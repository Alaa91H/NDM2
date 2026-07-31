use super::types::{ExternalTool, ToolId, UpdateInfo};
use crate::daemon::external_tools::registry;
use sha2::{Digest, Sha256};

pub fn check_latest_version(tool: &dyn ExternalTool, http: &reqwest::Client) -> UpdateInfo {
    let os_str = std::env::consts::OS;
    let arch_str = std::env::consts::ARCH;

    let os_pattern = match os_str {
        "windows" => "windows",
        "linux" => "linux",
        "macos" | "darwin" => "macos",
        _ => os_str,
    };

    let _arch_pattern = match arch_str {
        "x86_64" => "x86_64",
        "aarch64" | "arm64" => "aarch64",
        _ => arch_str,
    };

    match tool.id() {
        ToolId::YtDlp => {
            match check_ytdlp_latest(http, os_pattern) {
                Ok(info) => info,
                Err(_e) => UpdateInfo {
                    available: false,
                    current_version: None,
                    latest_version: None,
                    download_url: None,
                    release_notes: None,
                    published_at: None,
                },
            }
        }
        ToolId::Ffmpeg => match check_ffmpeg_latest(http, os_pattern) {
            Ok(info) => info,
            Err(_e) => UpdateInfo {
                available: false,
                current_version: None,
                latest_version: None,
                download_url: None,
                release_notes: Some("FFmpeg must be installed via your system package manager or from https://ffmpeg.org/download.html".to_owned()),
                published_at: None,
            },
        },
    }
}

fn check_ffmpeg_latest(_http: &reqwest::Client, os: &str) -> Result<UpdateInfo, String> {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {e}"))?;
    let response = client
        .get("https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest")
        .header("User-Agent", "NOVA-DownloadManager")
        .send()
        .map_err(|e| format!("GitHub API request failed: {e}"))?;

    let body = response
        .text()
        .map_err(|e| format!("Failed to read response: {e}"))?;
    let json: serde_json::Value =
        serde_json::from_str(&body).map_err(|e| format!("Failed to parse GitHub response: {e}"))?;

    let tag_name = json
        .get("tag_name")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_owned();

    let published_at = json
        .get("published_at")
        .and_then(|v| v.as_str())
        .map(std::borrow::ToOwned::to_owned);

    let mut download_url = None;
    if let Some(assets) = json.get("assets").and_then(|v| v.as_array()) {
        for asset in assets {
            let name = asset.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let url = asset
                .get("browser_download_url")
                .and_then(|v| v.as_str())
                .unwrap_or("");

            let matches_platform = match os {
                "windows" => {
                    name.contains("win64")
                        && name.contains("ffmpeg-master")
                        && name.ends_with(".zip")
                }
                "linux" => {
                    name.contains("linux64")
                        && name.contains("ffmpeg-master")
                        && name.ends_with(".tar.xz")
                }
                "macos" => {
                    name.contains("macos")
                        && name.contains("ffmpeg-master")
                        && name.ends_with(".zip")
                }
                _ => false,
            };

            if matches_platform && !url.is_empty() {
                download_url = Some(url.to_owned());
                break;
            }
        }
    }

    Ok(UpdateInfo {
        available: download_url.is_some(),
        current_version: None,
        latest_version: Some(tag_name),
        download_url,
        release_notes: Some("FFmpeg build from BtbN/FFmpeg-Builds".to_owned()),
        published_at,
    })
}

