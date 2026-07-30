use super::types::ProcessSpec;
use crate::daemon::utils::hide_command_window;
use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

#[derive(Debug)]
pub struct ProcessOutput {
    pub stdout: String,
    pub stderr: String,
    pub success: bool,
    pub exit_code: i32,
    pub duration: Duration,
}

pub fn run_tool(
    spec: &ProcessSpec,
    working_dir: Option<&PathBuf>,
) -> Result<ProcessOutput, String> {
    let started = Instant::now();

    let mut cmd = Command::new(&spec.program);
    cmd.args(&spec.args);
    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());
    hide_command_window(&mut cmd);

    if let Some(dir) = working_dir {
        cmd.current_dir(dir);
    }

    if !std::path::Path::new(&spec.program).exists() {
        return Err(format!("Program not found: {}", spec.program));
    }

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("Failed to spawn {}: {}", spec.program, e))?;

    let deadline = spec.timeout.map(|t| Instant::now() + t);

    let (tx, rx) = mpsc::channel();
    let stdout_thread = child.stdout.take().map(|mut r| {
        let tx = tx.clone();
        thread::spawn(move || {
            let mut buf = Vec::new();
            let _ = r.read_to_end(&mut buf);
            let _ = tx.send(("stdout", buf));
        })
    });
    let stderr_thread = child.stderr.take().map(|mut r| {
        let tx = tx.clone();
        thread::spawn(move || {
            let mut buf = Vec::new();
            let _ = r.read_to_end(&mut buf);
            let _ = tx.send(("stderr", buf));
        })
    });
    drop(tx);

    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s,
            Ok(None) => {
                if let Some(dl) = &deadline {
                    if Instant::now() >= *dl {
                        let _ = child.kill();
                        let _ = child.wait();
                        return Err(format!(
                            "Process timed out after {:?}",
                            spec.timeout.unwrap_or(Duration::from_secs(300))
                        ));
                    }
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(e) => return Err(format!("Process wait failed: {e}")),
        }
    };

    if let Some(h) = stdout_thread {
        let _ = h.join();
    }
    if let Some(h) = stderr_thread {
        let _ = h.join();
    }

    let mut stdout_buf = Vec::new();
    let mut stderr_buf = Vec::new();
    for (kind, buf) in &rx {
        match kind {
            "stdout" => stdout_buf = buf,
            "stderr" => stderr_buf = buf,
            _ => {}
        }
    }

    let elapsed = started.elapsed();
    Ok(ProcessOutput {
        stdout: String::from_utf8_lossy(&stdout_buf).to_string(),
        stderr: String::from_utf8_lossy(&stderr_buf).to_string(),
        success: status.success(),
        exit_code: status.code().unwrap_or(-1),
        duration: elapsed,
    })
}

pub fn run_tool_capture(
    program: &str,
    args: &[&str],
    timeout: Option<Duration>,
) -> Result<ProcessOutput, String> {
    run_tool(
        &ProcessSpec {
            program: program.to_owned(),
            args: args.iter().map(|s| (*s).to_owned()).collect(),
            timeout,
        },
        None,
    )
}
