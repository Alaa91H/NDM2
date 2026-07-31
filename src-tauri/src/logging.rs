//! Application-wide logging setup.
//!
//! NOVA logs to a structured, rotating file under
//! `{data_dir}/logs/nova.log` and mirrors every record into an in-memory ring
//! buffer that the `/api/logs` daemon routes can query at runtime.
//!
//! The default verbosity is `Debug` in debug builds and `Info` in release
//! builds. It can be overridden at startup with the `NOVA_LOG_LEVEL`
//! environment variable (`off|error|warn|info|debug|trace`) or changed at
//! runtime through `PATCH /api/logs/level`.

use flexi_logger::writers::LogWriter;
use flexi_logger::{DeferredNow, FileSpec, Logger, LoggerHandle};
use log::{LevelFilter, Record};
use serde::Serialize;
use std::collections::VecDeque;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

/// Maximum number of log entries kept in the in-memory ring buffer.
pub const LOG_BUFFER_CAPACITY: usize = 5000;
/// Rotate the log file once it reaches this size (10 MiB).
pub const LOG_FILE_MAX_SIZE: u64 = 10 * 1024 * 1024;
/// Number of rotated log files to keep.
pub const LOG_FILES_TO_KEEP: usize = 10;

/// A single structured log record, as exposed by `/api/logs`.
#[derive(Debug, Clone, Serialize)]
pub struct LogEntry {
    /// RFC 3339 timestamp (UTC) of the record.
    pub timestamp: String,
    /// Uppercase level name, e.g. `DEBUG`.
    pub level: String,
    /// The module path of the emitting crate.
    pub target: String,
    /// Name of the thread that emitted the record.
    pub thread: String,
    /// The formatted message.
    pub message: String,
    /// Source location `file:line` when the record carries it.
    pub location: Option<String>,
}

impl LogEntry {
    /// Numeric rank so callers can filter by minimum level.
    fn level_rank(level: &str) -> u8 {
        match level {
            "TRACE" => 1,
            "DEBUG" => 2,
            "INFO" => 3,
            "WARN" => 4,
            "ERROR" => 5,
            _ => 3,
        }
    }

    /// Whether this entry is at least as severe as `min_level`.
    pub(crate) fn meets_level(&self, min_level: LevelFilter) -> bool {
        let min_rank = match min_level {
            LevelFilter::Off => 5,
            LevelFilter::Error => 5,
            LevelFilter::Warn => 4,
            LevelFilter::Info => 3,
            LevelFilter::Debug => 2,
            LevelFilter::Trace => 1,
        };
        Self::level_rank(&self.level) >= min_rank
    }
}

struct LoggerState {
    handle: LoggerHandle,
    ring: Arc<Mutex<VecDeque<LogEntry>>>,
    dir: PathBuf,
}

static STATE: OnceLock<LoggerState> = OnceLock::new();

fn state() -> Option<&'static LoggerState> {
    STATE.get()
}

/// Directory used when no explicit data dir is available yet.
fn default_log_dir() -> PathBuf {
    let home = std::env::var("APPDATA")
        .or_else(|_| std::env::var("USERPROFILE"))
        .or_else(|_| std::env::var("HOME"))
        .unwrap_or_else(|_| ".".to_owned());
    Path::new(&home).join("nova-download-manager").join("logs")
}

fn resolve_level() -> LevelFilter {
    let default = if cfg!(debug_assertions) {
        LevelFilter::Debug
    } else {
        LevelFilter::Info
    };
    std::env::var("NOVA_LOG_LEVEL")
        .ok()
        .and_then(|raw| {
            let lower = raw.trim().to_ascii_lowercase();
            match lower.as_str() {
                "off" => Some(LevelFilter::Off),
                "error" => Some(LevelFilter::Error),
                "warn" => Some(LevelFilter::Warn),
                "info" => Some(LevelFilter::Info),
                "debug" => Some(LevelFilter::Debug),
                "trace" => Some(LevelFilter::Trace),
                _ => None,
            }
        })
        .unwrap_or(default)
}

