use std::{fs::File, sync::OnceLock};
use tracing::Level;
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::fmt;

static TRACER: OnceLock<()> = OnceLock::new();
static LOG_GUARD: OnceLock<WorkerGuard> = OnceLock::new();

pub fn setup_logger(log_file_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    TRACER.get_or_init(|| {
        let file = File::create(format!("{}/kubectl.log", log_file_path))
            .expect("Failed to create log file");
        let (non_blocking_writer, guard) = tracing_appender::non_blocking(file);

        let subscriber = fmt::Subscriber::builder()
            .with_line_number(true)
            .with_max_level(Level::INFO)
            .with_writer(non_blocking_writer)
            .finish();

        LOG_GUARD.set(guard).ok();
        tracing::subscriber::set_global_default(subscriber).expect("Failed to set global default");
    });

    Ok(())
}
