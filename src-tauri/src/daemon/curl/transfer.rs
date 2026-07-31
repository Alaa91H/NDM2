use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use ::curl::easy::Easy2;

use super::{
    apply_easy_options, create_easy_for_range_ext, drive_multi_socket, drive_multi_wait_perform,
    requested_connections, CurlMultiGuard, CurlTransferConfig, DirectDownloadPlan, HtmlHeadCapture,
    ResponseCapture, SegmentProgress,
};
use crate::daemon::direct::{
    EventLoopMode, FileWriter, IntegrityMetadata, IntegrityValidator, RetryPolicy, SegmentPlanner,
    SegmentRange as ByteRange,
};

use crate::daemon::engine::config::global_config;
use crate::daemon::engine::policy_engine::{DecisionCategory, DecisionContext};
use crate::daemon::state::SharedState;
use crate::daemon::types::{CurlJob, Segment};
use crate::daemon::utils::{build_segments, now_str};
use crate::lock_or_err;

fn build_decision_context(
    state: &SharedState,
    id: &str,
    plan: &DirectDownloadPlan,
    consecutive_failures: u32,
    current_speed: u64,
    supports_range: bool,
) -> DecisionContext {
    let host = {
        let url_str = &plan.url;
        if let Some(start) = url_str.find("://") {
            let rest = &url_str[start + 3..];
            if let Some(end) = rest.find('/') {
                &rest[..end]
            } else {
                rest
            }
        } else {
            ""
        }
    }
    .to_owned();

    // Acquire locks in documented order: curl_jobs (2), engine_trackers (4),
    // then die_orchestrator/resource_manager (10).
    let (active_downloads, total_downloaded, elapsed_secs) = {
        if let Ok(jobs) = state.curl_jobs.lock() {
            let active = jobs
                .values()
                .filter(|j| j.task.status == "downloading")
                .count() as u32;
            if let Some(job) = jobs.get(id) {
                (
                    active,
                    job.task.downloaded_bytes,
                    job.start_time.elapsed().as_secs_f64(),
                )
            } else {
                (active, 0u64, 0.0)
            }
        } else {
            (1u32, 0u64, 0.0)
        }
    };

    let attempted_segments = plan.connections;
    let mut completed_segments = 0u32;
    let mut failed_segments = 0u32;
    if let Ok(trackers) = state.engine_trackers.read() {
        if let Some(tracker) = trackers.get(id) {
            if let Some(seg) = tracker.segments.as_ref() {
                let info = seg.segments();
                completed_segments = info.iter().filter(|s| s.progress >= 1.0).count() as u32;
                failed_segments = info
                    .iter()
                    .filter(|s| !s.active && s.downloaded == 0 && s.total_bytes > 0)
                    .count() as u32;
            }
        }
    }

    let (server_stability, throughput_ceiling, per_conn_ceiling, is_rate_limited) = {
        if let Ok(die) = state.die_orchestrator.lock() {
            if let Ok(ps) = die.profile_store.lock() {
                let profile = ps.get_for_host(&host);
                let stability = profile.map_or(0.5, |p| p.stability_score as f32);
                let tput = profile.map_or(0, |p| p.throughput_ceiling);
                let per_conn = profile.map_or(0, |p| p.per_connection_ceiling);
                let rate_limited = ps.is_rate_limited(&host);
                (stability, tput, per_conn, rate_limited)
            } else {
                (0.5f32, 0u64, 0u64, false)
            }
        } else {
            (0.5f32, 0u64, 0u64, false)
        }
    };

    let (memory_pressure, cpu_pressure, disk_pressure) = {
        if let Ok(mut rm) = state.resource_manager.lock() {
            let snap = rm.snapshot();
            let disk_pressure = if snap.is_disk_bottlenecked() {
                0.8
            } else {
                0.1
            };
            (snap.memory_pressure, snap.cpu_usage_pct, disk_pressure)
        } else {
            (0.0, 0.0, 0.0)
        }
    };

    DecisionContext {
        category: DecisionCategory::Connection,
        host,
        file_size: plan.total_size,
        current_speed,
        current_connections: plan.connections,
        active_downloads,
        memory_pressure,
        cpu_pressure,
        disk_pressure,
        server_stability,
        is_rate_limited,
        consecutive_failures,
        supports_range,
        supports_resume: plan.resumable,
        protocol_multiplexed: false,
        rtt_us: 0,
        throughput_ceiling,
        per_connection_ceiling: per_conn_ceiling,
        attempted_segments,
        completed_segments,
        failed_segments,
        total_downloaded,
        elapsed_secs,
    }
}

pub fn task_from_body(
    body: &crate::daemon::types::CreateDownloadBody,
    id: &str,
    name: String,
    output_path: &Path,
    direct_options: HashMap<String, serde_json::Value>,
    args: Vec<String>,
) -> CurlJob {
    use crate::daemon::utils::infer_file_type;
    let category = body
        .category
        .clone()
        .unwrap_or_else(|| infer_file_type(&name).to_owned());
    let file_type = body
        .file_type
        .clone()
        .unwrap_or_else(|| infer_file_type(&name).to_owned());
    let initial_size = body.size_bytes.unwrap_or(0);
    // Blocking filesystem read (a single stat on the partial file). This fn is
    // synchronous and called from the async create_curl_task handler; kept here
    // intentionally so the caller can decide how to schedule it.
    let downloaded = FileWriter::current_size(output_path).unwrap_or(0);
    let task = crate::daemon::types::Task {
        id: id.to_owned(),
        name,
        url: body.url.as_deref().unwrap_or("").to_owned(),
        file_type,
        status: if body.start_immediately.unwrap_or(true) {
            "downloading"
        } else {
            "queued"
        }
        .to_owned(),
        size_bytes: initial_size,
        downloaded_bytes: downloaded,
        speed_bytes_per_sec: 0,
        time_left_seconds: 0,
        elapsed_seconds: 0,
        date_added: now_str(),
        category,
        queue_id: body.queue_id.clone().unwrap_or_else(|| "main".to_owned()),
        connections: requested_connections(body.connections),
        resumable: body.resumable.unwrap_or(true),
        save_path: output_path.to_string_lossy().to_string(),
        description: body
            .description
            .clone()
            .unwrap_or_else(|| "Direct download via libcurl multi".to_owned()),
        segments: build_segments(
            requested_connections(body.connections),
            initial_size,
            downloaded,
            0,
        ),
        referer: body.referer.clone(),
        engine: "libcurl-multi".to_owned(),
        engine_id: id.to_owned(),
        engine_status: Some(
            if body.start_immediately.unwrap_or(true) {
                "starting"
            } else {
                "queued"
            }
            .to_owned(),
        ),
        error_message: None,
    };
    CurlJob {
        task,
        direct_options,
        cancel_token: Arc::new(AtomicBool::new(false)),
        run_generation: Arc::new(AtomicU64::new(0)),
        start_time: Instant::now(),
        segment_prev_bytes: Vec::new(),
        args,
    }
}

pub fn plan_from_job(job: &CurlJob) -> DirectDownloadPlan {
    let config = CurlTransferConfig::from(&job.direct_options);
    let allow_overwrite = config.bool_("allowOverwrite").unwrap_or(true);
    let forced_single = config.bool_("forceSingleConnection").unwrap_or(false);
    let segmented = config.bool_("segmented").unwrap_or(true)
        && !forced_single
        && job.task.resumable
        && job.task.size_bytes >= global_config().min_segment_bytes
        && job.task.connections > 1;
    let etag = config.str_("etag").map(str::to_owned);
    let last_modified = config.str_("lastModified").map(str::to_owned);
    let (validator, validator_is_etag) = if let Some(et) = etag {
        (Some(et), true)
    } else if let Some(lm) = last_modified {
        (Some(lm), false)
    } else {
        (None, false)
    };
    let digest_sha256 = config.str_("digestSha256").map(str::to_owned);
    let link_mirrors = config.array_("linkMirrors");
    let mirror_priorities = config
        .array_u32_("mirrorPriorities")
        .unwrap_or_else(|| vec![1u32; link_mirrors.len()]);
    let preflight_resolved = config.bool_("preflightResolved").unwrap_or(false);
    let preflight_supports_range = config
        .bool_("preflightSupportsRange")
        .unwrap_or(job.task.resumable);
    DirectDownloadPlan {
        url: job.task.url.clone(),
        output_path: std::path::PathBuf::from(&job.task.save_path),
        total_size: job.task.size_bytes,
        connections: job
            .task
            .connections
            .clamp(1, global_config().max_connections_per_download),
        resumable: job.task.resumable,
        allow_overwrite,
        follow_redirects: config.bool_("location").unwrap_or(true),
        fail_on_error: config.bool_("failWithBody").unwrap_or(true),
        segmented,
        remove_on_error: config.bool_("removeOnError").unwrap_or(false),
        referer: config
            .str_("referer")
            .map(str::to_owned)
            .or_else(|| job.task.referer.clone()),
        config,
        validator,
        validator_is_etag,
        digest_sha256,
        link_mirrors,
        mirror_priorities,
        preflight_resolved,
        preflight_supports_range,
    }
}

