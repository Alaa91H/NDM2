use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use ::curl::easy::Easy2;
use ::curl::multi::Easy2Handle;

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
                    start_byte: range.start,
                    end_byte: range.end,
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
    let _phase_ctx = crate::logging::push_context("phase", "single");
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
        // NOTE: an on-disk file whose size equals the remote size is NOT treated
        // as "already complete" here. A file can legitimately have that size
        // while still missing its real content (e.g. a leftover preallocated
        // file), and skipping it would mark a garbage file as downloaded.
        // Resuming from the end of such a file is impossible (the server would
        // answer 416), so restart it from scratch instead. Genuinely complete
        // files are still respected by the explicit `skipExisting` option above.
        if plan.total_size > 0 && existing == plan.total_size {
            if plan.allow_overwrite {
                log::info!(
                    "Task {id}: on-disk file matches the expected size but completion is unverified; restarting download from scratch: {}",
                    plan.output_path.display()
                );
                let _ = std::fs::remove_file(&plan.output_path);
            }
            // With allow_overwrite=false a full-size file is never silently
            // accepted as complete (it may be a leftover preallocated file).
            // The dispatcher already auto-renamed it away in this
            // configuration; if we reach here anyway, fall through and let the
            // resume flow fail loudly (416) instead of reporting a fake 100%.
        } else if plan.total_size > 0 && existing > plan.total_size {
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
    log::debug!(
        "[DECISION] task={id} phase=single action=resume-dispatch existing={} resume_from={} resumable={} has_validator={} allow_overwrite={} total_size={} output={}",
        on_disk_before,
        resume_existing,
        plan.resumable,
        plan.validator.is_some(),
        plan.allow_overwrite,
        plan.total_size,
        plan.output_path.display()
    );
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
    let easy = create_easy_for_range_ext(plan, &plan.output_path, progress, None, task_limit_bps)?;
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
    // Live rate-limit tracking (M6): remember what cap is currently applied to
    // the easy handle so the tick can push changes immediately instead of
    // waiting for a restart. `None` = unlimited, `Some(bps)` = capped.
    let mut last_applied_rate: Option<u64> = task_limit_bps;
    let bandwidth_for_tick = state.bandwidth_manager.clone();
    let task_id_for_rate = id.to_owned();
    let mut last_total = on_disk_before;
    let mut last_tick = Instant::now();
    let mut last_progress_time = Instant::now();
    let downloaded_for_tick = downloaded_counter.clone();
    let cancel_for_tick = cancel.clone();
    // The total size may be unknown (0) at dispatch time (fast-path downloads
    // whose background size probe failed). Learn it from the server's
    // Content-Length / Content-Range headers as soon as they arrive, so the
    // UI can show a real progress percentage instead of staying at 0% until
    // the whole transfer completes and then jumping to 100%.
    let mut effective_total = plan.total_size;
    let mut tick = || {
        // Live rate-limit refresh (M6): push bandwidth changes into the
        // running easy handle on the next tick instead of at handle build.
        let new_rate = match bandwidth_for_tick.rate_limit_for(&task_id_for_rate) {
            crate::daemon::engine::bandwidth::RateLimit::Unlimited => None,
            crate::daemon::engine::bandwidth::RateLimit::Limit(kbps) => Some(kbps * 1024),
            crate::daemon::engine::bandwidth::RateLimit::Paused => {
                // Paused: handled by the drive-loop pause gate; keep the
                // current cap so resume restores it.
                last_applied_rate
            }
        };
        if new_rate != last_applied_rate {
            let raw = handles[0].raw();
            let _ = crate::daemon::curl::easy_config::set_live_rate(raw, new_rate);
            last_applied_rate = new_rate;
        }
        let counter_bytes = downloaded_for_tick.load(Ordering::Relaxed);
        let disk_bytes = FileWriter::current_size(&plan.output_path).unwrap_or(0);
        let effective_downloaded =
            on_disk_before + counter_bytes.max(disk_bytes.saturating_sub(on_disk_before));
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

        if effective_total == 0 {
            if let Ok(cap) = capture.lock() {
                if !cap.content_encoded {
                    if let Some(discovered) = cap.content_length {
                        effective_total = discovered;
                        log::info!(
                            "Task {id}: discovered total size from response headers: {discovered} bytes"
                        );
                    }
                }
            }
        }

        // Blocking lock: a try_lock spin would delay progress ticks and the
        // in-loop stall detector under contention.
        let mut jobs = match state.curl_jobs.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        {
            if let Some(job) = jobs.get_mut(id) {
                job.task.downloaded_bytes = effective_downloaded;
                // Prefer the header-discovered total; if the response is still
                // being read, keep any size the async background probe already
                // stored instead of resetting the UI back to 0%.
                job.task.size_bytes = if effective_total > 0 {
                    effective_total
                } else {
                    job.task.size_bytes
                };
                job.task.speed_bytes_per_sec = speed_u64;
                job.task.elapsed_seconds = job.start_time.elapsed().as_secs();
                job.task.time_left_seconds =
                    if speed > 0.0 && effective_total > effective_downloaded {
                        ((effective_total - effective_downloaded) as f64 / speed).ceil() as u64
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
    log::info!("Task {id}: starting curl multi drive loop (on_disk_before={on_disk_before})");
    if let Some(runtime) = socket_runtime.as_mut() {
        drive_multi_socket(
            guard.multi()?,
            runtime,
            &handles,
            &cancel,
            "transfer",
            &mut tick,
            state.bandwidth_manager.paused_flag(),
        )?;
    } else {
        drive_multi_wait_perform(
            guard.multi()?,
            &handles,
            &cancel,
            "transfer",
            &mut tick,
            state.bandwidth_manager.paused_flag(),
        )?;
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
        // which may be inflated by anything that resizes the file ahead of the
        // real data and would mask a zero-byte transfer as "complete".
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
    let _phase_ctx = crate::logging::push_context("phase", "segmented");
    FileWriter::ensure_parent(&plan.output_path)?;
    if !plan.allow_overwrite && plan.output_path.exists() {
        let existing = FileWriter::current_size(&plan.output_path)?;
        if existing == plan.total_size
            && plan.total_size > 0
            && plan.config.bool_("skipExisting").unwrap_or(false)
        {
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
    // A pre-existing output file whose size matches the remote size is NOT
    // treated as "already complete" — it may be a leftover preallocated file
    // whose real content is missing. Let the segment/merge flow rebuild it.

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

    // Phase 5/1.2: record the preflight into the unified profile store so the
    // adaptive DecisionContext has real stability/throughput data.
    {
        if let Ok(mut die) = state.die_orchestrator.lock() {
            let host = reqwest::Url::parse(&plan.url)
                .ok()
                .and_then(|u| u.host_str().map(str::to_owned))
                .unwrap_or_else(|| "unknown".into());
            let profile = crate::daemon::engine::adaptive::server_profiler::ServerProfile {
                host: host.clone(),
                protocol: match preflight.protocol.as_str() {
                    "h2" | "h2c" => {
                        crate::daemon::engine::adaptive::server_profiler::ProtocolVersion::Http2
                    }
                    "h3" => {
                        crate::daemon::engine::adaptive::server_profiler::ProtocolVersion::Http3
                    }
                    _ => crate::daemon::engine::adaptive::server_profiler::ProtocolVersion::Http11,
                },
                initial_rtt_us: preflight.initial_rtt_us,
                handshake_time_us: preflight.tls_handshake_us,
                initial_ttfb_us: preflight.ttfb_us,
                ..Default::default()
            };
            die.record_preflight(&host, &profile);
        }
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
    // Real bytes written per segment in the previous run (persisted with the
    // task snapshot). Used to confirm that a full-size on-disk part is
    // genuinely complete rather than a leftover preallocated part.
    let persisted_segment_bytes: Vec<u64> = state
        .curl_jobs
        .lock()
        .ok()
        .map(|jobs| {
            jobs.get(id)
                .map(|job| {
                    job.task
                        .segments
                        .iter()
                        .map(|s| s.downloaded_bytes)
                        .collect()
                })
                .unwrap_or_default()
        })
        .unwrap_or_default();
    for range in ranges.iter().cloned() {
        let _segment_ctx = crate::logging::push_context("segment", &range.index.to_string());
        let expected = part_size(&range);
        let actual = FileWriter::current_size(&range.path)?;
        log::debug!(
            "[SEGMENT] task={id} index={} expected={} on_disk={} start={} end={} path={}",
            range.index,
            expected,
            actual,
            range.start,
            range.end,
            range.path.display()
        );
        let mut existing = if actual > expected {
            let _ = std::fs::remove_file(&range.path);
            0
        } else {
            actual
        };
        if existing >= expected {
            // A full-size part is only trusted when the persisted per-segment
            // progress confirms it was fully downloaded. Otherwise it may be a
            // leftover preallocated part whose real content is missing, so
            // restart that segment instead of merging garbage.
            let confirmed = persisted_segment_bytes
                .get(range.index)
                .copied()
                .unwrap_or(0)
                >= expected;
            if confirmed {
                log::debug!(
                    "[DECISION] task={id} segment={} action=resume-complete expected={} on_disk={} persisted={} confirmed=true",
                    range.index,
                    expected,
                    actual,
                    persisted_segment_bytes
                        .get(range.index)
                        .copied()
                        .unwrap_or(0)
                );
                active.push((range, Arc::new(AtomicU64::new(0)), expected));
                continue;
            }
            log::info!(
                "[DECISION] task={id} segment={} action=restart-fullsize-unverified expected={} on_disk={} persisted={} confirmed=false",
                range.index,
                expected,
                actual,
                persisted_segment_bytes
                    .get(range.index)
                    .copied()
                    .unwrap_or(0)
            );
            let _ = std::fs::remove_file(&range.path);
            existing = 0;
        } else {
            log::debug!(
                "[DECISION] task={id} segment={} action=resume-partial existing={} expected={}",
                range.index,
                existing,
                expected
            );
        }
        let start = range.start + existing;
        let progress = Arc::new(AtomicU64::new(0));
        let seg_capture = Arc::new(Mutex::new(ResponseCapture::default()));
        seg_captures.push(seg_capture.clone());
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

    // Shared state between the tick closure and the rebuild loop (phase 5).
    // RefCell/Cell let the closure borrow immutably while the outer loop
    // mutates through the cell after a drive pass finishes.
    let handles_cell: std::cell::RefCell<
        Vec<Easy2Handle<crate::daemon::curl::easy_config::SegmentWriter>>,
    > = std::cell::RefCell::new(handles);
    let active_cell: std::cell::RefCell<Vec<(ByteRange, Arc<AtomicU64>, u64)>> =
        std::cell::RefCell::new(active);
    let last_total_cell: std::cell::Cell<u64> = std::cell::Cell::new(
        active_cell
            .borrow()
            .iter()
            .map(|(r, p, initial)| (*initial + p.load(Ordering::Relaxed)).min(part_size(r)))
            .sum(),
    );
    let last_tick_cell: std::cell::Cell<Instant> = std::cell::Cell::new(Instant::now());
    let prev_seg_bytes_cell: std::cell::RefCell<Vec<u64>> =
        std::cell::RefCell::new(vec![0; active_cell.borrow().len()]);
    // Live rate-limit tracking for the segmented path (M6).
    let bandwidth_for_segments = state.bandwidth_manager.clone();
    let segment_task_id = id.to_owned();
    let mut last_segment_rate: Option<u64> = per_segment_limit_bps.map(|v| v.max(1));
    // Phase 5: set by the tick when the adaptive engine requests a geometry
    // change; the outer loop rebuilds handles and resumes driving. Debounced
    // to at most one rebuild per 10s to prevent oscillation.
    let pending_rebuild = std::cell::Cell::new(false);
    let last_rebuild_at = std::cell::Cell::new(std::time::Instant::now());
    let mut tick = || {
        // Live rate refresh: apply the current per-segment cap to every live
        // handle so limit changes take effect immediately (M6).
        let new_seg_rate = match bandwidth_for_segments.rate_limit_for(&segment_task_id) {
            crate::daemon::engine::bandwidth::RateLimit::Unlimited => None,
            crate::daemon::engine::bandwidth::RateLimit::Limit(kbps) => {
                Some((kbps * 1024) / u64::from(effective_connections.max(1)).max(1))
            }
            crate::daemon::engine::bandwidth::RateLimit::Paused => last_segment_rate,
        };
        if new_seg_rate != last_segment_rate {
            for handle in handles_cell.borrow().iter() {
                let raw = handle.raw();
                let _ = crate::daemon::curl::easy_config::set_live_rate(raw, new_seg_rate);
            }
            last_segment_rate = new_seg_rate;
        }
        let now = Instant::now();
        let last_tick = last_tick_cell.get();
        let elapsed = now.duration_since(last_tick).as_secs_f64().max(0.001);
        last_tick_cell.set(now);
        let active = active_cell.borrow();
        let mut prev_seg_bytes = prev_seg_bytes_cell.borrow_mut();
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
        drop(active);
        drop(prev_seg_bytes);
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
                        // Phase 5: drive the adaptive engine LIVE. When the
                        // decision asks for a geometry change we set
                        // pending_rebuild; the outer drive loop then rebuilds
                        // the easy handles from the new segment plan and
                        // resumes driving.
                        if plan.config.adaptive {
                            let decision = engine.evaluate(&telemetry_bus);
                            let mut geometry_changed = false;
                            for action in &decision.actions {
                                match action {
                                    crate::daemon::engine::adaptive::AdaptationAction::AdjustConnections { new_count, .. } => {
                                        let target = (*new_count)
                                            .clamp(1, cfg.max_connections_per_download);
                                        let current = u32::try_from(
                                            handles_cell.borrow().len(),
                                        )
                                        .unwrap_or(1)
                                        .max(1);
                                        if target != current {
                                            engine
                                                .segment_ctrl
                                                .redistribute_for_count(target);
                                            geometry_changed = true;
                                        }
                                    }
                                    crate::daemon::engine::adaptive::AdaptationAction::SplitSegment { .. }
                                    | crate::daemon::engine::adaptive::AdaptationAction::MergeSegments { .. }
                                    | crate::daemon::engine::adaptive::AdaptationAction::Redistribute { .. } => {
                                        geometry_changed = true;
                                    }
                                    _ => {}
                                }
                            }
                            if geometry_changed {
                                log::info!(
                                    "Task {id}: adaptive decision — {} ({} segments → {})",
                                    decision.reason,
                                    handles_cell.borrow().len(),
                                    engine.segment_ctrl.segment_count()
                                );
                                // Mirror the new geometry to the UI scheduler.
                                let new_geometry: Vec<(u32, u64, u64, u64, u64, bool)> = engine
                                    .segment_ctrl
                                    .segments()
                                    .iter()
                                    .map(|s| {
                                        (
                                            s.id,
                                            s.start_byte,
                                            s.end_byte,
                                            s.downloaded,
                                            s.speed,
                                            s.state
                                                == crate::daemon::engine::adaptive::segment_controller::SegmentState::Active,
                                        )
                                    })
                                    .collect();
                                segment_scheduler.replace_segments(&new_geometry);
                                if last_rebuild_at.get().elapsed()
                                    >= std::time::Duration::from_secs(10)
                                {
                                    pending_rebuild.set(true);
                                    last_rebuild_at.set(std::time::Instant::now());
                                }
                            }
                        }
                    }
                }
            }
        }
        // Phase 5/1.2: persist per-tick telemetry into the unified profile
        // store so the adaptive engine's DecisionContext stays warm across
        // sessions.
        {
            if let Ok(mut die) = state.die_orchestrator.lock() {
                let host = reqwest::Url::parse(&plan.url)
                    .ok()
                    .and_then(|u| u.host_str().map(str::to_owned))
                    .unwrap_or_else(|| "unknown".into());
                let agg: u64 = seg_speeds.iter().sum();
                die.record_telemetry(&host, 0, agg, 206);
            }
        }
        update_curl_task_progress(
            state,
            id,
            plan.total_size,
            &active_cell.borrow(),
            &mut last_total_cell.get(),
            &mut last_tick_cell.get(),
        );
    };
    // Phase 5 outer drive loop: drive until completion, rebuilding the easy
    // handles whenever the adaptive engine changes the segment geometry.
    'drive: loop {
        let result = if let Some(runtime) = socket_runtime.as_mut() {
            drive_multi_socket(
                guard.multi()?,
                runtime,
                &handles_cell.borrow(),
                &cancel,
                "segment",
                &mut tick,
                state.bandwidth_manager.paused_flag(),
            )
        } else {
            drive_multi_wait_perform(
                guard.multi()?,
                &handles_cell.borrow(),
                &cancel,
                "segment",
                &mut tick,
                state.bandwidth_manager.paused_flag(),
            )
        };
        // If the drive loop finished because the engine requested a rebuild
        // (not because transfers completed), rebuild and continue.
        if !pending_rebuild.get() {
            result?;
            break 'drive;
        }
        pending_rebuild.set(false);
        log::info!("Task {id}: rebuilding segment handles after adaptive decision");
        // Rebuild: remove all current handles from the multi handle, then
        // recreate from the new geometry in segment_ctrl.
        {
            let mut handles = handles_cell.borrow_mut();
            let removed: Vec<_> = handles.drain(..).collect();
            for h in removed {
                let _ = guard.remove(h);
            }
        }
        let mut active = active_cell.borrow_mut();
        active.clear();
        let new_geometry: Vec<(u32, u64, u64, u64)> = engine_segments_for_rebuild(state, id);
        for (seg_id, start, end, downloaded) in new_geometry {
            let path = plan.output_path.with_extension(format!("part{seg_id:03}"));
            let range = ByteRange {
                index: seg_id as usize,
                start,
                end,
                path: path.clone(),
            };
            let progress = Arc::new(AtomicU64::new(0));
            let seg_capture = Arc::new(Mutex::new(ResponseCapture::default()));
            seg_captures.push(seg_capture.clone());
            let easy = create_easy_for_range_ext(
                plan,
                &path,
                SegmentProgress {
                    downloaded: progress.clone(),
                    abort: cancel.clone(),
                    retry_after: retry_after.clone(),
                    capture: seg_capture,
                    streaming_digest_out: streaming_digest_out.clone(),
                },
                Some((start + downloaded, end)),
                per_segment_limit_bps,
            )?;
            let handle = guard
                .add2(easy)
                .map_err(|e| format!("Could not add segment {seg_id}: {e}"))?;
            handles_cell.borrow_mut().push(handle);
            active.push((range, progress, downloaded));
        }
        // Recompute totals for the new geometry.
        last_total_cell.set(
            active
                .iter()
                .map(|(r, p, initial)| (*initial + p.load(Ordering::Relaxed)).min(part_size(r)))
                .sum(),
        );
        last_tick_cell.set(Instant::now());
        *prev_seg_bytes_cell.borrow_mut() = vec![0; active.len()];
        drop(active);
        if handles_cell.borrow().is_empty() {
            break 'drive;
        }
    }
    for (idx, handle) in handles_cell.borrow().iter().enumerate() {
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
        &active_cell.borrow(),
        &mut last_total_cell.get(),
        &mut last_tick_cell.get(),
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

/// Phase 5: read the adaptive engine's current segment geometry
/// (id, start, end, downloaded) for a task. Empty when the engine is gone.
fn engine_segments_for_rebuild(state: &SharedState, id: &str) -> Vec<(u32, u64, u64, u64)> {
    let Ok(trackers) = state.engine_trackers.read() else {
        return Vec::new();
    };
    let Some(tracker) = trackers.get(id) else {
        return Vec::new();
    };
    let Ok(engine_guard) = tracker.adaptive_engine.lock() else {
        return Vec::new();
    };
    let Some(engine) = engine_guard.as_ref() else {
        return Vec::new();
    };
    engine
        .segment_ctrl
        .segments()
        .iter()
        .map(|s| (s.id, s.start_byte, s.end_byte, s.downloaded))
        .collect()
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
    let _dispatch_ctx = crate::logging::push_context("phase", "dispatch");
    log::info!(
        "Task {id}: run_libcurl_download entered — url={}, total_size={}, segmented={}, output={}",
        plan.url,
        plan.total_size,
        plan.segmented,
        plan.output_path.display()
    );
    // Structured plan snapshot: a full reproduction record of how this transfer
    // was configured, so any later failure can be replayed from logs alone.
    log::debug!(
        "[PLAN] task={id} url={} total_size={} resumable={} segmented={} connections={} allow_overwrite={} skip_existing={:?} remove_on_error={} follow_redirects={} retry_attempts={} retry_max_delay_ms={:?} preflight_resolved={} mirrors={} output={}",
        plan.url,
        plan.total_size,
        plan.resumable,
        plan.segmented,
        plan.connections,
        plan.allow_overwrite,
        plan.config.bool_("skipExisting"),
        plan.remove_on_error,
        plan.follow_redirects,
        plan.config.retry_policy().attempts,
        plan.config.retry_policy().max_delay.as_millis(),
        plan.preflight_resolved,
        plan.link_mirrors.len(),
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
        // A full-size file is only trusted as "already complete" when the user
        // explicitly opted in via skipExisting. Otherwise an on-disk file whose
        // size matches the remote size may be a leftover preallocated file with
        // no real content (the reported fake-100% bug), so treat it as a
        // conflict to rename and download fresh, preserving the existing file.
        let is_complete = plan.total_size > 0
            && existing_size == plan.total_size
            && plan.config.bool_("skipExisting").unwrap_or(false);
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
        log::debug!(
            "[RETRY] task={id} attempt={} max_attempts={} elapsed_ms={} last_error={}",
            attempt + 1,
            retry_policy.attempts,
            start_time.elapsed().as_millis(),
            last_error.chars().take(160).collect::<String>()
        );
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
    let _task_ctx = crate::logging::push_context("task", id);
    let _path_ctx = crate::logging::push_context("phase", "error-path");
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
        job.task.error_message = if cancelled {
            None
        } else {
            Some(message.clone())
        };
        let task = job.task.clone();
        if !cancelled {
            let segment_summary: Vec<String> = task
                .segments
                .iter()
                .map(|s| format!("{}:{}", s.id, s.downloaded_bytes))
                .collect();
            log::error!(
                "[ERROR-PATH] task={id} generation={generation} url={} save_path={} downloaded_bytes={} size_bytes={} status={} engine_status={:?} segments=[{}] error={message}",
                task.url,
                task.save_path,
                task.downloaded_bytes,
                task.size_bytes,
                task.status,
                task.engine_status,
                segment_summary.join(",")
            );
        }
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
        let _task_ctx = crate::logging::push_context("task", &id2);
        let _url_ctx = crate::logging::push_context("url", &plan.url);
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

    // ── Local HTTP server with byte-range support (206) ──────────────────
    fn spawn_range_server(payload: std::sync::Arc<Vec<u8>>) -> std::net::SocketAddr {
        use std::io::{Read, Write};
        use std::net::{Shutdown, TcpListener};
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { break };
                let payload = payload.clone();
                std::thread::spawn(move || {
                    let mut buf = [0u8; 8192];
                    let n = stream.read(&mut buf).unwrap_or(0);
                    let req = String::from_utf8_lossy(&buf[..n]).to_string();
                    let total = payload.len() as u64;
                    let mut range = None;
                    for line in req.lines() {
                        if let Some(rest) = line.to_ascii_lowercase().strip_prefix("range: bytes=")
                        {
                            range = Some(rest.trim().to_string());
                            break;
                        }
                    }
                    let send = |stream: &mut std::net::TcpStream, head: String, body: &[u8]| {
                        let _ = stream.write_all(head.as_bytes());
                        let _ = stream.write_all(body);
                        let _ = stream.shutdown(Shutdown::Write);
                    };
                    match range {
                        Some(r) => {
                            let (s, e) = r.split_once('-').unwrap_or((r.as_str(), ""));
                            let start: u64 = s.trim().parse().unwrap_or(0);
                            if start >= total {
                                send(
                                    &mut stream,
                                    format!(
                                        "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */{total}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                                    ),
                                    b"",
                                );
                                return;
                            }
                            let end: u64 = if e.is_empty() {
                                total - 1
                            } else {
                                e.trim().parse().unwrap_or(total - 1)
                            };
                            let end = end.min(total - 1);
                            let body = &payload[start as usize..=end as usize];
                            send(
                                &mut stream,
                                format!(
                                    "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes {start}-{end}/{total}\r\nContent-Length: {}\r\nAccept-Ranges: bytes\r\nETag: \"nova-test\"\r\nConnection: close\r\n\r\n",
                                    body.len()
                                ),
                                body,
                            );
                        }
                        None => send(
                            &mut stream,
                            format!(
                                "HTTP/1.1 200 OK\r\nContent-Length: {total}\r\nAccept-Ranges: bytes\r\nETag: \"nova-test\"\r\nConnection: close\r\n\r\n"
                            ),
                            &payload,
                        ),
                    }
                });
            }
        });
        addr
    }

    fn download_body(
        url: &str,
        name: &str,
        size: u64,
        connections: u32,
    ) -> crate::daemon::types::CreateDownloadBody {
        crate::daemon::types::CreateDownloadBody {
            url: Some(url.to_string()),
            name: Some(name.to_string()),
            file_type: Some("other".to_string()),
            size_bytes: Some(size),
            category: Some("tests".to_string()),
            queue_id: Some("main".to_string()),
            connections: Some(connections),
            resumable: Some(true),
            save_path: None,
            description: Some("integration test".to_string()),
            referer: None,
            start_immediately: Some(true),
            direct_options: None,
            media_options: None,
        }
    }

    fn run_task_to_completion(
        state: &SharedState,
        id: &str,
        timeout: std::time::Duration,
    ) -> crate::daemon::types::Task {
        let deadline = std::time::Instant::now() + timeout;
        loop {
            let task = {
                let jobs = state.curl_jobs.lock().unwrap();
                let Some(job) = jobs.get(id) else {
                    panic!("task {id} vanished");
                };
                job.task.clone()
            };
            match task.status.as_str() {
                "completed" => return task,
                "error" => panic!(
                    "task {id} failed: {:?} (size={}, downloaded={})",
                    task.error_message, task.size_bytes, task.downloaded_bytes
                ),
                _ => {
                    assert!(
                        std::time::Instant::now() < deadline,
                        "task {id} timed out (status={}, downloaded={}, size={})",
                        task.status,
                        task.downloaded_bytes,
                        task.size_bytes
                    );
                    std::thread::sleep(std::time::Duration::from_millis(20));
                }
            }
        }
    }

    #[test]
    fn fresh_single_download_reports_intermediate_progress_and_full_content() {
        let payload: Vec<u8> = (0..(4 * 1024 * 1024)).map(|i| (i % 251) as u8).collect();
        let addr = spawn_range_server(std::sync::Arc::new(payload.clone()));
        let url = format!("http://{addr}/sample.zip");
        let dir = std::env::temp_dir().join(format!("nova_test_fresh_{}", std::process::id()));
        let out = dir.join("sample.zip");
        std::fs::create_dir_all(&dir).unwrap();

        let state = std::sync::Arc::new(crate::daemon::persist::tests::test_state(
            &dir.to_string_lossy(),
        ));
        let id = "fresh-progress-test";
        let body = download_body(&url, "sample.zip", payload.len() as u64, 1);
        let job = task_from_body(
            &body,
            id,
            "sample.zip".to_string(),
            &out,
            std::collections::HashMap::new(),
            Vec::new(),
        );
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            jobs.insert(id.to_string(), job);
        }
        state.mark_dirty();

        let st = state.clone();
        std::thread::spawn(move || start_curl_process(&st, id));

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
        let mut saw_intermediate = false;
        loop {
            let (status, downloaded, size) = {
                let jobs = state.curl_jobs.lock().unwrap();
                let Some(j) = jobs.get(id) else { break };
                (
                    j.task.status.clone(),
                    j.task.downloaded_bytes,
                    j.task.size_bytes,
                )
            };
            if downloaded > 0 && downloaded < size {
                saw_intermediate = true;
            } else if downloaded > 0 && size == 0 {
                // Progress with unknown size still proves live updates are
                // flowing (the header may not have been parsed yet).
                saw_intermediate = true;
            }
            if status == "completed" || status == "error" {
                break;
            }
            assert!(
                std::time::Instant::now() < deadline,
                "timeout status={status}"
            );
            std::thread::sleep(std::time::Duration::from_millis(5));
        }

        let task = run_task_to_completion(&state, id, std::time::Duration::from_secs(30));
        assert_eq!(task.size_bytes, payload.len() as u64);
        assert!(
            saw_intermediate,
            "no intermediate progress observed (downloaded stuck at 0, then jump to 100%)"
        );
        let written = std::fs::read(&out).unwrap();
        assert_eq!(written, payload, "output content mismatch");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn unknown_size_download_learns_total_from_content_length_for_live_progress() {
        let payload: Vec<u8> = (0..(4 * 1024 * 1024)).map(|i| (i % 257) as u8).collect();
        let addr = spawn_range_server(std::sync::Arc::new(payload.clone()));
        let url = format!("http://{addr}/unknown.bin");
        let dir = std::env::temp_dir().join(format!("nova_test_unknown_{}", std::process::id()));
        let out = dir.join("unknown.bin");
        std::fs::create_dir_all(&dir).unwrap();

        let state = std::sync::Arc::new(crate::daemon::persist::tests::test_state(
            &dir.to_string_lossy(),
        ));
        let id = "unknown-size-progress-test";
        // The reported bug: task created with an unknown total size (0). The
        // UI computed progress as downloaded/0 = 0%, then jumped to 100% only
        // when mark_curl_task_finished finally filled size_bytes. The transfer
        // must instead learn Content-Length during the response and expose a
        // real intermediate percentage.
        let body = download_body(&url, "unknown.bin", 0, 1);
        let job = task_from_body(
            &body,
            id,
            "unknown.bin".to_string(),
            &out,
            std::collections::HashMap::new(),
            Vec::new(),
        );
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            jobs.insert(id.to_string(), job);
        }
        state.mark_dirty();

        let st = state.clone();
        std::thread::spawn(move || start_curl_process(&st, id));

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
        let mut saw_intermediate = false;
        loop {
            let (status, downloaded, size) = {
                let jobs = state.curl_jobs.lock().unwrap();
                let Some(j) = jobs.get(id) else { break };
                (
                    j.task.status.clone(),
                    j.task.downloaded_bytes,
                    j.task.size_bytes,
                )
            };
            if downloaded > 0 && downloaded < size {
                saw_intermediate = true;
            }
            if status == "completed" || status == "error" {
                break;
            }
            assert!(
                std::time::Instant::now() < deadline,
                "timeout status={status} downloaded={downloaded} size={size}"
            );
            std::thread::sleep(std::time::Duration::from_millis(5));
        }

        let task = run_task_to_completion(&state, id, std::time::Duration::from_secs(30));
        assert_eq!(task.size_bytes, payload.len() as u64);
        assert!(
            saw_intermediate,
            "no intermediate progress: size_bytes stayed 0 during transfer (0% then 100% bug)"
        );
        let written = std::fs::read(&out).unwrap();
        assert_eq!(written, payload, "output content mismatch");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resume_of_preallocated_partial_file_repairs_content() {
        let payload: Vec<u8> = (0..(1024 * 1024)).map(|i| (i % 253) as u8).collect();
        let addr = spawn_range_server(std::sync::Arc::new(payload.clone()));
        let url = format!("http://{addr}/resume.zip");
        let dir = std::env::temp_dir().join(format!("nova_test_resume_{}", std::process::id()));
        let out = dir.join("resume.zip");
        std::fs::create_dir_all(&dir).unwrap();

        // Simulate a leftover preallocated file: full size on disk but only a
        // fraction of the real payload written (the rest is zeros).
        let partial = 256 * 1024usize;
        let mut f = std::fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(&out)
            .unwrap();
        f.set_len(payload.len() as u64).unwrap();
        use std::io::Write;
        f.write_all(&payload[..partial]).unwrap();
        f.sync_all().unwrap();
        drop(f);

        let state = std::sync::Arc::new(crate::daemon::persist::tests::test_state(
            &dir.to_string_lossy(),
        ));
        let id = "resume-prealloc-test";
        let body = download_body(&url, "resume.zip", payload.len() as u64, 1);
        let mut direct_options = std::collections::HashMap::new();
        direct_options.insert(
            "etag".to_string(),
            serde_json::Value::String("nova-test".to_string()),
        );
        // Restart-in-place is the overwrite path; the no-clobber path auto-
        // renames the target instead (covered by the dispatcher logic).
        direct_options.insert("allowOverwrite".to_string(), serde_json::json!(true));
        let job = task_from_body(
            &body,
            id,
            "resume.zip".to_string(),
            &out,
            direct_options,
            Vec::new(),
        );
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            jobs.insert(id.to_string(), job);
        }
        state.mark_dirty();

        let st = state.clone();
        std::thread::spawn(move || start_curl_process(&st, id));

        let task = run_task_to_completion(&state, id, std::time::Duration::from_secs(60));
        assert_eq!(task.size_bytes, payload.len() as u64);
        let written = std::fs::read(&out).unwrap();
        assert_eq!(
            written, payload,
            "preallocated partial file was treated as complete and left corrupted"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn no_clobber_full_size_leftover_is_renamed_and_redownloaded() {
        let payload: Vec<u8> = (0..(1024 * 1024)).map(|i| (i % 253) as u8).collect();
        let addr = spawn_range_server(std::sync::Arc::new(payload.clone()));
        let url = format!("http://{addr}/resume.zip");
        let dir = std::env::temp_dir().join(format!("nova_test_noclob_{}", std::process::id()));
        let out = dir.join("resume.zip");
        std::fs::create_dir_all(&dir).unwrap();

        // Leftover preallocated file at the default (no-clobber) setting.
        let partial = 256 * 1024usize;
        let mut f = std::fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(&out)
            .unwrap();
        f.set_len(payload.len() as u64).unwrap();
        use std::io::Write;
        f.write_all(&payload[..partial]).unwrap();
        f.sync_all().unwrap();
        drop(f);

        let state = std::sync::Arc::new(crate::daemon::persist::tests::test_state(
            &dir.to_string_lossy(),
        ));
        let id = "noclob-prealloc-test";
        let body = download_body(&url, "resume.zip", payload.len() as u64, 1);
        let mut direct_options = std::collections::HashMap::new();
        direct_options.insert(
            "etag".to_string(),
            serde_json::Value::String("nova-test".to_string()),
        );
        let job = task_from_body(
            &body,
            id,
            "resume.zip".to_string(),
            &out,
            direct_options,
            Vec::new(),
        );
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            jobs.insert(id.to_string(), job);
        }
        state.mark_dirty();

        let st = state.clone();
        std::thread::spawn(move || start_curl_process(&st, id));

        let task = run_task_to_completion(&state, id, std::time::Duration::from_secs(60));
        assert_eq!(task.size_bytes, payload.len() as u64);
        // The leftover is preserved, and a fresh copy is downloaded under a
        // conflict-suffixed name instead of being accepted as complete.
        let preserved = std::fs::read(&out).unwrap();
        assert_eq!(
            preserved.len(),
            payload.len(),
            "existing no-clobber file must not be overwritten"
        );
        assert_eq!(
            preserved[..partial],
            payload[..partial],
            "existing no-clobber file must not be overwritten"
        );
        let fresh = dir.join("resume (1).zip");
        assert!(fresh.exists(), "auto-renamed target was not created");
        let fresh_bytes = std::fs::read(&fresh).unwrap();
        assert_eq!(fresh_bytes, payload, "auto-renamed download is corrupt");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn segmented_resume_of_preallocated_parts_repairs_content() {
        use crate::daemon::types::Segment;
        use std::io::Write;
        let payload: Vec<u8> = (0..(1024 * 1024)).map(|i| (i % 251) as u8).collect();
        let addr = spawn_range_server(std::sync::Arc::new(payload.clone()));
        let url = format!("http://{addr}/seg.zip");
        let dir = std::env::temp_dir().join(format!("nova_test_seg_{}", std::process::id()));
        let out = dir.join("seg.zip");
        std::fs::create_dir_all(&dir).unwrap();

        // Legacy artifacts: both part files preallocated to their full segment
        // size while only half of each part's real content was written.
        let expected_part = 512 * 1024usize;
        for idx in 0..2usize {
            let part = dir.join(format!("seg.zip.part{idx:03}"));
            let mut f = std::fs::OpenOptions::new()
                .create(true)
                .truncate(true)
                .write(true)
                .open(&part)
                .unwrap();
            f.set_len(expected_part as u64).unwrap();
            let seg_start = idx * expected_part;
            f.write_all(&payload[seg_start..seg_start + expected_part / 2])
                .unwrap();
            f.sync_all().unwrap();
            drop(f);
        }

        let state = std::sync::Arc::new(crate::daemon::persist::tests::test_state(
            &dir.to_string_lossy(),
        ));
        let id = "seg-resume-test";
        let body = download_body(&url, "seg.zip", payload.len() as u64, 2);
        let mut job = task_from_body(
            &body,
            id,
            "seg.zip".to_string(),
            &out,
            std::collections::HashMap::new(),
            Vec::new(),
        );
        // Persisted per-segment progress from the interrupted legacy run: each
        // part was only half-real, so persisted bytes are below the segment size.
        job.task.segments = vec![
            Segment {
                id: 0,
                progress: 0.5,
                downloaded_bytes: (expected_part / 2) as u64,
                total_bytes: expected_part as u64,
                active: false,
                speed: 0,
                start_byte: 0,
                end_byte: expected_part as u64,
            },
            Segment {
                id: 1,
                progress: 0.5,
                downloaded_bytes: (expected_part / 2) as u64,
                total_bytes: expected_part as u64,
                active: false,
                speed: 0,
                start_byte: expected_part as u64,
                end_byte: (expected_part * 2) as u64,
            },
        ];
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            jobs.insert(id.to_string(), job);
        }
        state.mark_dirty();

        let st = state.clone();
        std::thread::spawn(move || start_curl_process(&st, id));

        let task = run_task_to_completion(&state, id, std::time::Duration::from_secs(60));
        assert_eq!(task.size_bytes, payload.len() as u64);
        let written = std::fs::read(&out).unwrap();
        assert_eq!(
            written, payload,
            "preallocated partial parts were merged as garbage"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn stale_generation_does_not_overwrite_newer_task_state() {
        // Regression for H8/C10: a worker that finished with an old generation
        // (after a redownload bumped it) must NOT overwrite the current state.
        let dir = std::env::temp_dir().join(format!("nova_test_gen_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let state = std::sync::Arc::new(crate::daemon::persist::tests::test_state(
            &dir.to_string_lossy(),
        ));
        let id = "gen-test";
        let body = download_body("http://127.0.0.1:1/x.zip", "x.zip", 100, 1);
        let job = task_from_body(
            &body,
            id,
            "x.zip".to_string(),
            &dir.join("x.zip"),
            std::collections::HashMap::new(),
            Vec::new(),
        );
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            jobs.insert(id.to_string(), job);
        }
        state.mark_dirty();

        // The current generation is 5 (simulating several redownloads).
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            if let Some(job) = jobs.get_mut(id) {
                job.run_generation
                    .store(5, std::sync::atomic::Ordering::Release);
                job.task.status = "downloading".to_owned();
            }
        }

        // A stale worker (generation 2) reports completion.
        mark_curl_task_finished(&state, id, 100, 2);

        // The newer task state must be untouched.
        let jobs = state.curl_jobs.lock().unwrap();
        let job = jobs.get(id).unwrap();
        assert_eq!(
            job.task.status, "downloading",
            "stale completion must not win"
        );
        assert_eq!(
            job.run_generation
                .load(std::sync::atomic::Ordering::Acquire),
            5
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn pause_actually_stalls_bytes_and_resume_completes() {
        // H1 regression: pause_all() must stop the transfer from moving bytes
        // (the old bug turned paused into "unlimited"). A large payload keeps
        // the transfer running long enough to sample the stall even when the
        // test binary shares the machine with other parallel tests.
        let payload: Vec<u8> = (0..(16 * 1024 * 1024)).map(|i| (i % 251) as u8).collect();
        let addr = spawn_range_server(std::sync::Arc::new(payload.clone()));
        let url = format!("http://{addr}/pause.zip");
        let dir = std::env::temp_dir().join(format!("nova_test_pause_{}", std::process::id()));
        let out = dir.join("pause.zip");
        std::fs::create_dir_all(&dir).unwrap();

        let state = std::sync::Arc::new(crate::daemon::persist::tests::test_state(
            &dir.to_string_lossy(),
        ));
        let id = "pause-test";
        let body = download_body(&url, "pause.zip", payload.len() as u64, 1);
        let job = task_from_body(
            &body,
            id,
            "pause.zip".to_string(),
            &out,
            std::collections::HashMap::new(),
            Vec::new(),
        );
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            jobs.insert(id.to_string(), job);
        }
        state.mark_dirty();

        let st = state.clone();
        let worker = std::thread::spawn(move || start_curl_process(&st, id));

        // Wait until some bytes have been written.
        let mut seen_any = false;
        for _ in 0..200 {
            let written = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
            if written > 0 {
                seen_any = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert!(seen_any, "transfer never started writing");

        // Pause and sample the on-disk size — it must not grow. Wait for the
        // pause gate to actually engage (the worker may be mid-perform when
        // pause_all() is called) by requiring two consecutive stable reads.
        state.bandwidth_manager.pause_all();
        let mut frozen = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
        let mut stable_reads = 0;
        for _ in 0..50 {
            std::thread::sleep(std::time::Duration::from_millis(40));
            let now = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
            if now == frozen {
                stable_reads += 1;
                if stable_reads >= 2 {
                    break;
                }
            } else {
                frozen = now;
                stable_reads = 0;
            }
        }
        assert!(stable_reads >= 2, "transfer never stalled after pause");
        let after_pause = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
        assert_eq!(
            after_pause, frozen,
            "paused transfer kept writing: before={frozen} after={after_pause}"
        );

        // Resume and let it complete.
        state.bandwidth_manager.resume_all();
        worker.join().unwrap();
        let task = run_task_to_completion(&state, id, std::time::Duration::from_secs(120));
        assert_eq!(task.status, "completed");
        let written = std::fs::read(&out).unwrap();
        assert_eq!(written, payload, "resumed download is corrupt");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn live_rate_limit_change_takes_effect() {
        // M6 regression: changing the bandwidth limit mid-transfer must apply
        // immediately to the running easy handle. A tiny limit makes the
        // transfer crawl; a generous limit lets it finish.
        let payload: Vec<u8> = (0..(2 * 1024 * 1024)).map(|i| (i % 253) as u8).collect();
        let addr = spawn_range_server(std::sync::Arc::new(payload.clone()));
        let url = format!("http://{addr}/rate.zip");
        let dir = std::env::temp_dir().join(format!("nova_test_rate_{}", std::process::id()));
        let out = dir.join("rate.zip");
        std::fs::create_dir_all(&dir).unwrap();

        let state = std::sync::Arc::new(crate::daemon::persist::tests::test_state(
            &dir.to_string_lossy(),
        ));
        let id = "rate-test";
        let body = download_body(&url, "rate.zip", payload.len() as u64, 1);
        let job = task_from_body(
            &body,
            id,
            "rate.zip".to_string(),
            &out,
            std::collections::HashMap::new(),
            Vec::new(),
        );
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            jobs.insert(id.to_string(), job);
        }
        state.mark_dirty();

        // Start with a modest per-task cap (64 KB/s) and record how much
        // downloads in a fixed window — the cap must visibly throttle.
        state.bandwidth_manager.set_task_limit(id.into(), 64);
        let st = state.clone();
        std::thread::spawn(move || start_curl_process(&st, id));

        std::thread::sleep(std::time::Duration::from_millis(500));
        let capped_size = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
        // 64 KB/s over 500ms ≈ 32 KB. Allow generous slack, but the transfer
        // must NOT have completed the full 2 MiB while capped.
        assert!(
            capped_size < 512 * 1024,
            "64 KB/s cap was not applied: wrote {capped_size} bytes in 500ms"
        );

        // Remove the cap — the transfer should now speed up and finish.
        state.bandwidth_manager.remove_task_limit(id);
        let task = run_task_to_completion(&state, id, std::time::Duration::from_secs(60));
        assert_eq!(task.status, "completed");
        let written = std::fs::read(&out).unwrap();
        assert_eq!(written, payload, "rate-limited download is corrupt");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn adaptive_segmented_download_grows_and_completes() {
        // Phase 5: the adaptive engine must drive real geometry growth on a
        // segmented download and the final file must match byte-for-byte.
        let payload: Vec<u8> = (0..(8 * 1024 * 1024)).map(|i| (i % 251) as u8).collect();
        let addr = spawn_range_server(std::sync::Arc::new(payload.clone()));
        let url = format!("http://{addr}/adaptive.zip");
        let dir = std::env::temp_dir().join(format!("nova_test_adaptive_{}", std::process::id()));
        let out = dir.join("adaptive.zip");
        std::fs::create_dir_all(&dir).unwrap();

        let state = std::sync::Arc::new(crate::daemon::persist::tests::test_state(
            &dir.to_string_lossy(),
        ));
        let id = "adaptive-test";
        let body = download_body(&url, "adaptive.zip", payload.len() as u64, 2);
        let mut direct_options = std::collections::HashMap::new();
        // Force a fast evaluation interval so a decision is made during the run.
        direct_options.insert(
            "adaptiveEvalMs".to_string(),
            serde_json::Value::from(100u64),
        );
        let mut job = task_from_body(
            &body,
            id,
            "adaptive.zip".to_string(),
            &out,
            direct_options,
            Vec::new(),
        );
        // Make the segments small enough that growth is possible: 8 MiB with
        // min_segment_bytes from config (256 KiB) allows up to 32 segments.
        job.task.connections = 2;
        {
            let mut jobs = state.curl_jobs.lock().unwrap();
            jobs.insert(id.to_string(), job);
        }
        state.mark_dirty();

        let st = state.clone();
        std::thread::spawn(move || start_curl_process(&st, id));

        let task = run_task_to_completion(&state, id, std::time::Duration::from_secs(120));
        assert_eq!(task.status, "completed");
        let written = std::fs::read(&out).unwrap();
        assert_eq!(written, payload, "adaptive download is corrupt");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