fn check_ytdlp_latest(_http: &reqwest::Client, os: &str) -> Result<UpdateInfo, String> {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {e}"))?;
    let response = client
        .get("https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")
        .header("User-Agent", "NOVA-DownloadManager")
        .send()
        .map_err(|e| format!("GitHub API request failed: {e}"))?;

    let body = response
        .text()
        .map_err(|e| format!("Failed to read response: {e}"))?;
    let json: serde_json::Value =
        serde_json::from_str(&body).map_err(|e| format!("Failed to parse GitHub response: {e}"))?;

    let tag_name = json
        .get("tag_name")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_owned();

    let published_at = json
        .get("published_at")
        .and_then(|v| v.as_str())
        .map(std::borrow::ToOwned::to_owned);

    let body_text = json
        .get("body")
        .and_then(|v| v.as_str())
        .map(std::borrow::ToOwned::to_owned);

    let mut download_url = None;
    if let Some(assets) = json.get("assets").and_then(|v| v.as_array()) {
        for asset in assets {
            let name = asset.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let url = asset
                .get("browser_download_url")
                .and_then(|v| v.as_str())
                .unwrap_or("");

            let matches_platform = match os {
                "windows" => name.contains("win") && name.ends_with(".exe"),
                "linux" => name.contains("linux") && !name.contains(".zip"),
                "macos" => name.contains("macos") || name.contains("darwin"),
                _ => false,
            };

            if matches_platform && !url.is_empty() {
                download_url = Some(url.to_owned());
                break;
            }
        }
    }

    Ok(UpdateInfo {
        available: download_url.is_some(),
        current_version: None,
        latest_version: Some(tag_name),
        download_url,
        release_notes: body_text,
        published_at,
    })
}

pub fn download_and_install(
    tool: &dyn ExternalTool,
    update_info: &UpdateInfo,
    install_dir: &std::path::Path,
    http: &reqwest::Client,
    data_dir: &str,
) -> Result<String, String> {
    let download_url = update_info
        .download_url
        .as_ref()
        .ok_or("No download URL available")?;

    if !install_dir.exists() {
        std::fs::create_dir_all(install_dir)
            .map_err(|e| format!("Failed to create install directory: {e}"))?;
    }

    let rt_handle = tokio::runtime::Handle::try_current()
        .map_err(|_| "No tokio runtime available for async operation".to_owned())?;
    let response = tokio::task::block_in_place(|| {
        rt_handle.block_on(async { http.get(download_url).send().await })
    })
    .map_err(|e| format!("Download request failed: {e}"))?;

    let bytes =
        tokio::task::block_in_place(|| rt_handle.block_on(async { response.bytes().await }))
            .map_err(|e| format!("Failed to read download: {e}"))?;

    // Compute SHA-256 checksum for integrity verification
    let checksum = {
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        format!("{:x}", hasher.finalize())
    };

    let filename = download_url
        .rsplit('/')
        .next()
        .unwrap_or("tool")
        .split(['/', '\\'])
        .next_back()
        .unwrap_or("tool");
    let dest_path = if filename.contains("..") || filename.is_empty() {
        let safe_name = format!("{}.exe", tool.id().as_str());
        install_dir.join(safe_name)
    } else {
        install_dir.join(filename)
    };

    std::fs::write(&dest_path, &bytes).map_err(|e| format!("Failed to write file: {e}"))?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&dest_path, std::fs::Permissions::from_mode(0o755));
    }

    let path_str = dest_path.display().to_string();

    let version_str = update_info.latest_version.as_deref().unwrap_or("unknown");

    let mut reg = registry::load_registry(data_dir);
    registry::register_tool(
        &mut reg,
        tool.id().as_str(),
        &path_str,
        Some(version_str),
        true,
        false,
    );
    if let Some(entry) = reg.tools.get_mut(tool.id().as_str()) {
        entry.checksum_sha256 = Some(checksum);
    }
    let _ = registry::save_registry(data_dir, &reg);

    Ok(path_str)
}

pub fn uninstall_tool(
    tool: &dyn ExternalTool,
    path: &std::path::Path,
    installed_by_app: bool,
    data_dir: &str,
) -> Result<(), String> {
    if !installed_by_app {
        return Err(format!(
            "{} was installed outside the application. The application cannot safely remove it automatically.",
            tool.name()
        ));
    }

    if path.exists() && path.is_file() {
        std::fs::remove_file(path)
            .map_err(|e| format!("Failed to remove {}: {}", path.display(), e))?;
    }

    let mut reg = registry::load_registry(data_dir);
    registry::unregister_tool(&mut reg, tool.id().as_str());
    let _ = registry::save_registry(data_dir, &reg);

    Ok(())
}