pub fn split_ranges(total_size: u64, connections: u32, output_path: &Path) -> Vec<ByteRange> {
    SegmentPlanner::new(global_config().max_connections_per_download).plan(
        total_size,
        connections,
        output_path,
    )
}

const fn part_size(range: &ByteRange) -> u64 {
    range.len()
}

pub fn remove_stale_parts_for(output_path: &Path) {
    FileWriter::remove_stale_parts_for(output_path);
}

fn merge_parts(output_path: &Path, ranges: &[ByteRange]) -> Result<u64, String> {
    FileWriter::merge_parts(output_path, ranges)
}

fn resolve_effective_target(plan: &DirectDownloadPlan) -> (String, bool, PreflightData) {
    log::info!(
        "resolve_effective_target: url={}, total_size={}, preflight_resolved={}",
        plan.url,
        plan.total_size,
        plan.preflight_resolved
    );

    // ── RIE preflight skip ─────────────────────────────────────────────
    // When the RIE (Resource Intelligence Engine) has already resolved the
    // URL via reqwest with full anti-bot headers (Sec-Fetch-*, realistic
    // User-Agent, Cloudflare challenge bypass), skip the redundant curl
    // preflight entirely. The RIE already:
    //   - Followed all HTTP redirects and meta-refresh chains
    //   - Detected Cloudflare/Akamai bot challenges
    //   - Determined range support (206 vs 200)
    //   - Collected timing, TLS, and connection diagnostics
    //
    // Running a second preflight with curl would:
    //   1. Double latency (extra round-trip before download starts)
    //   2. Use a different TLS fingerprint (libcurl vs reqwest) that may
    //      trigger bot detection differently
    //   3. Lose cookie/session state from the RIE probe
    //   4. Risk receiving a Cloudflare challenge page on the second request
    if plan.preflight_resolved {
        log::info!(
            "resolve_effective_target: RIE already resolved {} — reusing preflight results (range={})",
            plan.url,
            plan.preflight_supports_range
        );
        let preflight = PreflightData {
            supports_range: plan.preflight_supports_range,
            ..Default::default()
        };
        return (plan.url.clone(), plan.preflight_supports_range, preflight);
    }

    // ── Fast path: skip the preflight HTTP request entirely for direct file
    //    URLs that already have a recognizable extension. The probe was adding
    //    5+ seconds of latency before every download start, and if libcurl's TLS
    //    was misconfigured it would fail silently and block the download.
    //
    //    The apply_fast_resolve path already validated the URL and derived the
    //    filename. We only need the meta-refresh / redirect resolution for URLs
    //    that might point to HTML interstitials — not for direct file links.
    if crate::daemon::utils::file_type_from_extension(
        &plan.url.rsplit('.').next().unwrap_or("").to_lowercase(),
    ) != "other"
        || plan.url.ends_with(".exe")
        || plan.url.ends_with(".zip")
        || plan.url.ends_with(".pdf")
    {
        log::debug!(
            "resolve_effective_target: skipping preflight for direct file URL {}",
            plan.url
        );
        let preflight = PreflightData {
            supports_range: true,
            ..Default::default()
        };
        return (plan.url.clone(), true, preflight);
    }

    log::info!(
        "resolve_effective_target: no known extension — running preflight HEAD/GET for {}",
        plan.url
    );
    const MAX_META_REFRESH_HOPS: usize = 5;
    let mut current = plan.url.clone();
    let mut preflight = PreflightData::default();

    for _hop in 0..=MAX_META_REFRESH_HOPS {
        let mut hop_plan = plan.clone();
        hop_plan.url = current.clone();

        let mut easy = Easy2::new(HtmlHeadCapture::default());
        if apply_easy_options(&mut easy, &hop_plan, Some((0, 0))).is_err() {
            log::warn!(
                "resolve_effective_target: apply_easy_options failed for hop, returning current={current}"
            );
            return (current, true, preflight);
        }
        let _ = easy.timeout(Duration::from_secs(5));

        if let Err(e) = easy.perform() {
            log::warn!(
                "resolve_effective_target: preflight perform failed for {current}: {e}, returning current={current}"
            );
            return (current, true, preflight);
        }

        let code = easy.response_code().unwrap_or(0);
        let effective = easy
            .effective_url()
            .ok()
            .flatten()
            .filter(|u| u.starts_with("http"))
            .map_or_else(|| current.clone(), |u| u.to_owned());

        if let Ok(t) = easy.total_time() {
            preflight.initial_rtt_us = t.as_micros() as u64;
        }
        if let Ok(t) = easy.appconnect_time() {
            let us = t.as_micros() as u64;
            if us > 0 {
                preflight.tls_handshake_us = us;
                preflight.uses_tls = true;
            }
        }
        if let Ok(t) = easy.connect_time() {
            preflight.connect_us = t.as_micros() as u64;
        }
        if let Ok(t) = easy.starttransfer_time() {
            preflight.ttfb_us = t.as_micros() as u64;
        }

        // Capture the HTTP version from the preflight response so the adaptive
        // engine can make protocol-aware decisions (e.g., HTTP/2 multiplexing
        // supports more concurrent streams than HTTP/1.1).
        {
            if let Some(ver) = easy.get_ref().http_version() {
                preflight.protocol = match ver.as_str() {
                    "1.0" => "HTTP/1.0".to_owned(),
                    "1.1" => "HTTP/1.1".to_owned(),
                    "2" => "h2".to_owned(),
                    _ => format!("HTTP/{ver}"),
                };
            }
        }

        let is_html = easy
            .content_type()
            .ok()
            .flatten()
            .is_some_and(|ct| ct.to_ascii_lowercase().contains("text/html"));

        if is_html {
            if let Some(refresh) =
                crate::daemon::utils::parse_meta_refresh_url(&easy.get_ref().text())
            {
                let next = crate::daemon::utils::refreshed_url(refresh, &effective);
                if next.starts_with("http") && next != current && next != effective {
                    log::info!("resolve: meta-refresh {current} -> {next}");
                    current = next;
                    continue;
                }
            }
            return (effective, false, preflight);
        }

        return (effective, code == 206, preflight);
    }

    (current, false, preflight)
}

#[derive(Clone, Debug, Default)]
struct PreflightData {
    protocol: String,
    initial_rtt_us: u64,
    tls_handshake_us: u64,
    connect_us: u64,
    ttfb_us: u64,
    uses_tls: bool,
    supports_range: bool,
}

fn update_curl_task_progress(
    state: &SharedState,
    id: &str,
    total_size: u64,
    ranges: &[(ByteRange, Arc<AtomicU64>, u64)],
    last_total: &mut u64,
    last_tick: &mut Instant,
) {
    let downloaded: u64 = ranges
        .iter()
        .map(|(range, progress, initial)| {
            let on_disk = *initial + progress.load(Ordering::Relaxed);
            on_disk.min(part_size(range))
        })
        .sum();
    let now = Instant::now();
    let elapsed = now.duration_since(*last_tick).as_secs_f64().max(0.001);
    let speed = downloaded.saturating_sub(*last_total) as f64 / elapsed;
    *last_total = downloaded;
    *last_tick = now;

    let speed_u64 = speed.max(0.0) as u64;

    state.bandwidth_manager.report_speed(id, speed_u64);

    if let Ok(trackers) = state.engine_trackers.read() {
        if let Some(tracker) = trackers.get(id) {
            tracker.adaptive.report_speed(speed_u64);
        }
    }

    // Blocking lock: a try_lock spin would delay cancellation checks and
    // stall progress ticks under contention.
    let mut jobs = match state.curl_jobs.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    if let Some(job) = jobs.get_mut(id) {
        job.task.downloaded_bytes = downloaded;
        job.task.size_bytes = total_size;
        job.task.speed_bytes_per_sec = speed.max(0.0) as u64;
        job.task.elapsed_seconds = job.start_time.elapsed().as_secs();
        job.task.time_left_seconds = if speed > 0.0 && total_size > downloaded {
            ((total_size - downloaded) as f64 / speed).ceil() as u64
        } else {
            0
        };
        if job.segment_prev_bytes.len() != ranges.len() {
            job.segment_prev_bytes.resize(ranges.len(), 0);
        }
        let mut segment_speeds: Vec<u64> = Vec::with_capacity(ranges.len());
        for (i, (range, progress, initial)) in ranges.iter().enumerate() {
            let seg_total = part_size(range);
            let seg_downloaded = (*initial + progress.load(Ordering::Relaxed)).min(seg_total);
            let prev = job.segment_prev_bytes[i];
            let seg_speed = if seg_downloaded > prev {
                (seg_downloaded - prev) as f64 / elapsed
            } else {
                0.0
            };
            job.segment_prev_bytes[i] = seg_downloaded;
            segment_speeds.push(seg_speed.max(0.0) as u64);
        }
        job.task.segments = ranges
            .iter()
            .enumerate()
            .map(|(i, (range, progress, initial))| {
                let seg_total = part_size(range);
                let seg_downloaded = (*initial + progress.load(Ordering::Relaxed)).min(seg_total);
                Segment {
                    id: range.index as u32,
                    progress: if seg_total > 0 {
                        seg_downloaded as f64 / seg_total as f64
                    } else {
                        0.0
                    },
                    downloaded_bytes: seg_downloaded,
                    total_bytes: seg_total,
                    active: seg_downloaded < seg_total && job.task.status == "downloading",
                    speed: segment_speeds[i],
                }
            })
            .collect();
        let task = job.task.clone();
        drop(jobs);
        lock_or_err!(state.task_snapshot).insert(id.to_owned(), task);
        state.mark_dirty();
    }
}

