use axum::extract::Query;
use axum::http::StatusCode;
use axum::response::Json;
use axum::routing::get;
use axum::Router;
use log::LevelFilter;
use serde::Deserialize;

use crate::daemon::state::SharedState;

pub fn register_routes(router: Router<SharedState>) -> Router<SharedState> {
    router.route("/api/logs", get(handle_recent_logs)).route(
        "/api/logs/level",
        get(handle_get_log_level).patch(handle_set_log_level),
    )
}

#[derive(Debug, Deserialize)]
struct RecentLogsQuery {
    /// Maximum number of entries to return (clamped to the ring buffer size).
    limit: Option<usize>,
    /// Only return entries at or above this level (trace|debug|info|warn|error).
    level: Option<String>,
}

async fn handle_recent_logs(
    Query(params): Query<RecentLogsQuery>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let min_level = match params.level.as_deref() {
        None => None,
        Some(raw) => match raw.trim().to_ascii_lowercase().as_str() {
            "trace" => Some(LevelFilter::Trace),
            "debug" => Some(LevelFilter::Debug),
            "info" => Some(LevelFilter::Info),
            "warn" => Some(LevelFilter::Warn),
            "error" => Some(LevelFilter::Error),
            other => {
                return Err((
                    StatusCode::BAD_REQUEST,
                    Json(serde_json::json!({"error": format!("invalid level filter: {other}")})),
                ));
            }
        },
    };
    let limit = params
        .limit
        .unwrap_or(500)
        .min(crate::logging::LOG_BUFFER_CAPACITY);
    let entries = crate::logging::recent(limit, min_level);
    Ok(Json(serde_json::json!({
        "entries": entries,
        "level": crate::logging::current_level().to_string().to_ascii_lowercase(),
        "logDir": crate::logging::log_dir(),
    })))
}

async fn handle_get_log_level() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "level": crate::logging::current_level().to_string().to_ascii_lowercase(),
    }))
}

#[derive(Debug, Deserialize)]
struct SetLogLevelBody {
    level: String,
}

async fn handle_set_log_level(
    Json(body): Json<SetLogLevelBody>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let level = match body.level.trim().to_ascii_lowercase().as_str() {
        "off" => LevelFilter::Off,
        "error" => LevelFilter::Error,
        "warn" => LevelFilter::Warn,
        "info" => LevelFilter::Info,
        "debug" => LevelFilter::Debug,
        "trace" => LevelFilter::Trace,
        other => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("invalid level: {other}")})),
            ));
        }
    };
    crate::logging::set_level(level).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": e})),
        )
    })?;
    Ok(Json(serde_json::json!({
        "level": level.to_string().to_ascii_lowercase(),
    })))
}
