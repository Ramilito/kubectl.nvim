use opentelemetry_semantic_conventions::{
    resource::{SERVICE_NAME, SERVICE_VERSION},
    SCHEMA_URL,
};
use std::{fs::File, sync::OnceLock};
use tokio::runtime::Runtime;
use tracing::{info, level_filters::LevelFilter, Level};

use opentelemetry::{trace::TracerProvider, KeyValue};
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{trace::SdkTracerProvider, Resource};
use tracing_appender::non_blocking::WorkerGuard;
use tracing_opentelemetry::OpenTelemetryLayer;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, Layer};

use crate::RUNTIME;

static SUBSCRIBER_SET: OnceLock<()> = OnceLock::new();
static OTEL_GUARD: OnceLock<SdkTracerProvider> = OnceLock::new();
static LOG_GUARD: OnceLock<WorkerGuard> = OnceLock::new();

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

fn init_tracer_provider(ep: &str) -> SdkTracerProvider {
    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_tonic()
        .with_endpoint(ep)
        .build()
        .unwrap();

    SdkTracerProvider::builder()
        // .with_sampler(Sampler::ParentBased(Box::new(Sampler::TraceIdRatioBased(
        //     1.0,
        // ))))
        .with_resource(resource())
        .with_batch_exporter(exporter)
        .build()
}

pub fn init(
    _service_name: &str,
    log_dir: &str,
    collector_ep: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync + 'static>> {
    // let rt = RUNTIME.get_or_init(|| Runtime::new().expect("create Tokio runtime"));
    // rt.block_on(async {
        let file = File::create(format!("{}/kubectl.log", log_dir)).unwrap();
        let (file_writer, guard) = tracing_appender::non_blocking(file);
        LOG_GUARD.set(guard).ok();

        let fmt_layer = fmt::Layer::default()
            .with_line_number(true)
            .with_writer(file_writer)
            .with_filter(LevelFilter::from_level(Level::INFO));

        let tracer_provider = init_tracer_provider(collector_ep);
        let tracer = tracer_provider.tracer("tracing-otel-subscriber");

        SUBSCRIBER_SET.get_or_init(|| {
            tracing_subscriber::registry()
                .with(tracing_subscriber::filter::LevelFilter::from_level(
                    Level::TRACE,
                ))
                .with(fmt_layer)
                .with(OpenTelemetryLayer::new(tracer))
                .try_init()
                .ok();
        });

        OTEL_GUARD.set(tracer_provider.clone()).ok();
    // });
    Ok(())
}