/// HTTP(S) transfers always yield a non-zero response code after a
/// successful perform. Other protocols (FTP/SFTP/SCP/...) legitimately
/// report `response_code()==0` even on success, so the "no response" guards
/// must only apply to HTTP-family URLs.
fn is_http_family(url: &str) -> bool {
    let lower = url.get(..8).unwrap_or(url).to_ascii_lowercase();
    lower.starts_with("http://") || lower.starts_with("https://")
}

/// Result of a completed transfer pass. Carries everything the completion
/// path needs to decide whether the download may be marked complete.
#[derive(Clone, Debug)]
pub(super) struct TransferOutcome {
    pub(super) size: u64,
    pub(super) validator: Option<String>,
    /// True when the server actually sent a `Content-Encoding` (captured
    /// from response headers, not assumed from config), meaning libcurl
    /// decompressed the body and on-disk size may differ from the probed
    /// Content-Length.
    pub(super) content_encoded: bool,
}

impl TransferOutcome {
    const fn plain(size: u64, validator: Option<String>) -> Self {
        Self {
            size,
            validator,
            content_encoded: false,
        }
    }
}

/// Validate the final on-disk size against the probed size. Skipped only
/// when the server actually used Content-Encoding for this transfer.
fn validate_transfer_size(
    total_size: u64,
    content_encoded: bool,
    actual: u64,
) -> Result<(), String> {
    IntegrityValidator::new(IntegrityMetadata {
        expected_size: (total_size > 0).then_some(total_size),
        compressed_transfer: content_encoded,
    })
    .validate_size(actual)
}

fn run_single_libcurl(
    state: &SharedState,
    id: &str,
    plan: &DirectDownloadPlan,
    cancel: Arc<AtomicBool>,
    retry_after: Arc<AtomicU64>,
    streaming_digest_out: Arc<Mutex<Option<String>>>,
) -> Result<TransferOutcome, String> {
    log::info!(
        "Task {id}: run_single_libcurl starting — url={}, total_size={}, resumable={}, output={}",
        plan.url,
        plan.total_size,
        plan.resumable,
        plan.output_path.display()
    );
    FileWriter::ensure_parent(&plan.output_path)?;
    if plan.config.bool_("skipExisting") == Some(true) && plan.output_path.exists() {
        // Only honour skipExisting when the file on disk is plausibly the
        // completed object. An empty file, or one whose size disagrees with
        // a known remote size, must be (re)downloaded instead of being
        // silently accepted as "complete".
        let existing = FileWriter::current_size(&plan.output_path)?;
        let plausible = if plan.total_size > 0 {
            existing == plan.total_size
        } else {
            existing > 0
        };
        if plausible {
            return Ok(TransferOutcome::plain(existing, None));
        }
        log::info!(
            "skipExisting ignored for {} (on-disk {} bytes, expected {}): redownloading",
            plan.output_path.display(),
            existing,
            plan.total_size
        );
    }
    if plan.output_path.exists() {
        let existing = FileWriter::current_size(&plan.output_path)?;
        if plan.total_size > 0 && existing == plan.total_size {
            return Ok(TransferOutcome::plain(existing, None));
        }
        if plan.total_size > 0 && existing > plan.total_size {
            if plan.allow_overwrite {
                let _ = std::fs::remove_file(&plan.output_path);
            } else {
                return Err(format!(
                    "Destination is larger than expected and overwrite is disabled: {}",
                    plan.output_path.display()
                ));
            }
        } else if !plan.resumable && existing > 0 {
            if !plan.allow_overwrite {
                return Err(format!(
                    "Destination already exists: {}",
                    plan.output_path.display()
                ));
            }
            let _ = std::fs::remove_file(&plan.output_path);
        } else if !plan.allow_overwrite && plan.total_size == 0 && existing > 0 {
            return Err(format!(
                "Cannot safely resume existing destination without a known remote size: {}",
                plan.output_path.display()
            ));
        }
    }

    let resume_existing = if plan.resumable && plan.validator.is_some() {
        FileWriter::current_size(&plan.output_path)?
    } else {
        0
    };
    let on_disk_before = FileWriter::current_size(&plan.output_path)?;
    let capture = Arc::new(Mutex::new(ResponseCapture::default()));
    let downloaded_counter = Arc::new(AtomicU64::new(0));
    let progress = SegmentProgress {
        downloaded: downloaded_counter.clone(),
        abort: cancel.clone(),
        retry_after: retry_after.clone(),
        capture: capture.clone(),
        streaming_digest_out: streaming_digest_out.clone(),
    };
    let task_limit = state.bandwidth_manager.allowed_speed_for_task(id);
    let task_limit_bps = if task_limit > 0 {
        Some(task_limit * 1024)
    } else {
        None
    };
    let is_preallocated = resume_existing == 0 && plan.total_size > 0;
    let preallocate = if is_preallocated {
        Some(plan.total_size)
    } else {
        None
    };
    let easy = create_easy_for_range_ext(
        plan,
        &plan.output_path,
        progress,
        None,
        task_limit_bps,
        preallocate,
    )?;
    let mut guard = CurlMultiGuard::new();
    guard.configure_limits(global_config().connection_limits_for(1, &plan.url))?;
    let mut socket_runtime = if matches!(plan.config.event_loop_mode(), EventLoopMode::MultiSocket)
    {
        Some(guard.attach_socket_runtime()?)
    } else {
        None
    };
    let handle = guard.add2(easy)?;
    let handles = vec![handle];
    let mut last_total = on_disk_before;
    let mut last_tick = Instant::now();
    let mut last_progress_time = Instant::now();
    let downloaded_for_tick = downloaded_counter.clone();
    let cancel_for_tick = cancel.clone();
    let mut tick = || {
        let counter_bytes = downloaded_for_tick.load(Ordering::Relaxed);
        let effective_downloaded = if is_preallocated {
            on_disk_before + counter_bytes
        } else {
            let disk_bytes = FileWriter::current_size(&plan.output_path).unwrap_or(0);
            on_disk_before + counter_bytes.max(disk_bytes.saturating_sub(on_disk_before))
        };
        let now = Instant::now();
        let elapsed = now.duration_since(last_tick).as_secs_f64().max(0.001);
        let speed = effective_downloaded.saturating_sub(last_total) as f64 / elapsed;
        let prev_last_total = last_total;
        last_total = effective_downloaded;
        last_tick = now;

        if effective_downloaded > prev_last_total {
            last_progress_time = now;
        } else if now.duration_since(last_progress_time).as_secs() >= 60
            && effective_downloaded == prev_last_total
        {
            log::warn!("Task {id}: stall detected — no data received for 60s, aborting transfer");
            cancel_for_tick.store(true, Ordering::Release);
        }

        let speed_u64 = speed as u64;
        state.bandwidth_manager.report_speed(id, speed_u64);

        // Blocking lock: a try_lock spin would delay progress ticks and the
        // in-loop stall detector under contention.
        let mut jobs = match state.curl_jobs.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        {
            if let Some(job) = jobs.get_mut(id) {
                job.task.downloaded_bytes = effective_downloaded;
                job.task.size_bytes = plan.total_size;
                job.task.speed_bytes_per_sec = speed_u64;
                job.task.elapsed_seconds = job.start_time.elapsed().as_secs();
                job.task.time_left_seconds =
                    if speed > 0.0 && plan.total_size > effective_downloaded {
                        ((plan.total_size - effective_downloaded) as f64 / speed).ceil() as u64
                    } else {
                        0
                    };
                let task = job.task.clone();
                drop(jobs);
                lock_or_err!(state.task_snapshot).insert(id.to_owned(), task);
                state.mark_dirty();
            }
        }
    };
    log::info!(
        "Task {id}: starting curl multi drive loop (on_disk_before={on_disk_before}, preallocate={preallocate:?})"
    );
    if let Some(runtime) = socket_runtime.as_mut() {
        drive_multi_socket(
            guard.multi()?,
            runtime,
            &handles,
            &cancel,
            "transfer",
            &mut tick,
        )?;
    } else {
        drive_multi_wait_perform(guard.multi()?, &handles, &cancel, "transfer", &mut tick)?;
    }
    let response = handles[0]
        .response_code()
        .map_err(|e| format!("Could not read HTTP response code: {e}"))?;
    log::info!("Task {id}: curl transfer finished — HTTP response={response}");
    if response == 304 {
        // 304 Not Modified is only a valid completion when the local file
        // actually holds the (unchanged) object. If the partial file is
        // missing or empty, the conditional request was satisfied against
        // data we no longer have; retry once WITHOUT the validator so the
        // server returns the full body instead of another 304.
        let on_disk = FileWriter::current_size(&plan.output_path)?;
        if on_disk == 0 && plan.validator.is_some() {
            log::info!(
                "304 Not Modified but no local data for {}; retrying without conditional headers",
                plan.output_path.display()
            );
            let mut unconditional = plan.clone();
            unconditional.validator = None;
            unconditional.validator_is_etag = false;
            return run_single_libcurl(
                state,
                id,
                &unconditional,
                cancel,
                retry_after,
                streaming_digest_out,
            );
        }
        if on_disk == 0 {
            return Err(
                "Server replied 304 Not Modified but no local file exists to validate against"
                    .to_owned(),
            );
        }
        let (captured, encoded) = capture.lock().ok().map_or((None, false), |cap| {
            (cap.validator.clone(), cap.content_encoded)
        });
        return Ok(TransferOutcome {
            size: on_disk,
            validator: captured,
            content_encoded: encoded,
        });
    }
    if response == 412 {
        let existing = FileWriter::current_size(&plan.output_path)?;
        if existing > 0 {
            log::info!(
                "412 Precondition Failed: resource changed, discarding {} bytes of partial data for {}",
                existing,
                plan.output_path.display()
            );
            let _ = std::fs::remove_file(&plan.output_path);
        }
        return Err("resource-changed-412".to_owned());
    }
    if response == 416 {
        let existing = FileWriter::current_size(&plan.output_path)?;
        if existing > 0 {
            log::info!(
                "416 Range Not Satisfiable: discarding {} bytes of partial data for {}",
                existing,
                plan.output_path.display()
            );
            let _ = std::fs::remove_file(&plan.output_path);
        }
        return Err("range-not-satisfiable-416".to_owned());
    }
    if response == 200 && resume_existing > 0 {
        log::warn!(
            "Server returned 200 OK instead of 206 on resume ({} bytes), \
             truncating corrupted file {}",
            resume_existing,
            plan.output_path.display()
        );
        if let Ok(f) = std::fs::OpenOptions::new()
            .write(true)
            .open(&plan.output_path)
        {
            let _ = f.set_len(0);
        }
        return Err("resume-corrupted-200".to_owned());
    }
    if response >= 400 {
        return Err(format!("HTTP error {response}"));
    }
    // response == 0 means no HTTP response was received at all — the transfer
    // failed before reaching the server (DNS failure, connection refused, TLS
    // handshake error, etc.). Without this check, the download is silently
    // marked as "completed" with 0 bytes, which is exactly the bug where
    // "NOVA detects the file size but never downloads the file."
    // This guard applies only to HTTP-family URLs: FTP/SFTP/SCP transfers
    // legitimately report response_code()==0 on success.
    if response == 0 && is_http_family(&plan.url) {
        // Use the atomic counter (actual curl-written bytes) NOT file size,
        // because preallocated files inflate FileWriter::current_size() and
        // mask a zero-byte transfer as "complete".
        let curl_written = downloaded_counter.load(Ordering::Acquire);
        log::warn!(
            "Task {id}: HTTP response=0 — curl_written={curl_written}, on_disk={}, total_size={}",
            FileWriter::current_size(&plan.output_path).unwrap_or(0),
            plan.total_size
        );
        if curl_written == 0 {
            return Err(
                "Transfer failed: no HTTP response received (DNS, connection, or TLS error). \
                 The download engine could not reach the server."
                    .to_owned(),
            );
        }
        // Partial data was received but the connection dropped before a complete
        // response. Treat this as an error so retry logic can kick in.
        if plan.total_size > 0 && curl_written < plan.total_size {
            return Err(format!(
                "Transfer interrupted: received {} of {} bytes before connection lost (HTTP response code: 0)",
                curl_written, plan.total_size
            ));
        }
        // Unknown-size HTTP transfer whose connection dropped mid-body: with
        // no Content-Length there is no way to prove completeness. Fail
        // loudly so the user can retry instead of trusting a truncated file.
        if plan.total_size == 0 && curl_written > 0 {
            return Err(format!(
                "Transfer ended without an HTTP response after {curl_written} bytes; the file may be incomplete"
            ));
        }
    }
    let (captured, encoded) = capture.lock().ok().map_or((None, false), |cap| {
        (cap.validator.clone(), cap.content_encoded)
    });
    Ok(TransferOutcome {
        size: FileWriter::current_size(&plan.output_path)?,
        validator: captured,
        content_encoded: encoded,
    })
}

