use std::collections::HashSet;
use std::sync::atomic::Ordering;
use uuid::Uuid;

use super::{
    args, destination_from_body, remove_stale_parts_for, start_curl_process, task_from_body, Arc,
};
use crate::daemon::direct::DirectUrl;
use crate::daemon::engine::extractor::{EngineStatus, Extractor, ValidateError};
use crate::daemon::state::SharedState;
use crate::daemon::types::{CreateDownloadBody, Task};
use crate::daemon::utils::kill_process;
use crate::lock_or_err;

const MAX_TASKS: usize = 10_000;

pub async fn create_curl_task(
    state: &SharedState,
    body: &CreateDownloadBody,
) -> Result<Task, String> {
    let url = body.url.as_deref().unwrap_or("").trim();
    if url.starts_with("magnet:")
        || url.to_lowercase().ends_with(".torrent")
        || url.contains(".torrent?")
    {
        return Err("Torrent/magnet support requires a dedicated torrent engine; libcurl multi is for direct URL downloads.".to_owned());
    }
    let direct_url = DirectUrl::parse(url)?;
    let (_pinned_ip, resolve_entry) =
        crate::daemon::utils::is_safe_target_url_pinned(&direct_url.normalized)?;
    let url = direct_url.normalized.as_str();

    if let Err(integrity_error) =
        crate::daemon::engine_capabilities::validate_linked_libcurl_integrity()
    {
        log::warn!(
            "libcurl integrity discrepancy; continuing because per-download capabilities are validated separately: {integrity_error}"
        );
    }

    let mut direct_options = body.direct_options.clone().unwrap_or_default();
    crate::daemon::engine_capabilities::validate_curl_direct_options(
        &direct_options,
        body.resumable.unwrap_or(true),
    )?;

    let (name, output_path) = destination_from_body(body, url);
    crate::daemon::direct::FileWriter::ensure_parent(&output_path)?;
    let fail_with_body_supported =
        crate::daemon::engine_capabilities::curl_supports_flag("--fail-with-body");
    // Validate curl args (input validation) and pin DNS against rebinding.
    let mut curl_args =
        args::build_curl_args_with_capabilities(body, &output_path, fail_with_body_supported)?;
    curl_args.push("--resolve".to_owned());
    curl_args.push(resolve_entry.clone());
    let mut existing_resolve: Vec<serde_json::Value> = direct_options
        .remove("resolve")
        .and_then(|v| v.as_array().cloned())
        .unwrap_or_default();
    existing_resolve.push(resolve_entry.into());
    direct_options.insert("resolve".to_owned(), existing_resolve.into());
    drop(curl_args); // args are persisted via direct_options, not executed
    let id = Uuid::new_v4().to_string();
    let job = task_from_body(body, &id, name, &output_path, direct_options);
    let task = job.task.clone();
    // Hold curl_jobs + task_snapshot locks together so the capacity check
    // and insertions are atomic w.r.t. concurrent create calls.
    {
        let mut jobs = lock_or_err!(state.curl_jobs);
        let mut tasks = lock_or_err!(state.task_snapshot);
        if tasks.len() >= MAX_TASKS {
            return Err("Maximum number of tasks reached. Complete or delete some tasks before creating new ones.".to_owned());
        }
        jobs.insert(id.clone(), job);
        tasks.insert(id.clone(), task.clone());
    }
    state.mark_dirty();

    if body.start_immediately.unwrap_or(true) {
        start_curl_process(state, &id);
    }
    Ok(task)
}

