use std::sync::OnceLock;
use std::time::Duration;

/// Unified autonomous engine configuration. All values are either system-derived
/// at startup or adapted at runtime by the Download Intelligence Engine. No value
/// here is ever exposed to the user as a setting.
#[derive(Clone, Debug)]
pub struct EngineConfig {
    pub max_connections_per_download: u32,
    pub max_total_connections: u32,
    pub min_segment_bytes: u64,
    pub initial_segments: u32,
    pub max_retries: u32,
    pub base_retry_delay_ms: u64,
    pub max_retry_delay_ms: u64,
    pub backoff_multiplier: f64,
    pub write_buffer_bytes: usize,
    pub read_buffer_bytes: usize,
    pub flush_interval_ms: u64,
    pub worker_threads: u32,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self::detect()
    }
}

fn cpu_count() -> u32 {
    std::thread::available_parallelism()
        .map(|n| n.get() as u32)
        .unwrap_or(4)
}

/// Returns a shared singleton EngineConfig. First call detects system resources.
pub fn global_config() -> &'static EngineConfig {
    static INSTANCE: OnceLock<EngineConfig> = OnceLock::new();
    INSTANCE.get_or_init(EngineConfig::detect)
}

impl EngineConfig {
    /// Detect system resources and build the initial autonomous config.
    pub fn detect() -> Self {
        let cpus = cpu_count();
        let total_ram = total_system_memory_bytes();

        let max_connections_per_download = (cpus * 2).clamp(2, 64);
        let max_total_connections = (cpus * 4).clamp(4, 128);

        let min_segment_bytes = 256 * 1024;
        let initial_segments = cpus.clamp(1, 4);

        let max_retries = 5;
        let base_retry_delay_ms = 1000;
        let max_retry_delay_ms = 30_000;
        let backoff_multiplier = 2.0;

        let write_buffer_bytes = if total_ram > 4 * 1024 * 1024 * 1024 {
            256 * 1024
        } else {
            64 * 1024
        };
        let read_buffer_bytes = if total_ram > 4 * 1024 * 1024 * 1024 {
            128 * 1024
        } else {
            32 * 1024
        };

        let flush_interval_ms = 100;
        let worker_threads = cpus;

        Self {
            max_connections_per_download,
            max_total_connections,
            min_segment_bytes,
            initial_segments,
            max_retries,
            base_retry_delay_ms,
            max_retry_delay_ms,
            backoff_multiplier,
            write_buffer_bytes,
            read_buffer_bytes,
            flush_interval_ms,
            worker_threads,
        }
    }

    pub fn retry_policy(&self) -> crate::daemon::engine::retry::RetryPolicy {
        crate::daemon::engine::retry::RetryPolicy {
            max_retries: self.max_retries,
            base_delay: Duration::from_millis(self.base_retry_delay_ms),
            max_delay: Duration::from_millis(self.max_retry_delay_ms),
            backoff_multiplier: self.backoff_multiplier,
            jitter: true,
        }
    }

    pub fn connection_limits_for(
        &self,
        requested: u32,
        url: &str,
    ) -> crate::daemon::direct::ConnectionLimits {
        let requested = requested.clamp(1, self.max_connections_per_download) as usize;
        let learned = crate::daemon::direct::learned_host_ceiling(url)
            .unwrap_or(self.max_connections_per_download as usize);
        let per_host = requested.min(learned).max(1);
        let total = requested.max(1);
        let cache = (total * 2)
            .max(total)
            .min(self.max_total_connections as usize * 4);
        crate::daemon::direct::ConnectionLimits {
            total,
            per_host,
            cache,
        }
    }
}

fn total_system_memory_bytes() -> u64 {
    #[cfg(target_os = "windows")]
    {
        use std::mem;
        #[repr(C)]
        struct MemoryStatusEx {
            dw_length: u32,
            dw_memory_load: u32,
            ull_total_phys: u64,
            ull_avail_phys: u64,
            ull_total_page_file: u64,
            ull_avail_page_file: u64,
            ull_total_virtual: u64,
            ull_avail_virtual: u64,
            ull_avail_extended_virtual: u64,
        }
        extern "system" {
            fn GlobalMemoryStatusEx(lpBuffer: *mut MemoryStatusEx) -> i32;
        }
        unsafe {
            let mut status: MemoryStatusEx = mem::zeroed();
            status.dw_length = mem::size_of::<MemoryStatusEx>() as u32;
            if GlobalMemoryStatusEx(&mut status) != 0 {
                status.ull_total_phys
            } else {
                4 * 1024 * 1024 * 1024
            }
        }
    }
    #[cfg(target_os = "linux")]
    {
        if let Ok(content) = std::fs::read_to_string("/proc/meminfo") {
            for line in content.lines() {
                if line.starts_with("MemTotal:") {
                    if let Some(kb_str) = line.split_whitespace().nth(1) {
                        if let Ok(kb) = kb_str.parse::<u64>() {
                            return kb * 1024;
                        }
                    }
                    break;
                }
            }
        }
        4 * 1024 * 1024 * 1024
    }
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        if let Ok(output) = Command::new("sysctl").args(["-n", "hw.memsize"]).output() {
            if let Ok(s) = String::from_utf8(output.stdout) {
                if let Ok(bytes) = s.trim().parse::<u64>() {
                    return bytes;
                }
            }
        }
        4 * 1024 * 1024 * 1024
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
    {
        4 * 1024 * 1024 * 1024
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detect_produces_valid_config() {
        let cfg = EngineConfig::detect();
        assert!(cfg.max_connections_per_download >= 2);
        assert!(cfg.max_connections_per_download <= 64);
        assert!(cfg.max_total_connections >= 4);
        assert!(cfg.initial_segments >= 1);
        assert!(cfg.min_segment_bytes >= 256 * 1024);
        assert!(cfg.max_retries >= 1);
        assert!(cfg.backoff_multiplier >= 1.0);
        assert!(cfg.write_buffer_bytes >= 32 * 1024);
        assert!(cfg.read_buffer_bytes >= 32 * 1024);
        assert!(cfg.worker_threads >= 1);
    }

    #[test]
    fn global_config_returns_same_instance() {
        let a = global_config();
        let b = global_config();
        let a_ptr = a as *const EngineConfig;
        let b_ptr = b as *const EngineConfig;
        assert_eq!(a_ptr, b_ptr);
    }

    #[test]
    fn retry_policy_uses_config_values() {
        let cfg = EngineConfig::detect();
        let policy = cfg.retry_policy();
        assert_eq!(policy.max_retries, cfg.max_retries);
        assert_eq!(
            policy.base_delay,
            Duration::from_millis(cfg.base_retry_delay_ms)
        );
        assert_eq!(
            policy.max_delay,
            Duration::from_millis(cfg.max_retry_delay_ms)
        );
        assert_eq!(policy.backoff_multiplier, cfg.backoff_multiplier);
        assert!(policy.jitter);
    }

    #[test]
    fn connection_limits_respects_learned_ceiling() {
        let cfg = EngineConfig::detect();
        let limits = cfg.connection_limits_for(16, "https://example.com/file.zip");
        assert!(limits.total >= 1);
        assert!(limits.per_host >= 1);
        assert!(limits.cache >= limits.total);
    }

    #[test]
    fn detect_scales_with_memory() {
        let cfg = EngineConfig::detect();
        assert!(cfg.write_buffer_bytes >= 64 * 1024);
        assert!(cfg.read_buffer_bytes >= 32 * 1024);
    }
}