fn run_segmented_libcurl(
    state: &SharedState,
    id: &str,
    plan: &DirectDownloadPlan,
    cancel: Arc<AtomicBool>,
    retry_after: Arc<AtomicU64>,
    streaming_digest_out: Arc<Mutex<Option<String>>>,
    preflight: &PreflightData,
) -> Result<TransferOutcome, String> {
    FileWriter::ensure_parent(&plan.output_path)?;
    if !plan.allow_overwrite && plan.output_path.exists() {
        let existing = FileWriter::current_size(&plan.output_path)?;
        if existing == plan.total_size && plan.total_size > 0 {
            return Ok(TransferOutcome::plain(existing, None));
        }
        return Err(format!(
            "Destination already exists: {}",
            plan.output_path.display()
        ));
    }
    if !plan.resumable {
        let _ = std::fs::remove_file(&plan.output_path);
        remove_stale_parts_for(&plan.output_path);
    }
    if plan.output_path.exists()
        && FileWriter::current_size(&plan.output_path)? == plan.total_size
        && plan.total_size > 0
    {
        return Ok(TransferOutcome::plain(plan.total_size, None));
    }

    let task_limit = state.bandwidth_manager.allowed_speed_for_task(id);
    let cfg = global_config();
    let effective_connections = CurlTransferConfig::bandwidth_aware_connections(
        plan.connections,
        cfg.max_connections_per_download,
        task_limit,
    );

    let ranges = split_ranges(plan.total_size, effective_connections, &plan.output_path);

    let segment_scheduler = crate::daemon::engine::dynamic_segments::DynamicSegmentScheduler::new(
        plan.total_size,
        effective_connections,
        cfg.max_connections_per_download,
    );

    let telemetry_bus = Arc::new(crate::daemon::engine::adaptive::TelemetryBus::new());
    let adaptive_engine = {
        let host = reqwest::Url::parse(&plan.url)
            .ok()
            .and_then(|u| u.host_str().map(str::to_owned))
            .unwrap_or_else(|| "unknown".into());
        let protocol = match preflight.protocol.as_str() {
            "h2" | "h2c" => {
                crate::daemon::engine::adaptive::server_profiler::ProtocolVersion::Http2
            }
            "h3" => crate::daemon::engine::adaptive::server_profiler::ProtocolVersion::Http3,
            "HTTP/1.1" => crate::daemon::engine::adaptive::server_profiler::ProtocolVersion::Http11,
            "HTTP/1.0" => crate::daemon::engine::adaptive::server_profiler::ProtocolVersion::Http11,
            _ => crate::daemon::engine::adaptive::server_profiler::ProtocolVersion::Unknown,
        };
        let rie_connections = plan.config.rie_connections.unwrap_or(effective_connections);
        let mut engine = crate::daemon::engine::adaptive::AdaptiveEngine::new(
            host,
            plan.total_size,
            rie_connections,
            protocol,
            cfg.min_segment_bytes,
        );
        if preflight.initial_rtt_us > 0 || preflight.ttfb_us > 0 {
            engine.seed_profile(
                protocol,
                preflight.supports_range,
                plan.resumable,
                None,
                if preflight.uses_tls {
                    Some("TLS".into())
                } else {
                    None
                },
                None,
                preflight.initial_rtt_us,
                preflight.tls_handshake_us,
                preflight.ttfb_us,
            );
        }
        if let Some(ref strat) = plan.config.rie_strategy {
            log::info!(
                "Task {id}: RIE strategy={strat} rie_conns={rie_connections} effective_conns={effective_connections}"
            );
        }
        engine
    };

    {
        let mut trackers = match state.engine_trackers.write() {
            Ok(g) => g,
            Err(e) => {
                log::error!("engine_trackers lock poisoned: {e}");
                return Err("engine_trackers lock poisoned".into());
            }
        };
        trackers.insert(
            id.to_owned(),
            crate::daemon::state::TaskEngineTracker {
                adaptive:
                    crate::daemon::engine::adaptive_connections::AdaptiveConnectionManager::new(
                        plan.connections,
                        Default::default(),
                    ),
                segments: Some(segment_scheduler.clone()),
                retry_state: crate::daemon::engine::retry::RetryState::new(),
                adaptive_engine: Mutex::new(Some(adaptive_engine)),
            },
        );
    }

    let mut active: Vec<(ByteRange, Arc<AtomicU64>, u64)> = Vec::new();
    let mut guard = CurlMultiGuard::new();
    guard.configure_limits(
        global_config().connection_limits_for(effective_connections, &plan.url),
    )?;
    guard
        .multi()?
        .pipelining(false, true)
        .map_err(|e| format!("Could not enable libcurl multiplexing: {e}"))?;
    let mut socket_runtime = if matches!(plan.config.event_loop_mode(), EventLoopMode::MultiSocket)
    {
        Some(guard.attach_socket_runtime()?)
    } else {
        None
    };

    let mut handles = Vec::new();
    let mut seg_captures: Vec<Arc<Mutex<ResponseCapture>>> = Vec::new();
    let per_segment_limit_bps = if task_limit > 0 {
        Some((task_limit * 1024) / u64::from(effective_connections.max(1)))
    } else {
        None
    };
    for range in ranges.iter().cloned() {
        let expected = part_size(&range);
        let actual = FileWriter::current_size(&range.path)?;
        let existing = if actual > expected {
            let _ = std::fs::remove_file(&range.path);
            0
        } else {
            actual
        };
        if existing >= expected {
            active.push((range, Arc::new(AtomicU64::new(0)), expected));
            continue;
        }
        let start = range.start + existing;
        let progress = Arc::new(AtomicU64::new(0));
        let seg_capture = Arc::new(Mutex::new(ResponseCapture::default()));
        seg_captures.push(seg_capture.clone());
        let preallocate = if existing == 0 { Some(expected) } else { None };
        let easy = create_easy_for_range_ext(
            plan,
            &range.path,
            SegmentProgress {
                downloaded: progress.clone(),
                abort: cancel.clone(),
                retry_after: retry_after.clone(),
                capture: seg_capture,
                streaming_digest_out: streaming_digest_out.clone(),
            },
            Some((start, range.end)),
            per_segment_limit_bps,
            preallocate,
        )?;
        let handle = guard
            .add2(easy)
            .map_err(|e| format!("Could not add segment {}: {e}", range.index))?;
        handles.push(handle);
        active.push((range, progress, existing));
    }

    if handles.is_empty() {
        return merge_parts(&plan.output_path, &ranges).map(|s| TransferOutcome::plain(s, None));
    }

    let mut last_total: u64 = active
        .iter()
        .map(|(r, p, initial)| (*initial + p.load(Ordering::Relaxed)).min(part_size(r)))
        .sum();
    let mut last_tick = Instant::now();
    let mut prev_seg_bytes: Vec<u64> = vec![0; active.len()];
    let mut tick = || {
        let now = Instant::now();
        let elapsed = now.duration_since(last_tick).as_secs_f64().max(0.001);
        let mut seg_downloads = Vec::with_capacity(active.len());
        let mut seg_speeds = Vec::with_capacity(active.len());
        for (i, (_range, progress, _initial)) in active.iter().enumerate() {
            let seg_downloaded = progress.load(Ordering::Relaxed);
            let seg_speed = if seg_downloaded > prev_seg_bytes[i] {
                ((seg_downloaded - prev_seg_bytes[i]) as f64 / elapsed) as u64
            } else {
                0
            };
            prev_seg_bytes[i] = seg_downloaded;
            segment_scheduler.update_segment(i as u32, seg_downloaded, seg_speed, true);
            telemetry_bus.report_bytes(i, seg_downloaded);
            telemetry_bus.report_speed(i, seg_speed);
            telemetry_bus.set_alive(i, true);
            seg_downloads.push(seg_downloaded);
            seg_speeds.push(seg_speed);
        }
        if let Ok(trackers) = state.engine_trackers.read() {
            if let Some(tracker) = trackers.get(id) {
                if let Ok(mut engine_guard) = tracker.adaptive_engine.lock() {
                    if let Some(ref mut engine) = engine_guard.as_mut() {
                        for (i, (&downloaded, &speed)) in
                            seg_downloads.iter().zip(seg_speeds.iter()).enumerate()
                        {
                            engine
                                .segment_ctrl
                                .update_progress(i as u32, downloaded, speed);
                        }
                        // Adaptive engine evaluate() and decision application are
                        // disabled — the decisions (target_connections, segment
                        // split/merge/etc.) have no code path that reconfigures
                        // the active curl multi handle's easy handles. Progress
                        // data is still fed to segment_ctrl for future use.
                    }
                }
            }
        }
        update_curl_task_progress(
            state,
            id,
            plan.total_size,
            &active,
            &mut last_total,
            &mut last_tick,
        );
    };
    if let Some(runtime) = socket_runtime.as_mut() {
        drive_multi_socket(
            guard.multi()?,
            runtime,
            &handles,
            &cancel,
            "segment",
            &mut tick,
        )?;
    } else {
        drive_multi_wait_perform(guard.multi()?, &handles, &cancel, "segment", &mut tick)?;
    }
    for (idx, handle) in handles.iter().enumerate() {
        let code = handle
            .response_code()
            .map_err(|e| format!("Segment {idx}: could not read HTTP response code: {e}"))?;
        if code == 304 {
            continue;
        }
        if code == 412 {
            for r in &ranges {
                let _ = std::fs::remove_file(&r.path);
            }
            return Err("resource-changed-412".to_owned());
        }
        if code == 416 {
            for r in &ranges {
                let _ = std::fs::remove_file(&r.path);
            }
            return Err("range-not-satisfiable-416".to_owned());
        }
        if is_http_family(&plan.url) && code != 206 && code != 200 {
            return Err(format!(
                "Segment {idx} finished with unexpected HTTP status {code}"
            ));
        }
        if code == 200 && ranges.len() > 1 && is_http_family(&plan.url) {
            for r in &ranges {
                let _ = std::fs::remove_file(&r.path);
            }
            return Err("Server did not honor byte-range requests; retry with one connection or probe the URL again.".to_owned());
        }
    }
    update_curl_task_progress(
        state,
        id,
        plan.total_size,
        &active,
        &mut last_total,
        &mut last_tick,
    );
    let (captured_validator, encoded) = seg_captures
        .first()
        .and_then(|cap| cap.lock().ok())
        .map_or((None, false), |cap| {
            (cap.validator.clone(), cap.content_encoded)
        });
    merge_parts(&plan.output_path, &ranges).map(|s| TransferOutcome {
        size: s,
        validator: captured_validator,
        content_encoded: encoded,
    })
}

