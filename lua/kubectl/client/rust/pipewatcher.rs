use mlua::{chunk, Function as LuaFunction, Lua, Result as LuaResult, Table, Value as LuaValue};
use std::{
    io::Write,
    os::unix::io::{IntoRawFd, RawFd},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread::{self, JoinHandle},
};

pub fn pipe_watcher(lua: &Lua, name: Option<String>) -> LuaResult<LuaValue> {
    let exports = lua.create_table()?;
    let state = Arc::new(PipeWatcherState::new());

    {
        let state = state.clone();
        let start_fn = lua.create_function(move |lua, ()| {
            state.start_thread(lua)?;
            Ok(())
        })?;
        exports.set("start", start_fn)?;
    }

    {
        let state = state.clone();
        let stop_fn = lua.create_function(move |_lua, ()| {
            state.stop_thread();
            Ok(())
        })?;
        exports.set("stop", stop_fn)?;
    }

    Ok(LuaValue::Table(exports))
}

struct PipeWatcherState {
    thread_handle: Mutex<Option<JoinHandle<()>>>,
    shutdown: Arc<AtomicBool>,
    /// We store the fd in a `Mutex` to mutate it safely.
    pipe_fd: Mutex<RawFd>,
}

impl PipeWatcherState {
    fn new() -> Self {
        let (pipe_r, _) = os_pipe::pipe().expect("failed to open pipe");
        Self {
            thread_handle: Mutex::new(None),
            shutdown: Arc::new(AtomicBool::new(false)),
            pipe_fd: Mutex::new(pipe_r.into_raw_fd()),
        }
    }

    fn start_thread(&self, lua: &Lua) -> LuaResult<()> {
        // If there's already a thread running, do nothing
        if self.thread_handle.lock().unwrap().is_some() {
            return Ok(());
        }

        // Create new pipe each time we "start" so we can read from it in Neovim
        let (pipe_r, mut pipe_w) = os_pipe::pipe()?;

        // Reset the shutdown flag
        self.shutdown.store(false, Ordering::SeqCst);

        // We'll pass an MPSC channel to receive real data
        let (tx, rx) = std::sync::mpsc::channel::<String>();

        // Spawn worker thread
        let shutdown_flag = self.shutdown.clone();
        let handle = thread::spawn(move || {
            let mut i = 0;
            while !shutdown_flag.load(Ordering::SeqCst) {
                let name = if i % 2 == 0 { "John" } else { "Mary" };
                if tx.send(name.into()).is_err() {
                    break;
                }
                let _ = pipe_w.write_all(&[b'1']);
                i += 1;
                std::thread::sleep(std::time::Duration::from_secs(1));
            }
        });

        // Store the thread handle
        *self.thread_handle.lock().unwrap() = Some(handle);

        // Define Lua callback for reading from the channel
        let recv_fn = lua.create_function(move |lua, ()| {
            if let Ok(name) = rx.try_recv() {
                let print_func: LuaFunction = lua.globals().get("print")?;
                print_func.call(name)?;
            }
            Ok(())
        })?;

        let read_fd = pipe_r.into_raw_fd();

        // Setup Neovim's read callback
        lua.load(chunk! {
            local read_pipe = vim.loop.new_pipe()
            read_pipe:open($read_fd)
            read_pipe:read_start(function(err, chunk)
                assert(not err, err)
                if chunk then
                    for _ = 1,string.len(chunk) do
                        $recv_fn()
                    end
                end
            end)
        })
        .exec()?;

        // Close the old fd and store the new one
        {
            let mut fd_lock = self.pipe_fd.lock().unwrap();
            unsafe {
                libc::close(*fd_lock);
            }
            *fd_lock = read_fd;
        }

        Ok(())
    }

    fn stop_thread(&self) {
        // Signal the thread to shut down
        self.shutdown.store(true, Ordering::SeqCst);

        // Join the thread if it's still alive
        if let Some(handle) = self.thread_handle.lock().unwrap().take() {
            let _ = handle.join();
        }
    }
}

impl Drop for PipeWatcherState {
    fn drop(&mut self) {
        // Stop the thread if it's still running
        self.stop_thread();

        // Close the stored fd
        if let Ok(fd_lock) = self.pipe_fd.lock() {
            unsafe {
                libc::close(*fd_lock);
            }
        }
    }
}
