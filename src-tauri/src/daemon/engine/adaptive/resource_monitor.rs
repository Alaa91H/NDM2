use std::time::{Duration, Instant};

#[derive(Clone, Debug)]
pub struct ResourceSnapshot {
    pub cpu_count: u32,
    pub cpu_usage_pct: f32,
    pub available_memory_mb: u64,
    pub disk_write_mbps: u64,
    pub disk_active: bool,
}

impl Default for ResourceSnapshot {
    fn default() -> Self {
        Self {
            cpu_count: Self::detect_cpu_count(),
            cpu_usage_pct: 0.0,
            available_memory_mb: 0,
            disk_write_mbps: 0,
            disk_active: false,
        }
    }
}

impl ResourceSnapshot {
    fn detect_cpu_count() -> u32 {
        std::thread::available_parallelism().map_or(4, |n| n.get() as u32)
    }
}

pub struct ResourceMonitor {
    last_sample: Instant,
    sample_interval: Duration,
    cpu_count: u32,
    available_memory_mb: u64,
    snapshot: ResourceSnapshot,
    prev_disk_bytes_written: u64,
    prev_idle_ticks: u64,
    prev_total_ticks: u64,
    has_prev_ticks: bool,
}

impl ResourceMonitor {
    pub fn new() -> Self {
        let cpu_count = ResourceSnapshot::detect_cpu_count();
        Self {
            last_sample: Instant::now(),
            sample_interval: Duration::from_secs(2),
            cpu_count,
            available_memory_mb: 0,
            snapshot: ResourceSnapshot {
                cpu_count,
                ..Default::default()
            },
            prev_disk_bytes_written: 0,
            prev_idle_ticks: 0,
            prev_total_ticks: 0,
            has_prev_ticks: false,
        }
    }

    pub fn sample(&mut self) -> &ResourceSnapshot {
        let now = Instant::now();
        if now.duration_since(self.last_sample) < self.sample_interval {
            return &self.snapshot;
        }
        let prev_time = self.last_sample;
        self.last_sample = now;

        self.sample_memory();

        let (disk_write_mbps, disk_active) = self.sample_disk_io(now, prev_time);

        self.snapshot = ResourceSnapshot {
            cpu_count: self.cpu_count,
            cpu_usage_pct: self.estimate_cpu_usage(),
            available_memory_mb: self.available_memory_mb,
            disk_write_mbps,
            disk_active,
        };
        &self.snapshot
    }

    pub fn detect_cpu_count() -> u32 {
        ResourceSnapshot::detect_cpu_count()
    }

    pub const fn cpu_count(&self) -> u32 {
        self.cpu_count
    }

    pub fn max_safe_connections(&self) -> u32 {
        let base = self.cpu_count * 2;
        let mem_factor = if self.available_memory_mb > 1024 {
            base
        } else if self.available_memory_mb > 512 {
            (base * 3) / 4
        } else {
            base / 2
        };
        mem_factor.clamp(2, 32)
    }

    pub const fn disk_bottleneck(&self) -> bool {
        self.snapshot.disk_write_mbps > 0 && self.snapshot.disk_write_mbps < 10
    }

    pub fn cpu_saturated(&self) -> bool {
        self.snapshot.cpu_usage_pct > 0.85
    }

    pub fn disk_write_budget(&self, connections: u32) -> u64 {
        if self.snapshot.disk_write_mbps == 0 {
            return 0;
        }
        let total_bps = self.snapshot.disk_write_mbps * 1024 * 1024;
        total_bps / u64::from(connections.max(1))
    }

    pub fn snapshot_clone(&self) -> ResourceSnapshot {
        self.snapshot.clone()
    }

    fn estimate_cpu_usage(&mut self) -> f32 {
        #[cfg(target_os = "windows")]
        {
            self.estimate_cpu_usage_windows()
        }
        #[cfg(not(target_os = "windows"))]
        {
            self.estimate_cpu_usage_fallback()
        }
    }