fn run_libcurl_download(
    state: &SharedState,
    id: &str,
    mut plan: DirectDownloadPlan,
    cancel: Arc<AtomicBool>,
) -> Result<u64, String> {
    // Safety cap: no single download should retry for more than 24 hours,
    // regardless of how the retry policy is configured or dynamically adapted.
    const MAX_RETRY_WALL_TIME: std::time::Duration = std::time::Duration::from_secs(86400);
    log::info!(
        "Task {id}: run_libcurl_download entered — url={}, total_size={}, segmented={}, output={}",
        plan.url,
        plan.total_size,
        plan.segmented,
        plan.output_path.display()
    );
    let retry_policy = plan.config.retry_policy();
    let start_time = std::time::Instant::now();
    let mut last_error = String::new();
    let retry_after = Arc::new(AtomicU64::new(0));
    let streaming_digest_out = Arc::new(Mutex::new(None::<String>));
    if plan.segmented && crate::daemon::direct::learned_host_ceiling(&plan.url) == Some(1) {
        plan.segmented = false;
    }
    #[allow(unused_assignments)]
    let mut supports_range = true;
    #[allow(unused_assignments)]
    let mut preflight = PreflightData::default();
    {
        if let Ok(mut jobs) = state.curl_jobs.lock() {
            if let Some(job) = jobs.get_mut(id) {
                job.task.engine_status = Some("resolving-url".to_owned());
            }
        }
        state.mark_dirty();

        let resolved = resolve_effective_target(&plan);
        let effective_url = resolved.0;
        supports_range = resolved.1;
        preflight = resolved.2;

        if let Ok(mut jobs) = state.curl_jobs.lock() {
            if let Some(job) = jobs.get_mut(id) {
                job.task.engine_status = Some("running-libcurl-multi".to_owned());
            }
        }
        state.mark_dirty();

        if effective_url != plan.url {
            log::info!(
                "Task {}: resolved effective URL {} -> {}",
                id,
                plan.url,
                effective_url
            );
            plan.url = effective_url;
        }
        if plan.segmented && !supports_range {
            log::info!("Task {id}: server does not honour byte ranges; using a single connection");
            plan.segmented = false;
        }
    }
    // Auto-resolve filename conflicts before downloading. Professional download
    // managers (IDM, browser built-in) never block the user with "file exists"
    // errors; they append " (1)", " (2)" etc. to the filename. This also fixes
    // the reported bug where NOVA "detects size but never downloads" because a
    // stale partial file from a previous failed attempt blocked the new one.
    if !plan.allow_overwrite && plan.output_path.exists() {
        let existing_size = FileWriter::current_size(&plan.output_path)?;
        let is_complete = plan.total_size > 0 && existing_size == plan.total_size;
        if !is_complete {
            if let Some(renamed) = auto_rename_path(&plan.output_path) {
                log::info!(
                    "Task {}: auto-renamed {} -> {} (conflict resolution)",
                    id,
                    plan.output_path.display(),
                    renamed.display()
                );
                plan.output_path = renamed;
                // Update the task snapshot so the UI shows the new filename.
                // Lock order: curl_jobs → task_snapshot (to match the rest of the codebase)
                if let Ok(mut jobs) = state.curl_jobs.lock() {
                    if let Some(job) = jobs.get_mut(id) {
                        job.task.save_path = plan.output_path.to_string_lossy().to_string();
                    }
                }
                if let Ok(mut tasks) = state.task_snapshot.lock() {
                    if let Some(task) = tasks.get_mut(id) {
                        task.save_path = plan.output_path.to_string_lossy().to_string();
                    }
                }
                state.mark_dirty();
            }
        }
    }

    for attempt in 0..retry_policy.attempts {
        if cancel.load(Ordering::Acquire) {
            return Err("cancelled".to_owned());
        }
        if start_time.elapsed() >= MAX_RETRY_WALL_TIME {
            log::warn!(
                "Task {id}: retry wall-time limit ({MAX_RETRY_WALL_TIME:?}) exceeded, giving up"
            );
            break;
        }
        if let Some(max_time) = retry_policy.max_total_time {
            if start_time.elapsed() >= max_time {
                log::info!("Task {id}: retry max_total_time ({max_time:?}) exceeded, giving up");
                break;
            }
        }
        let result = if plan.segmented {
            run_segmented_libcurl(
                state,
                id,
                &plan,
                cancel.clone(),
                retry_after.clone(),
                streaming_digest_out.clone(),
                &preflight,
            )
        } else {
            run_single_libcurl(
                state,
                id,
                &plan,
                cancel.clone(),
                retry_after.clone(),
                streaming_digest_out.clone(),
            )
        };
        match result {
            Ok(outcome) => {
                let size = outcome.size;
                let captured_validator = outcome.validator.clone();
                if let Ok(mut trackers) = state.engine_trackers.write() {
                    if let Some(tracker) = trackers.get_mut(id) {
                        tracker.retry_state.reset();
                    }
                }
                if let Ok(managers) = state.mirror_managers.lock() {
                    if let Some(mgr) = managers.get(id) {
                        mgr.report_success(&plan.url);
                    }
                }
                // Size validation is skipped only when the server ACTUALLY
                // used Content-Encoding for this transfer (captured from the
                // response headers) — never merely assumed from config.
                validate_transfer_size(plan.total_size, outcome.content_encoded, size)?;
                if let Some(ref expected_raw) = plan.digest_sha256 {
                    let actual_hex = streaming_digest_out
                        .lock()
                        .ok()
                        .and_then(|s| s.clone())
                        .or_else(|| {
                            use crate::daemon::engine::checksum::{
                                compute_checksum, ChecksumAlgorithm,
                            };
                            compute_checksum(&plan.output_path, &ChecksumAlgorithm::Sha256).ok()
                        });
                    if let Some(actual_hex) = actual_hex {
                        let expected_hex = if let Some(bytes) =
                            crate::daemon::utils::base64_decode(expected_raw.trim_matches(':'))
                        {
                            bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
                        } else {
                            expected_raw.clone()
                        };
                        if actual_hex != expected_hex.to_lowercase() {
                            log::warn!(
                                "Task {id}: Content-Digest mismatch (expected {expected_hex}, got {actual_hex})"
                            );
                            return Err(format!(
                                "Content-Digest verification failed: expected sha-256={expected_hex}, got {actual_hex}"
                            ));
                        }
                        log::info!(
                            "Task {}: Content-Digest verified (sha-256={})",
                            id,
                            &actual_hex[..16]
                        );
                    }
                }
                if cancel.load(Ordering::Acquire) {
                    return Err("cancelled".to_owned());
                }
                if let Some(etag_file) = plan.config.str_("etagSave") {
                    if let Some(ref captured) = captured_validator {
                        if let Err(e) = std::fs::write(etag_file, captured) {
                            log::warn!(
                                "Task {id}: failed to persist ETag to {etag_file}: {e} — next resume will re-download"
                            );
                        }
                    }
                }
                return Ok(size);
            }
            Err(error) if error == "cancelled" || cancel.load(Ordering::Acquire) => {
                return Err("cancelled".to_owned())
            }
            Err(error) => {
                // ── Self-healer + policy engine ──────────────────────────
                // The self-healer analyzes the failure pattern and recommends
                // a recovery action. The policy engine records the decision
                // for analytics. We then use the recovery decision to
                // influence the actual retry behavior below.
                let mut healer_abort = false;
                let mut healer_pause: Option<Duration> = None;
                {
                    let failure_count = state
                        .engine_trackers
                        .read()
                        .ok()
                        .and_then(|t| t.get(id).map(|tr| tr.retry_state.attempt))
                        .unwrap_or(0);
                    let ctx =
                        build_decision_context(state, id, &plan, failure_count, 0, supports_range);
                    if let Ok(mut healer) = state.self_healer.lock() {
                        let recovery = healer.on_failure(&ctx.host, &error, &ctx);
                        log::info!("Task {id}: self-healer recovery decision: {recovery:?}");
                        // Wire the recovery decision into the retry loop.
                        if let crate::daemon::engine::policy_engine::PolicyDecision::Recovery {
                            ref action,
                            ..
                        } = recovery
                        {
                            use crate::daemon::engine::policy_engine::RecoveryAction;
                            match action {
                                RecoveryAction::Abort => {
                                    log::warn!("Task {id}: self-healer recommends abort — {error}");
                                    healer_abort = true;
                                }
                                RecoveryAction::ReduceConnections => {
                                    let new_conns = (plan.connections / 2).max(1);
                                    log::info!(
                                        "Task {}: self-healer reducing connections {} -> {}",
                                        id,
                                        plan.connections,
                                        new_conns
                                    );
                                    plan.connections = new_conns;
                                }
                                RecoveryAction::PauseAndRetry(dur) => {
                                    log::info!(
                                        "Task {id}: self-healer pausing {dur:?} before retry"
                                    );
                                    healer_pause = Some(*dur);
                                }
                                RecoveryAction::RestartDownload => {
                                    log::info!("Task {id}: self-healer recommends full restart");
                                }
                                _ => {}
                            }
                        }
                    }
                    if let Ok(mut pe) = state.policy_engine.lock() {
                        let retry_decision = pe.decide_retry(&ctx, &error);
                        pe.record_decision(&retry_decision, &error);
                    }
                }
                if healer_abort {
                    return Err(error);
                }
                if let Ok(mut trackers) = state.engine_trackers.write() {
                    if let Some(tracker) = trackers.get_mut(id) {
                        tracker.retry_state.record_failure(error.clone());
                    }
                }
                if let Ok(managers) = state.mirror_managers.lock() {
                    if let Some(mgr) = managers.get(id) {
                        if !plan.link_mirrors.is_empty() {
                            for (i, mirror_url) in plan.link_mirrors.iter().enumerate() {
                                if mirror_url != &plan.url {
                                    let priority =
                                        plan.mirror_priorities.get(i).copied().unwrap_or(1);
                                    use crate::daemon::engine::mirror::MirrorSource;
                                    mgr.add_mirror(MirrorSource {
                                        url: mirror_url.clone(),
                                        priority,
                                        region: None,
                                        bandwidth_estimate: None,
                                        last_checked: None,
                                        healthy: true,
                                    });
                                }
                            }
                        }
                        if let Some(new_url) = mgr.report_failure(&plan.url, &error) {
                            log::info!(
                                "Mirror failover for task {}: {} -> {}",
                                id,
                                plan.url,
                                new_url
                            );
                            plan.url = new_url;
                        }
                    }
                }
                if plan.segmented {
                    log::info!(
                        "Segmented attempt failed for task {id}; trying single-connection fallback"
                    );
                    plan.segmented = false;
                    if cancel.load(Ordering::Acquire) {
                        return Err("cancelled".to_owned());
                    }
                    match run_single_libcurl(
                        state,
                        id,
                        &plan,
                        cancel.clone(),
                        retry_after.clone(),
                        streaming_digest_out.clone(),
                    ) {
                        Ok(fb) => {
                            crate::daemon::direct::record_host_ceiling(&plan.url, 1);
                            validate_transfer_size(plan.total_size, fb.content_encoded, fb.size)?;
                            return Ok(fb.size);
                        }
                        Err(fb_error)
                            if fb_error == "cancelled" || cancel.load(Ordering::Acquire) =>
                        {
                            return Err("cancelled".to_owned());
                        }
                        Err(fb_error) => {
                            log::warn!(
                                "Single-connection fallback also failed for task {id}: {fb_error}"
                            );
                        }
                    }
                }
                if RetryPolicy::is_permanent_error(&error)
                    || !retry_policy.should_retry_error(&error)
                {
                    return Err(error);
                }
                last_error = error;
                if attempt + 1 < retry_policy.attempts {
                    let hinted = retry_after.swap(0, Ordering::AcqRel);
                    // Use the self-healer's recommended pause if available,
                    // otherwise fall back to Retry-After header or exponential backoff.
                    let backoff_delay = if let Some(pause) = healer_pause {
                        pause
                    } else if hinted > 0 {
                        Duration::from_secs(hinted)
                    } else {
                        retry_policy.delay_for_attempt(attempt as u32 + 1)
                    };
                    let actual_delay = if let Some(max_time) = retry_policy.max_total_time {
                        let remaining = max_time.saturating_sub(start_time.elapsed());
                        backoff_delay.min(remaining)
                    } else {
                        backoff_delay
                    };
                    // Sleep in 500ms chunks to check the cancel token
                    // periodically, preventing delayed cancellation.
                    let mut elapsed = Duration::ZERO;
                    while elapsed < actual_delay {
                        if cancel.load(Ordering::Acquire) {
                            return Err("cancelled".to_owned());
                        }
                        let chunk = Duration::from_millis(500)
                            .min(actual_delay.checked_sub(elapsed).unwrap_or(Duration::ZERO));
                        std::thread::sleep(chunk);
                        elapsed += chunk;
                    }
                }
            }
        }
    }
    Err(last_error)
}

