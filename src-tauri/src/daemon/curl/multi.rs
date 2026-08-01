use std::collections::HashMap;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ::curl::easy::{Easy2, Handler};
use ::curl::multi::{Easy2Handle, Events, Multi, Socket, WaitFd};

use super::{AtomicBool, PROGRESS_INTERVAL_MS};
use crate::daemon::direct::ConnectionLimits;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MultiErrorKind {
    Perform,
    SocketAction,
    Wait,
    Timeout,
    SocketAssignment,
}

impl std::fmt::Display for MultiErrorKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Perform => write!(f, "multi perform"),
            Self::SocketAction => write!(f, "multi socket action"),
            Self::Wait => write!(f, "multi wait"),
            Self::Timeout => write!(f, "multi timeout"),
            Self::SocketAssignment => write!(f, "socket assignment"),
        }
    }
}

fn wrap_multi_error(kind: MultiErrorKind, source: String) -> String {
    format!("libcurl {kind}: {source}")
}

pub struct CurlMultiGuard {
    multi: Option<Multi>,
    handle_count: usize,
}

impl CurlMultiGuard {
    pub(crate) fn new() -> Self {
        Self {
            multi: Some(Multi::new()),
            handle_count: 0,
        }
    }

    pub(crate) fn multi(&mut self) -> Result<&mut Multi, String> {
        self.multi.as_mut().ok_or_else(|| {
            "CurlMultiGuard: multi handle has already been consumed via into_inner()".to_owned()
        })
    }

    pub(crate) fn add2<H: Handler>(&mut self, easy: Easy2<H>) -> Result<Easy2Handle<H>, String> {
        let multi = self
            .multi
            .as_mut()
            .ok_or_else(|| "CurlMultiGuard: cannot add handle after into_inner()".to_owned())?;
        let mut handle = multi
            .add2(easy)
            .map_err(|e| format!("Could not add transfer to libcurl multi: {e}"))?;
        // Assign a per-handle token (1..=n in insertion order) so completion
        // messages can be mapped back to their handle in O(1) instead of
        // scanning every handle (see collect_multi_errors).
        handle
            .set_token(self.handle_count + 1)
            .map_err(|e| format!("Could not assign token to libcurl handle: {e}"))?;
        self.handle_count += 1;
        Ok(handle)
    }

    #[cfg(test)]
    pub(crate) fn handle_count(&self) -> usize {
        self.handle_count
    }

    pub(crate) fn configure_limits(&mut self, limits: ConnectionLimits) -> Result<(), String> {
        configure_multi_limits(self.multi()?, limits)
    }

    pub(crate) fn attach_socket_runtime(&mut self) -> Result<MultiSocketRuntime, String> {
        MultiSocketRuntime::attach(self.multi()?)
    }
}

