use fern::Dispatch;
use log::LevelFilter;
use chrono::Local;

pub fn setup_logger(log_file_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    Dispatch::new()
        .format(|out, message, record| {
            out.finish(format_args!(
                "[{}][{}][{}] {}",
                Local::now().format("%Y-%m-%d %H:%M:%S"),
                record.level(),
                record.target(),
                message
            ))
        })
        .level(LevelFilter::Info)
        .chain(fern::log_file(log_file_path)?)
        .apply()?;

    Ok(())
}