pub fn mark_curl_task_finished(state: &SharedState, id: &str, final_size: u64, generation: u64) {
    log::info!("Task {id}: download completed (final_size={final_size}, generation={generation})");
    state.priority_queue.stop_download(id);
    // download_stats scoped to this block and released before curl_jobs
    // is acquired below, preventing AB-BA deadlock with persist's
    // build_snapshot (which acquires curl_jobs → download_stats).
    {
        if let Ok(mut stats) = state.download_stats.lock() {
            stats.total_completed += 1;
            stats.total_downloaded_bytes += final_size;
        }
    }
    let mut jobs = lock_or_err!(state.curl_jobs);
    if let Some(job) = jobs.get_mut(id) {
        if job.run_generation.load(Ordering::Acquire) != generation {
            return;
        }
        job.task.status = "completed".to_owned();
        job.task.downloaded_bytes = final_size;
        if job.task.size_bytes == 0 {
            job.task.size_bytes = final_size;
        }
        job.task.speed_bytes_per_sec = 0;
        job.task.time_left_seconds = 0;
        job.task.engine_status = Some("completed".to_owned());
        job.task.error_message = None;
        job.task.segments =
            build_segments(job.task.connections, job.task.size_bytes, final_size, 0);
        let task = job.task.clone();
        drop(jobs);
        lock_or_err!(state.task_snapshot).insert(id.to_owned(), task);
        state.mark_dirty();
    }
}