pub async fn list_all_tasks(state: &SharedState) -> Vec<Task> {
    let current_gen = state
        .task_generation
        .load(std::sync::atomic::Ordering::Acquire);
    if let Ok(cache) = state.task_list_cache.read() {
        if let Some((gen, ref list)) = *cache {
            if gen == current_gen {
                return (**list).clone();
            }
        }
    }

    let mut tasks: Vec<Task> = lock_or_err!(state.media_jobs)
        .values()
        .map(|j| j.task.clone())
        .collect();
    tasks.extend(
        lock_or_err!(state.curl_jobs)
            .values()
            .map(|j| j.task.clone()),
    );

    let active_ids: HashSet<String> = tasks.iter().map(|t| t.id.clone()).collect();
    let mut snapshot = lock_or_err!(state.task_snapshot);
    for task in snapshot.values() {
        if !active_ids.contains(&task.id) {
            tasks.push(task.clone());
        }
    }

    let mut changed = snapshot.len() != tasks.len();
    if !changed {
        for task in &tasks {
            let same = snapshot.get(&task.id).is_some_and(|old| {
                old.status == task.status
                    && old.downloaded_bytes == task.downloaded_bytes
                    && old.size_bytes == task.size_bytes
                    && old.name == task.name
                    && old.save_path == task.save_path
                    && old.engine == task.engine
            });
            if !same {
                changed = true;
                break;
            }
        }
    }
    if changed {
        *snapshot = tasks.iter().map(|t| (t.id.clone(), t.clone())).collect();
        state.mark_dirty();
    }
    let result = Arc::new(tasks);
    if let Ok(mut cache) = state.task_list_cache.write() {
        *cache = Some((current_gen, result.clone()));
    }
    (*result).clone()
}

pub fn get_task(state: &SharedState, id: &str) -> Option<Task> {
    if let Some(job) = lock_or_err!(state.media_jobs).get(id) {
        return Some(job.task.clone());
    }
    if let Some(job) = lock_or_err!(state.curl_jobs).get(id) {
        return Some(job.task.clone());
    }
    lock_or_err!(state.task_snapshot).get(id).cloned()
}

pub async fn pause_task(state: &SharedState, id: &str) -> Result<Task, String> {
    {
        let mut jobs = lock_or_err!(state.media_jobs);
        if let Some(job) = jobs.get_mut(id) {
            if let Some(pid) = job.child {
                kill_process(pid);
                job.child = None;
            }
            job.task.status = "paused".to_owned();
            job.task.speed_bytes_per_sec = 0;
            job.task.engine_status = Some("paused".to_owned());
            let task = job.task.clone();
            drop(jobs);
            lock_or_err!(state.task_snapshot).insert(id.to_owned(), task.clone());
            state.mark_dirty();
            return Ok(task);
        }
    }

    {
        let mut jobs = lock_or_err!(state.curl_jobs);
        if let Some(job) = jobs.get_mut(id) {
            job.cancel_token.store(true, Ordering::Release);
            if job.task.status == "downloading" {
                job.task.status = "pausing".to_owned();
                job.task.engine_status = Some("pausing".to_owned());
            } else {
                job.task.status = "paused".to_owned();
                job.task.engine_status = Some("paused".to_owned());
            }
            job.task.speed_bytes_per_sec = 0;
            let task = job.task.clone();
            drop(jobs);
            lock_or_err!(state.task_snapshot).insert(id.to_owned(), task.clone());
            state.mark_dirty();
            return Ok(task);
        }
    }

    let snapshot = lock_or_err!(state.task_snapshot);
    snapshot
        .get(id)
        .cloned()
        .ok_or_else(|| "Task not found".to_owned())
}