impl Drop for CurlMultiGuard {
    fn drop(&mut self) {
        if self.handle_count > 0 {
            log::debug!(
                "CurlMultiGuard dropping with {} handles still registered; \
                 libcurl will clean up automatically",
                self.handle_count
            );
        }
        self.multi.take();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn multi_guard_new_has_zero_handles() {
        let guard = CurlMultiGuard::new();
        assert_eq!(guard.handle_count(), 0);
    }

    #[test]
    fn multi_guard_error_kind_display() {
        assert_eq!(MultiErrorKind::Perform.to_string(), "multi perform");
        assert_eq!(
            MultiErrorKind::SocketAction.to_string(),
            "multi socket action"
        );
        assert_eq!(MultiErrorKind::Wait.to_string(), "multi wait");
        assert_eq!(MultiErrorKind::Timeout.to_string(), "multi timeout");
        assert_eq!(
            MultiErrorKind::SocketAssignment.to_string(),
            "socket assignment"
        );
    }

    #[test]
    fn multi_guard_drop_logs_when_handles_registered() {
        let guard = CurlMultiGuard::new();
        assert_eq!(guard.handle_count(), 0);
        drop(guard);
    }

    #[test]
    fn multi_guard_configure_limits_succeeds() {
        let mut guard = CurlMultiGuard::new();
        let limits = ConnectionLimits {
            total: 4,
            per_host: 2,
            cache: 8,
        };
        assert!(guard.configure_limits(limits).is_ok());
    }

    #[test]
    fn connection_limits_from_config() {
        use crate::daemon::engine::config::global_config;
        let limits = global_config().connection_limits_for(4, "https://example.com/file");
        assert!(limits.total >= 1);
        assert!(limits.total <= 128);
        assert!(limits.per_host >= 1);
        assert!(limits.cache >= limits.total);
    }

    #[test]
    fn connection_limits_clamp_to_config() {
        use crate::daemon::engine::config::global_config;
        let limits = global_config().connection_limits_for(1000, "https://example.com/file");
        let cfg = global_config();
        assert!(limits.total <= cfg.max_connections_per_download as usize);
        assert!(limits.per_host <= limits.total);
        assert!(limits.total >= 1);
        assert!(limits.per_host >= 1);
    }
}

#[derive(Clone, Copy, Debug)]
pub(super) struct SocketUpdate {
    socket: Socket,
    token: usize,
    input: bool,
    output: bool,
    remove: bool,
}

#[derive(Clone, Copy, Debug)]
pub(super) struct SocketInterest {
    input: bool,
    output: bool,
}

pub struct MultiSocketRuntime {
    updates: Arc<Mutex<Vec<SocketUpdate>>>,
    timeout: Arc<Mutex<Option<Duration>>>,
    pub(super) sockets: HashMap<Socket, SocketInterest>,
    next_token: usize,
}

impl MultiSocketRuntime {
    pub(crate) fn attach(multi: &mut Multi) -> Result<Self, String> {
        let updates = Arc::new(Mutex::new(Vec::new()));
        let socket_updates = updates.clone();
        multi
            .socket_function(move |socket, events, token| {
                if let Ok(mut updates) = socket_updates.lock() {
                    updates.push(SocketUpdate {
                        socket,
                        token,
                        input: events.input(),
                        output: events.output(),
                        remove: events.remove(),
                    });
                }
            })
            .map_err(|e| format!("Could not configure libcurl socket callback: {e}"))?;

        let timeout = Arc::new(Mutex::new(None));
        let timer_timeout = timeout.clone();
        multi
            .timer_function(move |duration| {
                if let Ok(mut timeout) = timer_timeout.lock() {
                    *timeout = duration;
                }
                true
            })
            .map_err(|e| format!("Could not configure libcurl timer callback: {e}"))?;

        Ok(Self {
            updates,
            timeout,
            sockets: HashMap::new(),
            next_token: 1,
        })
    }

    pub(crate) fn drain_updates(&mut self, multi: &Multi) -> Result<(), String> {
        let updates = {
            let mut guard = self
                .updates
                .lock()
                .map_err(|_| "libcurl socket update queue is poisoned".to_owned())?;
            std::mem::take(&mut *guard)
        };

        for update in updates {
            if update.remove {
                self.sockets.remove(&update.socket);
                continue;
            }
            if !update.input && !update.output {
                self.sockets.remove(&update.socket);
                continue;
            }

            if update.token == 0 {
                let token = self.next_token;
                self.next_token = if self.next_token == usize::MAX {
                    1
                } else {
                    self.next_token + 1
                };
                multi.assign(update.socket, token).map_err(|e| {
                    wrap_multi_error(MultiErrorKind::SocketAssignment, e.to_string())
                })?;
            }

            self.sockets.insert(
                update.socket,
                SocketInterest {
                    input: update.input,
                    output: update.output,
                },
            );
        }
        Ok(())
    }

    fn wait_timeout(&self) -> Duration {
        let progress_interval = Duration::from_millis(PROGRESS_INTERVAL_MS);
        let timeout = self
            .timeout
            .lock()
            .ok()
            .and_then(|timeout| *timeout)
            .unwrap_or(progress_interval);
        timeout.min(progress_interval)
    }