/// Structured, tab-free single-line format for the rotating log files.
fn format_file_line(
    w: &mut dyn Write,
    now: &mut DeferredNow,
    record: &Record,
) -> std::io::Result<()> {
    let ts = now.format_rfc3339();
    let thread = std::thread::current()
        .name()
        .unwrap_or("<unnamed>")
        .to_owned();
    let location = record
        .file()
        .zip(record.line())
        .map(|(file, line)| format!(" at {file}:{line}"))
        .unwrap_or_default();
    writeln!(
        w,
        "[{ts}] [{level}] [{thread}] [{target}]{location} {msg}",
        level = record.level(),
        target = record.target(),
        msg = record.args(),
    )
}

/// A flexi_logger target that pushes structured entries into the ring buffer.
struct RingBufferWriter {
    ring: Arc<Mutex<VecDeque<LogEntry>>>,
}

impl LogWriter for RingBufferWriter {
    fn write(&self, now: &mut DeferredNow, record: &Record) -> std::io::Result<()> {
        let entry = LogEntry {
            timestamp: now.format_rfc3339(),
            level: record.level().as_str().to_owned(),
            target: record.target().to_owned(),
            thread: std::thread::current()
                .name()
                .unwrap_or("<unnamed>")
                .to_owned(),
            message: record.args().to_string(),
            location: record
                .file()
                .zip(record.line())
                .map(|(file, line)| format!("{file}:{line}")),
        };
        if let Ok(mut buffer) = self.ring.lock() {
            if buffer.len() == LOG_BUFFER_CAPACITY {
                buffer.pop_front();
            }
            buffer.push_back(entry);
        }
        Ok(())
    }

    fn flush(&self) -> std::io::Result<()> {
        Ok(())
    }
}

/// Initialize the global logger with the default data directory.
/// Safe to call multiple times; only the first call takes effect.
pub fn init_default() {
    let _ = init(default_log_dir());
}

/// Initialize the global logger, writing rotating structured logs to
/// `log_dir` and mirroring records into the in-memory ring buffer.
///
/// If the log directory cannot be used, falls back to a ring-buffer-only
/// logger so runtime log queries still work.
pub fn init(log_dir: PathBuf) -> Result<(), String> {
    if STATE.get().is_some() {
        return Ok(());
    }

    let ring: Arc<Mutex<VecDeque<LogEntry>>> =
        Arc::new(Mutex::new(VecDeque::with_capacity(LOG_BUFFER_CAPACITY)));

    let handle = if std::fs::create_dir_all(&log_dir).is_err() {
        build_ring_only_logger(ring.clone()).map_err(|e| {
            format!(
                "cannot create log dir {} and fallback logger failed: {e}",
                log_dir.display()
            )
        })?
    } else {
        match build_logger(log_dir.clone(), ring.clone()) {
            Ok(handle) => handle,
            Err(_) => build_ring_only_logger(ring.clone())
                .map_err(|e| format!("failed to initialize fallback logger: {e}"))?,
        }
    };

    let state = LoggerState {
        handle,
        ring,
        dir: log_dir.clone(),
    };
    let _ = STATE.set(state);
    log::info!(
        "Logging initialized (level={}) file={}",
        current_level(),
        log_dir.join("nova.log").display()
    );
    Ok(())
}

fn build_logger(
    log_dir: PathBuf,
    ring: Arc<Mutex<VecDeque<LogEntry>>>,
) -> Result<LoggerHandle, flexi_logger::FlexiLoggerError> {
    Logger::with(resolve_level())
        .log_to_file_and_writer(
            FileSpec::default().directory(&log_dir).basename("nova"),
            Box::new(RingBufferWriter { ring }),
        )
        .rotate(
            flexi_logger::Criterion::Size(LOG_FILE_MAX_SIZE),
            flexi_logger::Naming::Timestamps,
            flexi_logger::Cleanup::KeepLogFiles(LOG_FILES_TO_KEEP),
        )
        .append()
        .use_utc()
        .use_windows_line_ending()
        .format_for_files(format_file_line)
        .start()
}