pub async fn resume_task(state: &SharedState, id: &str) -> Result<Task, String> {
    {
        let mut jobs = lock_or_err!(state.media_jobs);
        if let Some(job) = jobs.get_mut(id) {
            let needs_start = job.task.status != "completed";
            if needs_start {
                job.task.status = "downloading".to_owned();
                job.task.engine_status = Some("resuming".to_owned());
            }
            drop(jobs);
            if needs_start {
                crate::daemon::ytdlp::start_ytdlp_process(state, id);
            }
            state.mark_dirty();
            let jobs = lock_or_err!(state.media_jobs);
            return jobs
                .get(id)
                .map(|j| j.task.clone())
                .ok_or_else(|| "Task not found after resume".to_owned());
        }
    }

    {
        let mut jobs = lock_or_err!(state.curl_jobs);
        if let Some(job) = jobs.get_mut(id) {
            if job.task.status == "completed" {
                return Err(format!(
                    "Cannot resume '{}': download is already completed.",
                    job.task.name
                ));
            }
            if matches!(
                job.task.status.as_str(),
                "downloading" | "pausing" | "stopping"
            ) {
                return Err(format!("Cannot resume '{}': current state is {}. Wait until the previous libcurl worker has stopped.", job.task.name, job.task.status));
            }
            job.task.status = "queued".to_owned();
            job.task.engine_status = Some("resume-requested".to_owned());
            job.task.error_message = None;
            let task = job.task.clone();
            drop(jobs);
            start_curl_process(state, id);
            state.mark_dirty();
            return Ok(task);
        }
    }

    Err("Task not found".to_owned())
}

/// Characters that may not appear in a file name on any supported platform
/// (Windows-reserved set is the strictest, so it is used universally).
fn sanitize_new_name(raw: &str) -> Result<String, String> {
    let name = raw.trim();
    if name.is_empty() {
        return Err("Name cannot be empty".to_owned());
    }
    if name.len() > 240 {
        return Err("Name is too long (max 240 characters)".to_owned());
    }
    if name.chars().any(|c| {
        matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|') || c.is_control()
    }) {
        return Err(format!("Name contains forbidden characters: {name}"));
    }
    if name == "." || name == ".." {
        return Err("Invalid name".to_owned());
    }
    // Reject names whose NFC-normalized form introduces path separators
    // or contains ".." components (Unicode normalization attack vector).
    use unicode_normalization::UnicodeNormalization;
    for ch in name.chars() {
        let nfc: String = ch.nfc().collect();
        if nfc.contains('/') || nfc.contains('\\') {
            return Err(format!("Name contains forbidden characters: {name}"));
        }
    }
    let normalized: String = name.nfc().collect();
    for component in std::path::Path::new(&normalized).components() {
        if matches!(component, std::path::Component::ParentDir) {
            return Err("Name contains path traversal components".to_owned());
        }
    }
    Ok(name.to_owned())
}

/// Rename the on-disk destination (completed or partial) to match a new task
/// name, keeping the original extension when the new name has none. Returns
/// the new save path on success.
fn rename_destination_on_disk(
    old_path: &std::path::Path,
    new_name: &str,
) -> Option<std::path::PathBuf> {
    let parent = old_path.parent()?;
    let mut candidate = parent.join(new_name);
    // Keep the previous extension when the user typed a bare stem.
    if candidate.extension().is_none() {
        if let Some(ext) = old_path.extension().and_then(|e| e.to_str()) {
            candidate.set_extension(ext);
        }
    }
    if candidate == old_path {
        return Some(old_path.to_path_buf());
    }
    if candidate.exists() {
        // Never clobber an existing file during rename.
        return None;
    }
    if old_path.exists() {
        std::fs::rename(old_path, &candidate).ok()?;
    }
    Some(candidate)
}

/// Clear stored conditional-request validators after the task URL changes so
/// a resume against the refreshed link does not trigger 412/304 loops.
fn clear_stale_validators(
    direct_options: &mut std::collections::HashMap<String, serde_json::Value>,
) {
    for key in ["etag", "lastModified", "digestSha256"] {
        direct_options.remove(key);
    }
}