    #[cfg(target_os = "windows")]
    fn estimate_cpu_usage_windows(&mut self) -> f32 {
        #[repr(C)]
        struct FileTime {
            dw_low_date_time: u32,
            dw_high_date_time: u32,
        }

        #[repr(C)]
        struct SystemTimes {
            idle_time: FileTime,
            kernel_time: FileTime,
            user_time: FileTime,
        }

        extern "system" {
            fn GetSystemTimes(
                idle_time: *mut FileTime,
                kernel_time: *mut FileTime,
                user_time: *mut FileTime,
            ) -> i32;
        }

        let mut idle = FileTime {
            dw_low_date_time: 0,
            dw_high_date_time: 0,
        };
        let mut kernel = FileTime {
            dw_low_date_time: 0,
            dw_high_date_time: 0,
        };
        let mut user = FileTime {
            dw_low_date_time: 0,
            dw_high_date_time: 0,
        };

        let success = unsafe { GetSystemTimes(&mut idle, &mut kernel, &mut user) };

        if success == 0 {
            return self.estimate_cpu_usage_fallback();
        }

        fn file_time_to_u64(ft: &FileTime) -> u64 {
            (u64::from(ft.dw_high_date_time) << 32) | u64::from(ft.dw_low_date_time)
        }

        let idle_ticks = file_time_to_u64(&idle);
        let kernel_ticks = file_time_to_u64(&kernel);
        let user_ticks = file_time_to_u64(&user);
        let total_busy = kernel_ticks + user_ticks;
        let total = total_busy + idle_ticks;

        if total == 0 {
            return 0.0;
        }

        let (prev_idle, prev_total) = if self.has_prev_ticks {
            (self.prev_idle_ticks, self.prev_total_ticks)
        } else {
            (idle_ticks, total)
        };
        self.prev_idle_ticks = idle_ticks;
        self.prev_total_ticks = total;
        self.has_prev_ticks = true;

        let d_idle = idle_ticks.saturating_sub(prev_idle);
        let d_total = total.saturating_sub(prev_total);
        let cpu_pct = if d_total == 0 {
            0.0
        } else {
            (1.0 - (d_idle as f64 / d_total as f64)) as f32
        };

        cpu_pct.clamp(0.0, 1.0)
    }

    fn estimate_cpu_usage_fallback(&self) -> f32 {
        log::warn!("No OS-specific CPU sampling available; returning 0.0");
        0.0
    }

    fn sample_memory(&mut self) {
        #[cfg(target_os = "windows")]
        {
            self.sample_memory_windows();
        }
        #[cfg(not(target_os = "windows"))]
        {
            self.sample_memory_fallback();
        }
    }

    #[cfg(target_os = "windows")]
    fn sample_memory_windows(&mut self) {
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

        let mut mem = MemoryStatusEx {
            dw_length: std::mem::size_of::<MemoryStatusEx>() as u32,
            dw_memory_load: 0,
            ull_total_phys: 0,
            ull_avail_phys: 0,
            ull_total_page_file: 0,
            ull_avail_page_file: 0,
            ull_total_virtual: 0,
            ull_avail_virtual: 0,
            ull_avail_extended_virtual: 0,
        };

        let success = unsafe { GlobalMemoryStatusEx(&mut mem) };
        if success != 0 {
            self.available_memory_mb = mem.ull_avail_phys / (1024 * 1024);
        }
    }

    #[cfg(not(target_os = "windows"))]
    fn sample_memory_fallback(&mut self) {
        self.available_memory_mb = 2048;
    }

    fn sample_disk_io(&mut self, now: Instant, prev_time: Instant) -> (u64, bool) {
        #[cfg(target_os = "windows")]
        {
            self.sample_disk_io_windows(now, prev_time)
        }
        #[cfg(not(target_os = "windows"))]
        {
            (0, false)
        }
    }