pub fn mark_curl_task_failed(
    state: &SharedState,
    id: &str,
    message: String,
    cancelled: bool,
    generation: u64,
) {
    if cancelled {
        log::info!("Task {id}: download cancelled (generation={generation})");
    } else {
        log::error!("Task {id}: download failed: {message} (generation={generation})");
    }
    // Always decrement active_downloads — both cancel and error release a slot.
    state.priority_queue.stop_download(id);
    // download_stats scoped here; guard released before curl_jobs below
    // (see build_snapshot in persist.rs for lock-ordering rationale).
    if !cancelled {
        {
            if let Ok(mut stats) = state.download_stats.lock() {
                stats.total_failed += 1;
            }
        }
    }
    let mut jobs = lock_or_err!(state.curl_jobs);
    if let Some(job) = jobs.get_mut(id) {
        if job.run_generation.load(Ordering::Acquire) != generation {
            return;
        }
        job.task.status = if cancelled { "paused" } else { "error" }.to_owned();
        job.task.speed_bytes_per_sec = 0;
        job.task.time_left_seconds = 0;
        job.task.engine_status = Some(if cancelled { "paused" } else { "failed" }.to_owned());
        job.task.error_message = if cancelled { None } else { Some(message) };
        let task = job.task.clone();
        let remove_on_error = job
            .direct_options
            .get("removeOnError")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false);
        let path = std::path::PathBuf::from(&job.task.save_path);
        drop(jobs);
        if !cancelled && remove_on_error {
            let _ = std::fs::remove_file(&path);
            remove_stale_parts_for(&path);
        }
        lock_or_err!(state.task_snapshot).insert(id.to_owned(), task);
        state.mark_dirty();
    }
}

