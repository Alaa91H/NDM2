use axum::response::Json;
use axum::routing::post;
use axum::Router;
use std::time::Instant;

use crate::daemon::state::SharedState;

pub(crate) fn register_routes(router: Router<SharedState>) -> Router<SharedState> {
    router.route("/api/dns/ping-all", post(handle_dns_ping_all))
}

async fn handle_dns_ping_all() -> Json<serde_json::Value> {
    let providers: Vec<(&str, &str)> = vec![
        ("Cloudflare", "1.1.1.1"),
        ("Google", "8.8.8.8"),
        ("OpenDNS", "208.67.222.222"),
        ("Quad9", "9.9.9.9"),
        ("Comodo Secure", "8.26.56.26"),
        ("AdGuard", "94.140.14.14"),
        ("CleanBrowsing", "185.228.168.9"),
    ];

    let mut results = Vec::with_capacity(providers.len());
    for (name, ip) in providers {
        let latency = ping_ip(ip).await;
        results.push(serde_json::json!({
            "name": name,
            "ip": ip,
            "latencyMs": latency,
        }));
    }

    Json(serde_json::json!({ "results": results }))
}

async fn ping_ip(ip: &str) -> Option<f64> {
    let start = Instant::now();

    #[cfg(target_os = "windows")]
    let output = std::process::Command::new("ping")
        .arg("-n")
        .arg("1")
        .arg("-w")
        .arg("2000")
        .arg(ip)
        .output();

    #[cfg(not(target_os = "windows"))]
    let output = std::process::Command::new("ping")
        .arg("-c")
        .arg("1")
        .arg("-W")
        .arg("2")
        .arg(ip)
        .output();

    match output {
        Ok(out) if out.status.success() => {
            let ms = start.elapsed().as_secs_f64() * 1000.0;
            Some((ms * 10.0).round() / 10.0)
        }
        _ => None,
    }
}