pub async fn update_task_metadata(
    state: &SharedState,
    id: &str,
    name: Option<String>,
    url: Option<String>,
) -> Result<Task, String> {
    let new_name = match name.as_deref() {
        Some(raw) => Some(sanitize_new_name(raw)?),
        None => None,
    };
    let new_url = match url.as_deref() {
        Some(raw) => {
            let trimmed = raw.trim();
            if trimmed.is_empty() {
                return Err("URL cannot be empty".to_owned());
            }
            Some(trimmed.to_owned())
        }
        None => None,
    };
    if new_name.is_none() && new_url.is_none() {
        return Err("Nothing to update".to_owned());
    }

    // Media (yt-dlp) tasks.
    {
        let mut jobs = lock_or_err!(state.media_jobs);
        if let Some(job) = jobs.get_mut(id) {
            if matches!(
                job.task.status.as_str(),
                "downloading" | "pausing" | "stopping"
            ) {
                return Err("Stop the download before editing it".to_owned());
            }
            if let Some(ref u) = new_url {
                if !(u.starts_with("http://") || u.starts_with("https://")) {
                    return Err("Only http(s) URLs are supported for media tasks".to_owned());
                }
                job.task.url = u.clone();
            }
            if let Some(ref n) = new_name {
                job.task.name = n.clone();
                if let Some(new_path) =
                    rename_destination_on_disk(std::path::Path::new(&job.task.save_path), n)
                {
                    job.task.save_path = new_path.to_string_lossy().to_string();
                }
            }
            let task = job.task.clone();
            drop(jobs);
            lock_or_err!(state.task_snapshot).insert(id.to_owned(), task.clone());
            state.mark_dirty();
            return Ok(task);
        }
    }

    // Direct (libcurl) tasks.
    {
        let mut jobs = lock_or_err!(state.curl_jobs);
        if let Some(job) = jobs.get_mut(id) {
            if matches!(
                job.task.status.as_str(),
                "downloading" | "pausing" | "stopping"
            ) {
                return Err("Stop the download before editing it".to_owned());
            }
            if let Some(ref u) = new_url {
                let parsed = DirectUrl::parse(u)?;
                crate::daemon::utils::is_safe_target_url(&parsed.normalized)?;
                let old_url = std::mem::replace(&mut job.task.url, parsed.normalized.clone());
                if old_url != parsed.normalized {
                    clear_stale_validators(&mut job.direct_options);
                    if !old_url.is_empty() {
                        state.metadata_cache.remove(&old_url);
                    }
                }
            }
            if let Some(ref n) = new_name {
                job.task.name = n.clone();
                if let Some(new_path) =
                    rename_destination_on_disk(std::path::Path::new(&job.task.save_path), n)
                {
                    job.task.save_path = new_path.to_string_lossy().to_string();
                }
            }
            let task = job.task.clone();
            drop(jobs);
            lock_or_err!(state.task_snapshot).insert(id.to_owned(), task.clone());
            state.mark_dirty();
            return Ok(task);
        }
    }

    Err("Task not found".to_owned())
}

