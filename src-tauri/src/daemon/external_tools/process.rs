use super::types::ProcessSpec;
use crate::daemon::utils::hide_command_window;
use std::path::PathBuf;
use std::process::{Command, Stdio};
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

    let output = loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let mut stdout_buf = Vec::new();
                let mut stderr_buf = Vec::new();
                if let Some(ref mut child_stdout) = child.stdout {
                    use std::io::Read;
                    let _ = child_stdout.read_to_end(&mut stdout_buf);
                }
                if let Some(ref mut child_stderr) = child.stderr {
                    use std::io::Read;
                    let _ = child_stderr.read_to_end(&mut stderr_buf);
                }
                break std::process::Output {
                    status,
                    stdout: stdout_buf,
                    stderr: stderr_buf,
                };
            }
            Ok(None) => {
                if let Some(dl) = &deadline {
                    if Instant::now() >= *dl {
                        let _ = child.kill();
                        let _ = child.wait();
                        return Err(format!(
                            "Process timed out after {:?}",
                            spec.timeout.unwrap()
                        ));
                    }
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(e) => return Err(format!("Process wait failed: {}", e)),
        }
    };

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let elapsed = started.elapsed();

    Ok(ProcessOutput {
        stdout,
        stderr,
        success: output.status.success(),
        exit_code: output.status.code().unwrap_or(-1),
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
            program: program.to_string(),
            args: args.iter().map(|s| s.to_string()).collect(),
            timeout,
        },
        None,
    )
}
