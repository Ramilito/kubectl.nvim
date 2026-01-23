use http::Uri;
use kube::Client;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::OnceLock;
use std::time::Duration;
use tokio::task::JoinHandle;
use tokio::time;
use tokio_util::sync::CancellationToken;

static HEALTH_OK: AtomicBool = AtomicBool::new(false);
static HEALTH_LAST_OK: AtomicU64 = AtomicU64::new(0);
static HEALTH_COLLECTOR: OnceLock<HealthCollector> = OnceLock::new();

const POLL_INTERVAL: Duration = Duration::from_secs(2);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(2);

struct HealthCollector {
    _handle: JoinHandle<()>,
    cancel: CancellationToken,
}

pub fn spawn_health_collector(client: Client) {
    HEALTH_COLLECTOR.get_or_init(|| {
        let cancel = CancellationToken::new();
        let child = cancel.clone();

        let handle = tokio::spawn(async move {
            let mut tick = time::interval(POLL_INTERVAL);

            loop {
                tokio::select! {
                    _ = child.cancelled() => break,
                    _ = tick.tick() => {
                        let ok = check_livez(&client).await;
                        HEALTH_OK.store(ok, Ordering::Relaxed);
                        if ok {
                            let now = std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .map(|d| d.as_secs())
                                .unwrap_or(0);
                            HEALTH_LAST_OK.store(now, Ordering::Relaxed);
                        }
                    }
                }
            }
        });

        HealthCollector {
            _handle: handle,
            cancel,
        }
    });
}

pub fn shutdown_health_collector() {
    if let Some(collector) = HEALTH_COLLECTOR.get() {
        collector.cancel.cancel();
    }
}

async fn check_livez(client: &Client) -> bool {
    let url: Uri = "/livez".parse().expect("valid uri");
    let req = match http::Request::get(url).body(Vec::new()) {
        Ok(r) => r,
        Err(_) => return false,
    };

    match tokio::time::timeout(REQUEST_TIMEOUT, client.request_text(req)).await {
        Ok(Ok(text)) => text == "ok",
        _ => false,
    }
}

/// Get cached health status (sync, no block_on)
pub fn get_health_status() -> (bool, u64) {
    (
        HEALTH_OK.load(Ordering::Relaxed),
        HEALTH_LAST_OK.load(Ordering::Relaxed),
    )
}