    fn wait_fds(&self) -> Vec<(Socket, WaitFd)> {
        self.sockets
            .iter()
            .filter(|(_, interest)| interest.input || interest.output)
            .map(|(socket, interest)| {
                let mut wait_fd = WaitFd::new();
                wait_fd.set_fd(*socket);
                wait_fd.poll_on_read(interest.input);
                wait_fd.poll_on_write(interest.output);
                (*socket, wait_fd)
            })
            .collect()
    }
}

pub fn configure_multi_limits(multi: &mut Multi, limits: ConnectionLimits) -> Result<(), String> {
    multi
        .set_max_total_connections(limits.total)
        .map_err(|e| format!("Could not configure total libcurl connections: {e}"))?;
    multi
        .set_max_host_connections(limits.per_host)
        .map_err(|e| format!("Could not configure host libcurl connections: {e}"))?;
    multi
        .set_max_connects(limits.cache)
        .map_err(|e| format!("Could not configure libcurl connection cache: {e}"))?;
    Ok(())
}

fn collect_multi_errors<H: Handler>(
    multi: &Multi,
    handles: &[Easy2Handle<H>],
    label: &str,
) -> Vec<String> {
    let mut errors = Vec::new();
    // `CurlMultiGuard::add2` assigns tokens 1..=n in insertion order, so the
    // token of `handles[idx]` is `idx + 1`. Building this map once turns the
    // message→handle lookup from O(handles) per message into O(1), avoiding
    // O(n*m) work with many segments.
    let by_token: HashMap<usize, usize> = (0..handles.len()).map(|idx| (idx + 1, idx)).collect();
    multi.messages(|message| {
        // Messages from handles that were never token-assigned carry token 0
        // and simply match no entry.
        let token = message.token().unwrap_or(0);
        if let Some(&idx) = by_token.get(&token) {
            if let Some(Err(error)) = message.result_for2(&handles[idx]) {
                if handles.len() == 1 {
                    errors.push(format!("[{label}] {error}"));
                } else {
                    errors.push(format!("[{label}:{idx}] {error}"));
                }
            }
        }
    });
    errors
}

fn check_multi_messages<H: Handler>(
    multi: &Multi,
    handles: &[Easy2Handle<H>],
    label: &str,
) -> Result<(), String> {
    let errors = collect_multi_errors(multi, handles, label);
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("; "))
    }
}

pub fn drive_multi_wait_perform<H, F>(
    multi: &Multi,
    handles: &[Easy2Handle<H>],
    cancel: &AtomicBool,
    label: &str,
    mut tick: F,
    paused: &AtomicBool,
) -> Result<(), String>
where
    H: Handler,
    F: FnMut(),
{
    let mut running = multi
        .perform()
        .map_err(|e| wrap_multi_error(MultiErrorKind::Perform, e.to_string()))?;
    while running > 0 {
        if cancel.load(Ordering::Acquire) {
            return Err("cancelled".to_owned());
        }
        if paused.load(Ordering::Acquire) {
            // Pause gate: do NOT call perform/action so no bytes move while
            // paused. Sleep briefly and keep ticking so the UI stays fresh and
            // resume is detected promptly.
            std::thread::sleep(Duration::from_millis(PROGRESS_INTERVAL_MS));
            tick();
            continue;
        }
        multi
            .wait(&mut [], Duration::from_millis(PROGRESS_INTERVAL_MS))
            .map_err(|e| wrap_multi_error(MultiErrorKind::Wait, e.to_string()))?;
        tick();
        running = multi
            .perform()
            .map_err(|e| wrap_multi_error(MultiErrorKind::Perform, e.to_string()))?;
        check_multi_messages(multi, handles, label)?;
    }
    tick();
    check_multi_messages(multi, handles, label)
}

