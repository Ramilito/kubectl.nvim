use opentelemetry_semantic_conventions::{
    resource::{SERVICE_NAME, SERVICE_VERSION},
    SCHEMA_URL,
};
use std::{
    fs::File,
    sync::{mpsc, OnceLock},
};
use tracing::{info, level_filters::LevelFilter};

use opentelemetry::{trace::TracerProvider, KeyValue};
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{
    trace::{Sampler, SdkTracerProvider},
    Resource,
};
use tracing_appender::non_blocking::WorkerGuard;
use tracing_opentelemetry::OpenTelemetryLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, Layer};

static SUBSCRIBER_SET:    OnceLock<()>              = OnceLock::new();
static LOG_GUARD:         OnceLock<WorkerGuard>     = OnceLock::new();
static TRACER_PROVIDER:   OnceLock<SdkTracerProvider> = OnceLock::new();
static WORKER_HANDLE:     OnceLock<std::thread::JoinHandle<()>> = OnceLock::new();

/// Common OTEL resource descriptor.
fn resource() -> Resource {
    Resource::builder()
        .with_schema_url(
            [
                KeyValue::new(SERVICE_NAME, "kubectl.nvim"),
                KeyValue::new(SERVICE_VERSION, "2.0.0"),
            ],
            SCHEMA_URL,
        )
        .build()
}

/// Spawn a Tokio runtime, create the OTLP exporter, and hand the provider back
/// to the main thread.
fn init_tracer_provider(ep: &str) -> SdkTracerProvider {
    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_tonic()
        .with_endpoint(ep)
        .build()
        .unwrap();

    SdkTracerProvider::builder()
        .with_sampler(Sampler::ParentBased(Box::new(Sampler::TraceIdRatioBased(
            1.0,
        ))))
        .with_resource(resource())
        .with_batch_exporter(exporter)
        .build()
}

/// Public entry point called by kubectl-core.
pub fn setup_logger(
    log_file_path: &str,
    endpoint: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync + 'static>> {
    // ---- 1.  start background worker that owns the provider ----
    let (tx, rx) = mpsc::sync_channel(1);
    let endpoint_owned = endpoint.to_owned();

    let handle = std::thread::Builder::new()
        .name("otel-worker".into())
        .spawn(move || {
            let rt = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .worker_threads(1)
                .build()
                .expect("Tokio runtime");

            rt.block_on(async move {
                let provider = init_tracer_provider(&endpoint_owned);
                tx.send(provider).ok();           // hand provider back
                std::future::pending::<()>().await;
            });
        })?;

    // receive provider
    let provider = rx.recv()?;
    TRACER_PROVIDER.set(provider.clone()).ok();
    WORKER_HANDLE.set(handle).ok();

    // ---- 2. file layer (non-blocking) ----
    let (file_layer, guard) = {
        let file = File::create(format!("{}/kubectl.log", log_file_path))?;
        let (writer, g) = tracing_appender::non_blocking(file);
        (
            tracing_subscriber::fmt::layer()
                .with_line_number(true)
                .with_writer(writer)
                .with_filter(LevelFilter::INFO),
            g,
        )
    };
    LOG_GUARD.set(guard).ok();

    // ---- 3. OTLP layer ----
    let otel_layer = OpenTelemetryLayer::new(provider.tracer("kubectl.nvim"));

    // ---- 4. install subscriber (set only once) ----
    SUBSCRIBER_SET.get_or_init(|| {
        tracing_subscriber::registry()
            .with(LevelFilter::TRACE)
            .with(file_layer)
            .with(otel_layer)
            .try_init()
            .ok();
    });

    Ok(())
}