pub fn start_curl_process(state: &SharedState, id: &str) {
    let record = {
        let mut jobs = lock_or_err!(state.curl_jobs);
        let Some(job) = jobs.get_mut(id) else {
            return;
        };
        if job.task.status == "completed" {
            return;
        }
        let worker_was_started = job.run_generation.load(Ordering::Acquire) > 0;
        if worker_was_started
            && matches!(
                job.task.status.as_str(),
                "downloading" | "pausing" | "stopping"
            )
        {
            return;
        }
        job.cancel_token = Arc::new(AtomicBool::new(false));
        let generation = job
            .run_generation
            .fetch_add(1, Ordering::Release)
            .saturating_add(1);
        job.task.status = "downloading".to_owned();
        job.task.engine_status = Some("running-libcurl-multi".to_owned());
        job.task.error_message = None;
        job.start_time = Instant::now();
        let plan = plan_from_job(job);
        let token = job.cancel_token.clone();
        log::info!(
            "Task {id}: plan_from_job — url={}, total_size={}, resumable={}, output_path={}, connections={}",
            plan.url, plan.total_size, plan.resumable, plan.output_path.display(), plan.connections
        );
        (plan, token, generation)
    };
    state.mark_dirty();
    state.priority_queue.start_download();

    let watchdog_cancel = record.1.clone();
    let watchdog_generation = record.2;
    let watchdog_id = id.to_owned();
    let watchdog_state = state.clone();
    let watchdog_expected = record.0.total_size;

    let state2 = state.clone();
    let id2 = id.to_owned();
    std::thread::spawn(move || {
        let (plan, cancel, generation) = record;
        log::info!("Starting libcurl multi transfer for task {id2} generation {generation}");
        let remove_on_error = plan.remove_on_error;
        let output_path = plan.output_path.clone();
        let expected_size = plan.total_size;
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            run_libcurl_download(&state2, &id2, plan, cancel.clone())
        }));
        match result {
            Ok(Ok(0)) => {
                log::error!(
                    "Task {id2}: download produced 0-byte file (expected {expected_size}); refusing to mark as complete"
                );
                if remove_on_error {
                    let _ = std::fs::remove_file(&output_path);
                    remove_stale_parts_for(&output_path);
                }
                mark_curl_task_failed(
                    &state2,
                    &id2,
                    if expected_size > 0 {
                        format!(
                            "Transfer produced an empty file but {expected_size} bytes were expected; refusing to mark the download as complete"
                        )
                    } else {
                        "Download produced an empty file (0 bytes). The server may have rejected the request or TLS may have failed.".to_owned()
                    },
                    false,
                    generation,
                );
            }
            Ok(Ok(final_size)) => mark_curl_task_finished(&state2, &id2, final_size, generation),
            Ok(Err(error)) => {
                let cancelled = cancel.load(Ordering::Relaxed) || error == "cancelled";
                if !cancelled && remove_on_error {
                    let _ = std::fs::remove_file(&output_path);
                    remove_stale_parts_for(&output_path);
                }
                if cancelled {
                    let watchdog_set_error = state2.curl_jobs.lock().ok().is_some_and(|j| {
                        j.get(&id2)
                            .is_some_and(|job| job.task.error_message.is_some())
                    });
                    if watchdog_set_error {
                        log::info!(
                            "Task {id2}: watchdog already set error; preserving instead of marking cancelled"
                        );
                        state2.priority_queue.stop_download(&id2);
                        return;
                    }
                }
                mark_curl_task_failed(&state2, &id2, error, cancelled, generation);
            }
            Err(panic_info) => {
                let msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                    format!("Worker thread panicked: {s}")
                } else if let Some(s) = panic_info.downcast_ref::<String>() {
                    format!("Worker thread panicked: {s}")
                } else {
                    "Worker thread panicked with unknown payload".to_owned()
                };
                log::error!("{msg} (task: {id2})");
                mark_curl_task_failed(&state2, &id2, msg, false, generation);
            }
        }
    });

    // Watchdog thread: monitors the transfer independently of the curl
    // multi loop. If the multi socket interface blocks inside multi.action()
    // (which prevents tick() and the in-loop stall detector from firing),
    // this watchdog detects the stall from OUTSIDE and force-sets the cancel
    // token so the curl thread exits as soon as it checks it.
    // Small (< 1 MiB) downloads finish in seconds and are fully covered by the
    // in-loop stall detector, so the extra watchdog thread is skipped for them.
    if watchdog_expected >= 1_048_576 {
        let hard_deadline_secs = if watchdog_expected > 0 {
            let estimated = (watchdog_expected / 10_000) + 120;
            estimated.clamp(300, 10800)
        } else {
            7200
        };
        let watchdog_handle = std::thread::spawn(move || {
            log::info!(
                "Watchdog started for task {watchdog_id} (hard deadline: {hard_deadline_secs}s)"
            );
            let start = Instant::now();
            let mut last_downloaded: u64 = 0;
            let mut last_progress_time = Instant::now();
            let stall_timeout = Duration::from_secs(60);

            loop {
                std::thread::sleep(Duration::from_secs(3));

                if watchdog_state.shutdown_requested.load(Ordering::Acquire) {
                    log::info!("Watchdog for {watchdog_id}: daemon shutting down, exiting");
                    return;
                }

                if watchdog_cancel.load(Ordering::Acquire) {
                    log::info!("Watchdog for {watchdog_id}: cancel token already set, exiting");
                    return;
                }

                let (status, downloaded, speed) = {
                    let jobs = match watchdog_state.curl_jobs.lock() {
                        Ok(j) => j,
                        Err(_) => {
                            log::error!("Watchdog for {watchdog_id}: curl_jobs lock poisoned, force-cancelling");
                            watchdog_cancel.store(true, Ordering::Release);
                            return;
                        }
                    };
                    if let Some(job) = jobs.get(&watchdog_id) {
                        (
                            job.task.status.clone(),
                            job.task.downloaded_bytes,
                            job.task.speed_bytes_per_sec,
                        )
                    } else {
                        log::info!(
                            "Watchdog for {watchdog_id}: job removed from curl_jobs, exiting"
                        );
                        return;
                    }
                };

                if status != "downloading" {
                    log::info!("Watchdog for {watchdog_id}: status is '{status}', exiting");
                    return;
                }

                if downloaded > last_downloaded {
                    last_downloaded = downloaded;
                    last_progress_time = Instant::now();
                }

                let elapsed = start.elapsed().as_secs();

                // Stall check: no bytes received for stall_timeout seconds
                if last_progress_time.elapsed() >= stall_timeout {
                    log::warn!(
                        "Watchdog: task {watchdog_id} stalled for {}s with 0 bytes/s — force-cancelling transfer (downloaded={downloaded})",
                        stall_timeout.as_secs()
                    );
                    watchdog_cancel.store(true, Ordering::Release);
                    force_error_status(
                        &watchdog_state,
                        &watchdog_id,
                        watchdog_generation,
                        format!(
                            "Download stalled: no data received for {} seconds. The connection may have hung or the server stopped responding.",
                            stall_timeout.as_secs()
                        ),
                    );
                    return;
                }

                // Hard deadline: total elapsed time exceeded
                if elapsed >= hard_deadline_secs {
                    log::warn!(
                        "Watchdog: task {watchdog_id} exceeded hard deadline of {hard_deadline_secs}s — force-cancelling transfer (downloaded={downloaded})"
                    );
                    watchdog_cancel.store(true, Ordering::Release);
                    force_error_status(
                        &watchdog_state,
                        &watchdog_id,
                        watchdog_generation,
                        format!(
                            "Download timed out after {hard_deadline_secs} seconds. The transfer did not complete within the allowed time limit."
                        ),
                    );
                    return;
                }

                // Periodic heartbeat log every 30s
                if elapsed > 0 && elapsed % 30 == 0 {
                    log::info!(
                        "Watchdog heartbeat: task {watchdog_id} — {elapsed}s elapsed, downloaded={downloaded}, speed={speed} B/s, status={status}"
                    );
                }
            }
        });
        match state.watchdog_handles.lock() {
            Ok(mut handles) => {
                handles.retain(|h| !h.is_finished());
                handles.push(watchdog_handle);
            }
            Err(e) => log::error!("watchdog_handles lock poisoned: {e}"),
        }
    }
}

/// Force a task to "error" status from an external thread (watchdog).
/// This is used when the curl worker thread is stuck and cannot update
/// the status itself. Checks the generation to prevent a stale watchdog
/// from overwriting a restarted task's state.
fn force_error_status(state: &SharedState, id: &str, generation: u64, message: String) {
    log::error!("Watchdog force-error for task {id}: {message}");
    state.priority_queue.stop_download(id);
    {
        if let Ok(mut stats) = state.download_stats.lock() {
            stats.total_failed += 1;
        }
    }
    let mut jobs = lock_or_err!(state.curl_jobs);
    if let Some(job) = jobs.get_mut(id) {
        if job.task.status == "completed" || job.task.status == "paused" {
            return;
        }
        if generation > 0 && job.run_generation.load(Ordering::Acquire) != generation {
            log::info!(
                "Watchdog for {id}: generation mismatch (ours={generation}, current={}), skipping",
                job.run_generation.load(Ordering::Acquire)
            );
            return;
        }
        job.task.status = "error".to_owned();
        job.task.speed_bytes_per_sec = 0;
        job.task.time_left_seconds = 0;
        job.task.engine_status = Some("watchdog-timeout".to_owned());
        job.task.error_message = Some(message);
        let task = job.task.clone();
        drop(jobs);
        lock_or_err!(state.task_snapshot).insert(id.to_owned(), task);
        state.mark_dirty();
    }
}

/// Generate a unique filename by appending " (1)", " (2)", etc. before the
/// extension, mirroring the browser's `uniquify` conflict resolution.
/// Returns `None` only if the original path has no filename component.
/// Uses atomic `create_new` to prevent TOCTOU races across concurrent tasks.
fn auto_rename_path(original: &std::path::Path) -> Option<std::path::PathBuf> {
    let parent = original.parent()?;
    let stem = original.file_stem()?.to_str()?;
    let ext = original.extension().and_then(|e| e.to_str());

    // Try atomic file creation to eliminate TOCTOU race with concurrent tasks.
    let try_claim = |candidate: &std::path::PathBuf| -> bool {
        match std::fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(candidate)
        {
            Ok(f) => {
                drop(f);
                if let Err(e) = std::fs::remove_file(candidate) {
                    log::warn!(
                        "auto_rename_path: failed to remove placeholder file {}: {e}",
                        candidate.display()
                    );
                }
                true
            }
            Err(_) => false,
        }
    };

    for counter in 1u32..=9999 {
        let new_stem = format!("{stem} ({counter})");
        let new_name = match ext {
            Some(e) => format!("{new_stem}.{e}"),
            None => new_stem,
        };
        let candidate = parent.join(&new_name);
        if !candidate.exists() && try_claim(&candidate) {
            return Some(candidate);
        }
    }
    // Exhausted the counter; append a timestamp + pid as a last resort.
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let new_stem = format!("{}_{}_{}", stem, ts, std::process::id());
    let new_name = match ext {
        Some(e) => format!("{new_stem}.{e}"),
        None => new_stem,
    };
    let candidate = parent.join(&new_name);
    let _ = try_claim(&candidate);
    Some(candidate)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preflight_data_defaults() {
        let p = PreflightData::default();
        assert!(p.protocol.is_empty());
        assert_eq!(p.initial_rtt_us, 0);
        assert_eq!(p.tls_handshake_us, 0);
        assert_eq!(p.connect_us, 0);
        assert_eq!(p.ttfb_us, 0);
        assert!(!p.uses_tls);
        assert!(!p.supports_range);
    }

    #[test]
    #[allow(clippy::field_reassign_with_default)]
    fn preflight_data_clones() {
        let mut p = PreflightData::default();
        p.protocol = "h2".into();
        p.initial_rtt_us = 50000;
        p.tls_handshake_us = 12000;
        p.connect_us = 8000;
        p.ttfb_us = 55000;
        p.uses_tls = true;
        p.supports_range = true;
        let p2 = p.clone();
        assert_eq!(p2.protocol, "h2");
        assert_eq!(p2.initial_rtt_us, 50000);
        assert_eq!(p2.tls_handshake_us, 12000);
        assert_eq!(p2.connect_us, 8000);
        assert_eq!(p2.ttfb_us, 55000);
        assert!(p2.uses_tls);
        assert!(p2.supports_range);
    }
}