pub fn drive_multi_socket<H, F>(
    multi: &Multi,
    runtime: &mut MultiSocketRuntime,
    handles: &[Easy2Handle<H>],
    cancel: &AtomicBool,
    label: &str,
    mut tick: F,
    paused: &AtomicBool,
) -> Result<(), String>
where
    H: Handler,
    F: FnMut(),
{
    let mut running = handles.len() as u32;
    runtime.drain_updates(multi)?;
    if runtime.sockets.is_empty() {
        running = multi
            .timeout()
            .map_err(|e| wrap_multi_error(MultiErrorKind::Timeout, e.to_string()))?;
        runtime.drain_updates(multi)?;
    }

    // Consecutive loops where libcurl reports running > 0 but zero registered
    // sockets indicate a stalled multi state (e.g. a timer-only transfer that
    // never creates sockets). Bail out instead of sleeping forever. The
    // threshold is time-based (not loop-count) so a slow-but-legitimate
    // transfer under an active rate limit is not mistaken for a stall: a
    // capped transfer can sit with no ready sockets for seconds while it
    // trickles data.
    const STALL_GRACE_PERIOD: Duration = Duration::from_secs(5);
    let mut empty_socket_stalls = 0u32;
    let mut empty_socket_since = std::time::Instant::now();

    while running > 0 {
        if cancel.load(Ordering::Acquire) {
            return Err("cancelled".to_owned());
        }

        if paused.load(Ordering::Acquire) {
            // Pause gate: no multi.action calls while paused, so the transfer
            // cannot move bytes. Keep ticking so resume is picked up quickly.
            std::thread::sleep(Duration::from_millis(PROGRESS_INTERVAL_MS));
            runtime.drain_updates(multi)?;
            tick();
            continue;
        }

        let timeout = runtime.wait_timeout();
        if timeout.is_zero() || runtime.sockets.is_empty() {
            if runtime.sockets.is_empty() {
                if empty_socket_stalls == 0 {
                    empty_socket_since = std::time::Instant::now();
                }
                empty_socket_stalls += 1;
                if empty_socket_since.elapsed() > STALL_GRACE_PERIOD {
                    return Err(wrap_multi_error(
                        MultiErrorKind::Wait,
                        "multi handle reports running transfers but no active sockets \
                         for more than the grace period; stalled — aborting drive loop"
                            .to_owned(),
                    ));
                }
            } else {
                empty_socket_stalls = 0;
            }
            // Bounded sleep: never sleep longer than one progress interval, so
            // an empty-socket + running>0 state cannot block indefinitely and
            // the stall counter above gets a chance to break the loop. When
            // the timer is zero (sockets present), keep the original
            // no-sleep behavior and call multi.timeout() immediately.
            let sleep = if runtime.sockets.is_empty() {
                Duration::from_millis(PROGRESS_INTERVAL_MS)
            } else {
                Duration::ZERO
            };
            if !sleep.is_zero() {
                std::thread::sleep(sleep);
            }
            running = multi
                .timeout()
                .map_err(|e| wrap_multi_error(MultiErrorKind::Timeout, e.to_string()))?;
            runtime.drain_updates(multi)?;
            tick();
            check_multi_messages(multi, handles, label)?;
            continue;
        }
        empty_socket_stalls = 0;

        let wait_fds = runtime.wait_fds();
        let sockets: Vec<Socket> = wait_fds.iter().map(|(socket, _)| *socket).collect();
        let interests: Vec<SocketInterest> = sockets
            .iter()
            .filter_map(|socket| runtime.sockets.get(socket).copied())
            .collect();
        let mut wait_fds: Vec<WaitFd> = wait_fds.into_iter().map(|(_, wait_fd)| wait_fd).collect();
        let ready_count = multi
            .wait(&mut wait_fds, timeout)
            .map_err(|e| wrap_multi_error(MultiErrorKind::Wait, e.to_string()))?;

        let mut dispatched = 0u32;
        for (idx, wait_fd) in wait_fds.iter().enumerate() {
            let mut events = Events::new();
            let mut ready = false;
            if wait_fd.received_read() || wait_fd.received_priority_read() {
                events.input(true);
                ready = true;
            }
            if wait_fd.received_write() {
                events.output(true);
                ready = true;
            }
            if ready {
                dispatched = dispatched.saturating_add(1);
                running = multi
                    .action(sockets[idx], &events)
                    .map_err(|e| wrap_multi_error(MultiErrorKind::SocketAction, e.to_string()))?;
                runtime.drain_updates(multi)?;
            }
        }

        if ready_count > 0 && dispatched > 0 {
        } else if wait_fds.is_empty() || ready_count == 0 {
            running = multi
                .timeout()
                .map_err(|e| wrap_multi_error(MultiErrorKind::Timeout, e.to_string()))?;
            runtime.drain_updates(multi)?;
        } else {
            for (idx, interest) in interests.iter().enumerate() {
                let mut events = Events::new();
                events.input(interest.input);
                events.output(interest.output);
                running = multi
                    .action(sockets[idx], &events)
                    .map_err(|e| wrap_multi_error(MultiErrorKind::SocketAction, e.to_string()))?;
                runtime.drain_updates(multi)?;
            }
        }

        tick();
        check_multi_messages(multi, handles, label)?;
    }

    tick();
    check_multi_messages(multi, handles, label)
}
