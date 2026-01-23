use std::{fs::File, sync::OnceLock};
use tracing::Level;
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, Layer};

static TRACER: OnceLock<()> = OnceLock::new();
static LOG_GUARD: OnceLock<WorkerGuard> = OnceLock::new();

pub fn setup_logger(log_file_path: &str, _ep: &str) -> Result<(), Box<dyn std::error::Error>> {
    TRACER.get_or_init(|| {
        let file = File::create(format!("{}/kubectl.log", log_file_path))
            .expect("Failed to create log file");
        let (non_blocking_writer, guard) = tracing_appender::non_blocking(file);

        let file_layer = fmt::layer()
            .with_line_number(true)
            .with_writer(non_blocking_writer)
            .with_filter(tracing_subscriber::filter::LevelFilter::from_level(Level::INFO));

        LOG_GUARD.set(guard).ok();

        let registry = tracing_subscriber::registry().with(file_layer);

        #[cfg(feature = "console")]
        let registry = registry.with(console_subscriber::spawn());

        registry.try_init().ok();
    });

    Ok(())
}
