use super::types::{ExternalTool, ToolId, ToolStatus};
use crate::daemon::utils::hide_command_window;
use std::process::Command;
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
pub struct HealthReport {
    pub tool_id: ToolId,
    pub status: ToolStatus,
    pub executable_works: bool,
    pub version_detected: Option<String>,
    pub version_compatible: bool,
    pub capabilities_detected: bool,
    pub error_message: Option<String>,
    pub check_duration: Duration,
}

pub fn check_health(tool: &dyn ExternalTool, path: &std::path::Path) -> HealthReport {
    let started = Instant::now();
    let mut report = HealthReport {
        tool_id: tool.id(),
        status: ToolStatus::Unknown,
        executable_works: false,
        version_detected: None,
        version_compatible: false,
        capabilities_detected: false,
        error_message: None,
        check_duration: Duration::ZERO,
    };

    if !path.exists() {
        report.status = ToolStatus::NotInstalled;
        report.error_message = Some(format!("Executable not found at {}", path.display()));
        report.check_duration = started.elapsed();
        return report;
    }

    match run_version_check(tool, path) {
        Ok(output) => {
            report.executable_works = true;
            if let Some(version) = tool.parse_version(&output) {
                report.version_detected = Some(version.to_string());
                report.version_compatible = version.is_compatible_with(&tool.minimum_version());
                if report.version_compatible {
                    report.status = ToolStatus::Installed;
                    report.capabilities_detected = true;
                } else {
                    report.status = ToolStatus::Incompatible;
                    report.error_message = Some(format!(
                        "Version {} is below minimum required {}",
                        version,
                        tool.minimum_version()
                    ));
                }
            } else {
                report.executable_works = true;
                report.status = ToolStatus::Broken;
                report.error_message = Some("Could not parse version from output".to_string());
            }
        }
        Err(e) => {
            report.error_message = Some(e);
            if path.exists() {
                report.status = ToolStatus::Broken;
            } else {
                report.status = ToolStatus::NotInstalled;
            }
        }
    }

    report.check_duration = started.elapsed();
    report
}

fn run_version_check(tool: &dyn ExternalTool, path: &std::path::Path) -> Result<String, String> {
    let timeout = tool.version_command_timeout();
    let args = tool.version_args();

    let mut cmd = Command::new(path);
    cmd.args(args);
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());
    hide_command_window(&mut cmd);

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("Failed to execute {}: {}", path.display(), e))?;

    let deadline = Instant::now() + timeout;

    let output = loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                use std::io::Read;
                let mut stdout_buf = Vec::new();
                let mut stderr_buf = Vec::new();
                if let Some(ref mut h) = child.stdout {
                    let _ = h.read_to_end(&mut stdout_buf);
                }
                if let Some(ref mut h) = child.stderr {
                    let _ = h.read_to_end(&mut stderr_buf);
                }
                break std::process::Output {
                    status,
                    stdout: stdout_buf,
                    stderr: stderr_buf,
                };
            }
            Ok(None) => {
                if Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(format!("Version check timed out after {:?}", timeout));
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(e) => return Err(format!("Version check failed: {}", e)),
        }
    };

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.is_empty() {
            return Err(format!("Version command failed: {}", stderr.trim()));
        }
    }

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    if stdout.trim().is_empty() {
        return Err("Version command returned empty output".to_string());
    }

    Ok(stdout)
}

pub fn probe_capabilities(tool: &dyn ExternalTool, path: &std::path::Path) -> Vec<String> {
    if !path.exists() {
        return Vec::new();
    }
    tool.capabilities().into_iter().map(|c| c.id).collect()
}