/// Re-download a task from scratch: removes the existing output (and any
/// segment parts), resets progress, clears stale validators, and restarts.
pub async fn redownload_task(state: &SharedState, id: &str) -> Result<Task, String> {
    {
        let out = {
            let mut jobs = lock_or_err!(state.media_jobs);
            if let Some(job) = jobs.get_mut(id) {
                if let Some(pid) = job.child.take() {
                    kill_process(pid);
                }
                let path = std::path::PathBuf::from(&job.task.save_path);
                let save_path_empty = job.task.save_path.is_empty();
                job.task.status = "downloading".to_owned();
                job.task.downloaded_bytes = 0;
                job.task.speed_bytes_per_sec = 0;
                job.task.time_left_seconds = 0;
                job.task.error_message = None;
                job.task.engine_status = Some("redownload-requested".to_owned());
                Some((job.task.clone(), path, save_path_empty))
            } else {
                None
            }
        };
        if let Some((task, path, save_path_empty)) = out {
            if !save_path_empty {
                for attempt in 0..10 {
                    if std::fs::remove_file(&path).is_ok() {
                        break;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(200 * (1 << attempt)))
                        .await;
                }
            }
            lock_or_err!(state.task_snapshot).insert(id.to_owned(), task.clone());
            state.mark_dirty();
            crate::daemon::ytdlp::start_ytdlp_process(state, id);
            return Ok(task);
        }
    }

    {
        let out = {
            let mut jobs = lock_or_err!(state.curl_jobs);
            if let Some(job) = jobs.get_mut(id) {
                job.cancel_token.store(true, Ordering::Release);
                job.run_generation.fetch_add(1, Ordering::Release);
                let path = std::path::PathBuf::from(&job.task.save_path);
                clear_stale_validators(&mut job.direct_options);
                job.task.status = "queued".to_owned();
                job.task.downloaded_bytes = 0;
                job.task.speed_bytes_per_sec = 0;
                job.task.time_left_seconds = 0;
                job.task.error_message = None;
                job.task.engine_status = Some("redownload-requested".to_owned());
                job.task.segments = crate::daemon::utils::build_segments(
                    job.task.connections,
                    job.task.size_bytes,
                    0,
                    0,
                );
                Some((job.task.clone(), path))
            } else {
                None
            }
        };
        if let Some((task, path)) = out {
            let mut removed = false;
            for attempt in 0..10 {
                if std::fs::remove_file(&path).is_ok() {
                    removed = true;
                    break;
                }
                tokio::time::sleep(std::time::Duration::from_millis(200 * (1 << attempt))).await;
            }
            if !removed {
                log::warn!("Task {id}: remove_file failed on redownload after 10 retries");
            }
            remove_stale_parts_for(&path);
            lock_or_err!(state.task_snapshot).insert(id.to_owned(), task.clone());
            state.mark_dirty();
            start_curl_process(state, id);
            return Ok(task);
        }
    }

    Err("Task not found".to_owned())
}

pub async fn delete_task(state: &SharedState, id: &str, delete_files: bool) -> Result<(), String> {
    {
        let entry = {
            let mut jobs = lock_or_err!(state.media_jobs);
            if let Some(job) = jobs.remove(id) {
                if let Some(pid) = job.child {
                    kill_process(pid);
                }
                Some((std::path::PathBuf::from(&job.task.save_path), job.task.url))
            } else {
                None
            }
        };
        if let Some((path, url)) = entry {
            state.priority_queue.remove(id);
            state.bandwidth_manager.remove_task_limit(id);
            if !url.is_empty() {
                state.metadata_cache.remove(&url);
            }
            if delete_files {
                for attempt in 0..10 {
                    if std::fs::remove_file(&path).is_ok() {
                        break;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(200 * (1 << attempt)))
                        .await;
                }
            }
            if let Ok(mut trackers) = state.engine_trackers.write() {
                trackers.remove(id);
            }
            lock_or_err!(state.task_snapshot).remove(id);
            state.mark_dirty();
            return Ok(());
        }
    }

    {
        let entry = {
            let mut jobs = lock_or_err!(state.curl_jobs);
            if let Some(job) = jobs.get_mut(id) {
                job.cancel_token.store(true, Ordering::Release);
                job.run_generation.fetch_add(1, Ordering::Release);
            }
            if let Ok(mut trackers) = state.engine_trackers.write() {
                trackers.remove(id);
            }
            // Remove from snapshot before curl_jobs to prevent ghost task.
            lock_or_err!(state.task_snapshot).remove(id);
            let job = jobs.remove(id);
            job.map(|job| (std::path::PathBuf::from(&job.task.save_path), job.task.url))
        };
        if let Some((path, url)) = entry {
            state.priority_queue.remove(id);
            state.bandwidth_manager.remove_task_limit(id);
            if !url.is_empty() {
                state.metadata_cache.remove(&url);
            }
            if delete_files {
                for attempt in 0..10 {
                    if std::fs::remove_file(&path).is_ok() {
                        break;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(200 * (1 << attempt)))
                        .await;
                }
                remove_stale_parts_for(&path);
            }
            state.mark_dirty();
            return Ok(());
        }
    }
    if lock_or_err!(state.task_snapshot).remove(id).is_some() {
        state.mark_dirty();
    }
    Ok(())
}