fn build_ring_only_logger(
    ring: Arc<Mutex<VecDeque<LogEntry>>>,
) -> Result<LoggerHandle, flexi_logger::FlexiLoggerError> {
    Logger::with(resolve_level())
        .log_to_writer(Box::new(RingBufferWriter { ring }))
        .start()
}

/// Current effective global level.
pub fn current_level() -> LevelFilter {
    state()
        .and_then(|s| s.handle.current_max_level().ok())
        .unwrap_or_else(|| {
            std::env::var("NOVA_LOG_LEVEL")
                .ok()
                .and_then(|raw| raw.trim().parse().ok())
                .unwrap_or(LevelFilter::Off)
        })
}

/// Change the global level at runtime (e.g. via `PATCH /api/logs/level`).
pub fn set_level(level: LevelFilter) -> Result<(), String> {
    match state() {
        Some(s) => {
            s.handle.set_new_spec(level.into());
            log::info!("Log level changed to {level}");
            Ok(())
        }
        None => Err("logger is not initialized".to_owned()),
    }
}

/// Absolute path of the directory holding the rotating log files, if the
/// file logger is active.
pub fn log_dir() -> Option<PathBuf> {
    state().map(|s| s.dir.clone())
}

/// Return up to `limit` most-recent ring-buffer entries, optionally filtered
/// to `min_level` or more severe.
pub fn recent(limit: usize, min_level: Option<LevelFilter>) -> Vec<LogEntry> {
    let Some(state) = state() else {
        return Vec::new();
    };
    let guard = state
        .ring
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let filtered: Vec<LogEntry> = guard
        .iter()
        .filter(|entry| min_level.map_or(true, |min| entry.meets_level(min)))
        .cloned()
        .collect();
    let start = filtered.len().saturating_sub(limit);
    filtered[start..].to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn level_rank_orders_severity() {
        assert_eq!(LogEntry::level_rank("TRACE"), 1);
        assert_eq!(LogEntry::level_rank("DEBUG"), 2);
        assert_eq!(LogEntry::level_rank("INFO"), 3);
        assert_eq!(LogEntry::level_rank("WARN"), 4);
        assert_eq!(LogEntry::level_rank("ERROR"), 5);
    }

    #[test]
    fn meets_level_filters_by_minimum() {
        let entry = |level: &str| LogEntry {
            timestamp: "ts".to_owned(),
            level: level.to_owned(),
            target: "t".to_owned(),
            thread: "th".to_owned(),
            message: "m".to_owned(),
            location: None,
        };
        assert!(entry("INFO").meets_level(LevelFilter::Info));
        assert!(entry("WARN").meets_level(LevelFilter::Info));
        assert!(entry("DEBUG").meets_level(LevelFilter::Debug));
        assert!(!entry("DEBUG").meets_level(LevelFilter::Info));
        assert!(!entry("TRACE").meets_level(LevelFilter::Debug));
    }

    #[test]
    fn resolve_level_honors_env_override() {
        std::env::set_var("NOVA_LOG_LEVEL", "trace");
        assert_eq!(resolve_level(), LevelFilter::Trace);
        std::env::set_var("NOVA_LOG_LEVEL", "info");
        assert_eq!(resolve_level(), LevelFilter::Info);
        std::env::remove_var("NOVA_LOG_LEVEL");
    }

    #[test]
    fn format_file_line_emits_structured_single_line() {
        let args = format_args!("hello {value}", value = 7);
        let record = log::Record::builder()
            .file(Some("src/lib.rs"))
            .line(Some(42))
            .target("nova::test")
            .args(args)
            .level(log::Level::Info)
            .build();
        let mut now = DeferredNow::new();
        let mut out = Vec::new();
        format_file_line(&mut out, &mut now, &record).unwrap();
        let line = String::from_utf8(out).unwrap();
        assert!(line.starts_with('['));
        assert!(line.contains("] [INFO] ["));
        assert!(line.contains("[nova::test]"));
        assert!(line.contains("at src/lib.rs:42"));
        assert!(line.contains("hello 7"));
        assert_eq!(line.matches('\n').count(), 1);
    }
}
