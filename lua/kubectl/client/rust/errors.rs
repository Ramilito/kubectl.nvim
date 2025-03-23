use std::fs::OpenOptions;
use std::io::Write;

use crate::LOG_PATH;

pub trait LogErrorExt<T, E> {
    fn log_err(self) -> Result<T, mlua::Error>;
}

impl<T, E: std::fmt::Display> LogErrorExt<T, E> for Result<T, E> {
    fn log_err(self) -> Result<T, mlua::Error> {
        self.map_err(|e| {
            log_error(&e);
            mlua::Error::RuntimeError(e.to_string())
        })
    }
}

pub fn log_error<E: std::fmt::Display>(err: E) {
    let msg = err.to_string();
    if let Some(log_opt) = LOG_PATH.get() {
        if let Some(ref log_dir) = *log_opt {
            let file_path = format!("{}/kubectl.log", log_dir);
            if let Ok(mut file) = OpenOptions::new()
                .create(true)
                .append(true)
                .open(&file_path)
            {
                let _ = writeln!(file, "{}", msg);
            } else {
                eprintln!("Failed to open log file at {}", file_path);
            }
        } else {
            eprintln!("LOG_PATH is None. Error: {}", msg);
        }
    } else {
        eprintln!("LOG_PATH not set. Error: {}", msg);
    }
}