pub fn curl_version() -> String {
    let v = ::curl::Version::get();
    format!("libcurl {}", v.version())
}

pub struct CurlExtractor;

impl Extractor for CurlExtractor {
    fn id(&self) -> &'static str {
        "libcurl-multi"
    }

    fn can_handle(&self, url: &str, has_media_options: bool) -> bool {
        if has_media_options {
            return false;
        }
        url.starts_with("http://")
            || url.starts_with("https://")
            || url.starts_with("ftp://")
            || url.starts_with("ftps://")
            || url.starts_with("sftp://")
            || url.starts_with("scp://")
    }

    fn validate(&self, body: &CreateDownloadBody) -> Result<(), ValidateError> {
        let url = body.url.as_deref().unwrap_or("").trim();
        if url.is_empty() {
            return Err(ValidateError("Missing url".into()));
        }
        if url.starts_with("magnet:") || url.to_lowercase().ends_with(".torrent") {
            return Err(ValidateError(
                "Torrent/magnet requires a dedicated torrent engine".into(),
            ));
        }
        let direct_options = body.direct_options.clone().unwrap_or_default();
        crate::daemon::engine_capabilities::validate_curl_direct_options(
            &direct_options,
            body.resumable.unwrap_or(true),
        )
        .map_err(ValidateError)?;
        Ok(())
    }

    fn engine_status(&self, _state: &SharedState) -> EngineStatus {
        let v = ::curl::Version::get();
        EngineStatus {
            id: "libcurl-multi".to_owned(),
            name: "libcurl-multi".to_owned(),
            available: true,
            version: Some(v.version().to_owned()),
            features: vec![
                "direct-http".to_owned(),
                "segmented".to_owned(),
                "range-requests".to_owned(),
            ],
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::daemon::curl::{build_curl_args, drive_multi_socket, split_ranges, CurlMultiGuard};
    use crate::daemon::types::CreateDownloadBody;
    use ::curl::easy::Easy2;
    use std::io::Read;
    use std::io::Write;
    use std::net::TcpListener;
    use std::sync::atomic::AtomicBool;
    use std::sync::{Arc, Mutex};
    use std::thread;
    use std::time::Duration;

    fn base_body() -> CreateDownloadBody {
        CreateDownloadBody {
            url: Some("https://example.com/file.bin".to_string()),
            name: Some("file.bin".to_string()),
            file_type: None,
            size_bytes: Some(1000),
            category: None,
            queue_id: None,
            connections: Some(24),
            resumable: Some(true),
            save_path: Some("C:/Downloads/file.bin".to_string()),
            description: None,
            referer: Some("https://example.com/page".to_string()),
            start_immediately: Some(false),
            direct_options: None,
            media_options: None,
        }
    }

    fn has_pair(args: &[String], flag: &str, value: &str) -> bool {
        args.windows(2)
            .any(|pair| pair[0] == flag && pair[1] == value)
    }

    #[test]
    fn build_curl_args_applies_direct_settings() {
        let mut direct_options = std::collections::HashMap::new();
        direct_options.insert(
            "headers".to_string(),
            serde_json::json!("Authorization: Bearer token\nX-Test: yes"),
        );
        direct_options.insert("cookies".to_string(), serde_json::json!("sid=abc"));
        direct_options.insert("userAgent".to_string(), serde_json::json!("NOVA-Test"));
        direct_options.insert("sourceAddress".to_string(), serde_json::json!("10.8.0.2"));
        direct_options.insert("retryCount".to_string(), serde_json::json!(5));
        direct_options.insert("timeoutSec".to_string(), serde_json::json!(45));
        direct_options.insert("allowOverwrite".to_string(), serde_json::json!(false));
        direct_options.insert("compressed".to_string(), serde_json::json!(true));

        let mut body = base_body();
        body.direct_options = Some(direct_options);

        let args = build_curl_args(&body, std::path::Path::new("C:/Downloads/file.bin")).unwrap();

        assert!(args.contains(&"--location".to_string()));
        assert!(has_pair(&args, "--output", "C:/Downloads/file.bin"));
        assert!(has_pair(&args, "--user-agent", "NOVA-Test"));
        assert!(has_pair(&args, "--interface", "10.8.0.2"));
        assert!(has_pair(&args, "--retry", "5"));
        assert!(has_pair(&args, "--max-time", "45"));
        assert!(has_pair(&args, "--referer", "https://example.com/page"));
        assert!(has_pair(&args, "--header", "Authorization: Bearer token"));
        assert!(has_pair(&args, "--header", "X-Test: yes"));
        assert!(has_pair(&args, "--cookie", "sid=abc"));
        assert!(args.contains(&"--no-clobber".to_string()));
        assert!(args.contains(&"--compressed".to_string()));
        assert_eq!(
            args.last().map(String::as_str),
            Some("https://example.com/file.bin")
        );
    }

    #[test]
    fn build_curl_args_rejects_torrents() {
        let mut body = base_body();
        body.url = Some("magnet:?xt=urn:btih:abc".to_string());
        assert!(build_curl_args(&body, std::path::Path::new("file.torrent")).is_err());
    }

    #[test]
    fn build_curl_args_accepts_browser_user_agent() {
        let mut direct_options = std::collections::HashMap::new();
        let user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) NOVA/0.1.0";
        direct_options.insert("userAgent".to_string(), serde_json::json!(user_agent));

        let mut body = base_body();
        body.direct_options = Some(direct_options);

        let args = build_curl_args(&body, std::path::Path::new("C:/Downloads/file.bin")).unwrap();

        assert!(has_pair(&args, "--user-agent", user_agent));
    }

    #[derive(Clone)]
    struct MemorySink {
        data: Arc<Mutex<Vec<u8>>>,
    }

    impl ::curl::easy::Handler for MemorySink {
        fn write(&mut self, data: &[u8]) -> Result<usize, ::curl::easy::WriteError> {
            self.data.lock().unwrap().extend_from_slice(data);
            Ok(data.len())
        }
    }

    #[test]
    fn multi_socket_runtime_downloads_local_response() {
        let expected = b"hello multi_socket".to_vec();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let server_body = expected.clone();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut request = [0u8; 1024];
            let _ = stream.read(&mut request);
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                server_body.len()
            );
            stream.write_all(response.as_bytes()).unwrap();
            stream.write_all(&server_body).unwrap();
        });

        let received = Arc::new(Mutex::new(Vec::new()));
        let mut easy = Easy2::new(MemorySink {
            data: received.clone(),
        });
        easy.url(&format!("http://{addr}/file.bin")).unwrap();
        easy.get(true).unwrap();

        let mut guard = CurlMultiGuard::new();
        let mut runtime = guard.attach_socket_runtime().unwrap();
        let handle = guard.add2(easy).unwrap();
        let handles = vec![handle];
        let cancel = AtomicBool::new(false);

        drive_multi_socket(
            guard.multi().unwrap(),
            &mut runtime,
            &handles,
            &cancel,
            "transfer",
            || {},
        )
        .unwrap();

        assert_eq!(handles[0].response_code().unwrap(), 200);
        assert_eq!(*received.lock().unwrap(), expected);
        server.join().unwrap();
    }

    #[test]
    fn split_ranges_are_contiguous() {
        let ranges = split_ranges(100, 6, std::path::Path::new("file.bin"));
        assert_eq!(ranges.first().unwrap().start, 0);
        assert_eq!(ranges.last().unwrap().end, 99);
        for pair in ranges.windows(2) {
            assert_eq!(pair[0].end + 1, pair[1].start);
        }
    }
}