    #[cfg(target_os = "windows")]
    fn sample_disk_io_windows(&mut self, now: Instant, prev_time: Instant) -> (u64, bool) {
        #[repr(C)]
        struct IoCounters {
            read_operation_count: u64,
            write_operation_count: u64,
            other_operation_count: u64,
            read_transfer_count: u64,
            write_transfer_count: u64,
            other_transfer_count: u64,
        }

        extern "system" {
            fn GetCurrentProcess() -> *mut std::ffi::c_void;
            fn GetProcessIoCounters(
                h_process: *mut std::ffi::c_void,
                lp_io_counters: *mut IoCounters,
            ) -> i32;
        }

        let mut counters = IoCounters {
            read_operation_count: 0,
            write_operation_count: 0,
            other_operation_count: 0,
            read_transfer_count: 0,
            write_transfer_count: 0,
            other_transfer_count: 0,
        };

        let success = unsafe {
            let h = GetCurrentProcess();
            GetProcessIoCounters(h, &mut counters)
        };

        if success == 0 {
            return (0, false);
        }

        let current_bytes = counters.write_transfer_count;
        let prev_bytes = self.prev_disk_bytes_written;
        self.prev_disk_bytes_written = current_bytes;

        if prev_bytes == 0 || current_bytes < prev_bytes {
            return (0, current_bytes > 0);
        }

        let delta_bytes = current_bytes - prev_bytes;
        let delta_secs = now.duration_since(prev_time).as_secs_f64();
        if delta_secs <= 0.0 {
            return (0, delta_bytes > 0);
        }

        let mbps = (delta_bytes as f64 / (1024.0 * 1024.0) / delta_secs) as u64;
        (mbps, delta_bytes > 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_detects_cpu_count() {
        let m = ResourceMonitor::new();
        assert!(m.cpu_count >= 1);
    }

    #[test]
    fn snapshot_default() {
        let s = ResourceSnapshot::default();
        assert!(s.cpu_count >= 1);
        assert_eq!(s.cpu_usage_pct, 0.0);
    }

    #[test]
    fn max_safe_connections_scales_with_memory() {
        let mut m = ResourceMonitor::new();
        m.available_memory_mb = 2048;
        m.cpu_count = 8;
        let max = m.max_safe_connections();
        assert!((4..=32).contains(&max));

        m.available_memory_mb = 256;
        let low_mem = m.max_safe_connections();
        assert!(low_mem <= max);
    }

    #[test]
    fn max_safe_connections_clamps() {
        let mut m = ResourceMonitor::new();
        m.cpu_count = 1;
        m.available_memory_mb = 256;
        assert!(m.max_safe_connections() >= 2);

        m.cpu_count = 64;
        m.available_memory_mb = 8192;
        assert!(m.max_safe_connections() <= 32);
    }

    #[test]
    fn disk_bottleneck_below_threshold() {
        let mut m = ResourceMonitor::new();
        m.snapshot.disk_write_mbps = 5;
        assert!(m.disk_bottleneck());
        m.snapshot.disk_write_mbps = 100;
        assert!(!m.disk_bottleneck());
    }

    #[test]
    fn cpu_saturated_at_high_usage() {
        let mut m = ResourceMonitor::new();
        m.snapshot.cpu_usage_pct = 0.9;
        assert!(m.cpu_saturated());
        m.snapshot.cpu_usage_pct = 0.5;
        assert!(!m.cpu_saturated());
    }

    #[test]
    fn disk_write_budget_divides_evenly() {
        let mut m = ResourceMonitor::new();
        m.snapshot.disk_write_mbps = 100;
        let budget = m.disk_write_budget(4);
        assert_eq!(budget, 25 * 1024 * 1024);
    }

    #[test]
    fn disk_write_budget_zero_when_no_disk() {
        let m = ResourceMonitor::new();
        assert_eq!(m.disk_write_budget(4), 0);
    }

    #[test]
    fn sample_updates_snapshot() {
        let mut m = ResourceMonitor::new();
        m.last_sample = Instant::now() - Duration::from_secs(10);
        let snap = m.sample();
        assert!(snap.cpu_count >= 1);
    }

    #[test]
    fn snapshot_clone_returns_copy() {
        let m = ResourceMonitor::new();
        let mut snap = m.snapshot_clone();
        let original = snap.disk_write_mbps;
        snap.disk_write_mbps = 999;
        assert_eq!(snap.disk_write_mbps, 999);
        let snap2 = m.snapshot_clone();
        assert_eq!(snap2.disk_write_mbps, original);
        assert_ne!(snap2.disk_write_mbps, 999);
    }
}
