use super::types::{ExternalTool, ToolPathCandidate, ToolRegistry};
use std::path::PathBuf;

pub fn discover_tool(tool: &dyn ExternalTool, registry: &ToolRegistry) -> Vec<ToolPathCandidate> {
    let mut candidates = Vec::new();

    if let Some(entry) = registry.tools.get(tool.id().as_str()) {
        if entry.custom_path {
            let path = PathBuf::from(&entry.path);
            candidates.push(ToolPathCandidate {
                path: path.clone(),
                source: "registry (custom)".to_string(),
                exists: path.exists(),
                is_executable: is_executable_path(&path),
            });
        }
    }

    for search_path in tool.default_search_paths() {
        for name in tool.executable_names() {
            let candidate = search_path.join(name);
            if !candidates.iter().any(|c| c.path == candidate) {
                let exists = candidate.exists();
                candidates.push(ToolPathCandidate {
                    path: candidate.clone(),
                    source: format!("system ({})", search_path.display()),
                    exists,
                    is_executable: exists && is_executable_path(&candidate),
                });
            }
        }
    }

    for name in tool.executable_names() {
        if let Some(full_path) = which_on_path(name) {
            if !candidates.iter().any(|c| c.path == full_path) {
                candidates.push(ToolPathCandidate {
                    path: full_path,
                    source: "PATH".to_string(),
                    exists: true,
                    is_executable: true,
                });
            }
        }
    }

    candidates
}

pub fn find_best_candidate(
    tool: &dyn ExternalTool,
    registry: &ToolRegistry,
) -> Option<ToolPathCandidate> {
    let candidates = discover_tool(tool, registry);
    candidates.into_iter().find(|c| c.exists && c.is_executable)
}

fn is_executable_path(path: &std::path::Path) -> bool {
    if cfg!(windows) {
        path.extension()
            .and_then(|e| e.to_str())
            .map(|e| matches!(e.to_lowercase().as_str(), "exe" | "cmd" | "bat" | "com"))
            .unwrap_or(false)
    } else {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::metadata(path)
                .ok()
                .map(|m| m.permissions().mode() & 0o111 != 0)
                .unwrap_or(false)
        }
        #[cfg(not(unix))]
        {
            path.exists()
        }
    }
}

fn which_on_path(name: &str) -> Option<PathBuf> {
    let mut cmd = std::process::Command::new(if cfg!(windows) { "where" } else { "which" });
    crate::daemon::utils::hide_command_window(&mut cmd);
    if let Ok(output) = cmd.arg(name).output() {
        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let line = stdout.lines().next().unwrap_or("").trim();
            if !line.is_empty() {
                return Some(PathBuf::from(line));
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use crate::daemon::external_tools::ToolId;

    #[test]
    fn executable_names_windows() {
        let tool_id = ToolId::Ffmpeg;
        let names = match tool_id {
            ToolId::Ffmpeg => vec!["ffmpeg.exe"],
            ToolId::YtDlp => vec!["yt-dlp.exe"],
        };
        assert!(!names.is_empty());
    }
}
