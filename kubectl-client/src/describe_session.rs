use libc::free;
use mlua::{prelude::*, UserData, UserDataMethods};
use sha2::{Digest, Sha256};
use std::ffi::{c_char, CStr, CString};
use std::time::Duration;
use tokio::sync::mpsc;

use crate::streaming::{StreamingSession, TaskHandle};
use crate::structs::CmdDescribeArgs;
use crate::RUNTIME;

#[link(name = "kubectl_go")]
extern "C" {
    fn DescribeResource(
        cGroup: *const c_char,
        cVersion: *const c_char,
        cResource: *const c_char,
        cNamespace: *const c_char,
        cName: *const c_char,
        cContext: *const c_char,
    ) -> *mut c_char;
}

const POLL_INTERVAL: Duration = Duration::from_secs(5);
const MAX_RETRY_INTERVAL: Duration = Duration::from_secs(120);

fn hash_content(s: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(s.as_bytes());
    format!("{:x}", hasher.finalize())
}

/// Call the Go DescribeResource FFI function.
/// Returns the describe output or an error string.
fn call_describe(args: &DescribeArgs) -> Result<String, String> {
    let group = CString::new(args.group.as_str()).map_err(|e| e.to_string())?;
    let version = CString::new(args.version.as_str()).map_err(|e| e.to_string())?;
    let resource = CString::new(args.resource.as_str()).map_err(|e| e.to_string())?;
    let namespace = CString::new(args.namespace.as_str()).map_err(|e| e.to_string())?;
    let name = CString::new(args.name.as_str()).map_err(|e| e.to_string())?;
    let context = CString::new(args.context.as_str()).map_err(|e| e.to_string())?;

    unsafe {
        let result_ptr = DescribeResource(
            group.as_ptr(),
            version.as_ptr(),
            resource.as_ptr(),
            namespace.as_ptr(),
            name.as_ptr(),
            context.as_ptr(),
        );

        if result_ptr.is_null() {
            return Err("DescribeResource returned null pointer".into());
        }

        let result_str = CStr::from_ptr(result_ptr).to_string_lossy().into_owned();
        free(result_ptr.cast());
        Ok(result_str)
    }
}

/// Arguments for describe polling task.
#[derive(Clone)]
struct DescribeArgs {
    group: String,
    version: String,
    resource: String,
    namespace: String,
    name: String,
    context: String,
}

/// A streaming describe session that polls for updates.
pub struct DescribeSession {
    session: StreamingSession<String>,
}

impl DescribeSession {
    pub fn new(args: CmdDescribeArgs) -> LuaResult<Self> {
        let describe_args = DescribeArgs {
            group: args.gvk.g,
            version: args.gvk.v,
            resource: args.gvk.k,
            namespace: args.namespace.unwrap_or_default(),
            name: args.name,
            context: args.context,
        };

        // Do initial describe synchronously to fail fast on errors
        let initial_content = call_describe(&describe_args)
            .map_err(|e| LuaError::RuntimeError(format!("Failed to describe resource: {e}")))?;

        let session = StreamingSession::new();
        let runtime = RUNTIME
            .get()
            .ok_or_else(|| LuaError::runtime("Tokio runtime not initialized"))?;

        // Send initial content
        let _ = session.sender().send(initial_content.clone());

        // Spawn polling task
        spawn_describe_poll_task(
            runtime,
            describe_args,
            session.sender(),
            session.task_handle(),
            hash_content(&initial_content),
        );

        Ok(DescribeSession { session })
    }

    fn read_content(&self) -> LuaResult<Option<String>> {
        self.session
            .try_recv()
            .map_err(|e| LuaError::runtime(e.to_string()))
    }

    fn is_open(&self) -> bool {
        self.session.is_open()
    }

    fn close(&self) {
        self.session.close();
    }
}

impl UserData for DescribeSession {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("read_content", |_, this, ()| this.read_content());
        methods.add_method("open", |_, this, ()| Ok(this.is_open()));
        methods.add_method("close", |_, this, ()| {
            this.close();
            Ok(())
        });
    }
}

/// Spawn an async task that polls for describe updates.
fn spawn_describe_poll_task(
    runtime: &tokio::runtime::Runtime,
    args: DescribeArgs,
    sender: mpsc::UnboundedSender<String>,
    task_handle: TaskHandle,
    initial_hash: String,
) {
    let _guard = task_handle.guard();

    runtime.spawn(async move {
        let _guard = _guard;
        let mut last_hash = initial_hash;
        let mut delay = POLL_INTERVAL;

        loop {
            tokio::time::sleep(delay).await;

            if !task_handle.is_active() {
                break;
            }

            // Call describe (blocking FFI call in async context is fine here
            // since it's a dedicated polling task)
            let result = tokio::task::spawn_blocking({
                let args = args.clone();
                move || call_describe(&args)
            })
            .await;

            match result {
                Ok(Ok(content)) => {
                    // Reset delay on success
                    delay = POLL_INTERVAL;

                    // Check if content changed
                    let new_hash = hash_content(&content);
                    if new_hash != last_hash {
                        last_hash = new_hash;
                        if sender.send(content).is_err() {
                            break; // Channel closed
                        }
                    }
                }
                Ok(Err(_)) | Err(_) => {
                    // Exponential backoff on error
                    delay = (delay * 2).min(MAX_RETRY_INTERVAL);
                }
            }
        }
    });
}

/// Create a new describe session.
/// Called from Lua with a config table.
pub fn describe_session(_lua: &Lua, config: mlua::Table) -> LuaResult<DescribeSession> {
    let gvk_table: mlua::Table = config.get("gvk")?;
    let args = CmdDescribeArgs {
        name: config.get("name")?,
        namespace: config.get("namespace")?,
        context: config.get("context")?,
        gvk: crate::structs::Gvk {
            k: gvk_table.get("k")?,
            v: gvk_table.get("v")?,
            g: gvk_table.get("g")?,
        },
    };

    DescribeSession::new(args)
}
