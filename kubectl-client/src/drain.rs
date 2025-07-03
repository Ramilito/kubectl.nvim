use k8s_openapi::serde_json;
use libc::free;
use mlua::{Error as LuaError, Lua, Result as LuaResult};
use serde::Deserialize;
use std::{
    ffi::{CStr, CString},
    os::raw::c_char,
};
use tokio::runtime::Runtime;
use tracing::info;

use crate::RUNTIME;

#[link(name = "kubectl_go")]
extern "C" {
    fn DrainNode(
        node_name: *const c_char,
        context_name: *const c_char,
        grace_secs: i32,
        timeout_secs: i32,
        ignore_ds: i32,
        delete_emptydir: i32,
        force: i32,
        dry_run: i32,
    ) -> *mut c_char;
}

#[derive(Deserialize, Debug)]
pub struct CmdDrainArgs {
    pub context: String,
    pub node: String,
    pub grace: String,
    pub timeout: String,
    pub ignore_ds: bool,
    pub delete_emptydir: bool,
    pub force: bool,
    pub dry_run: bool,
}

pub async fn drain_node_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdDrainArgs =
        serde_json::from_str(&json).map_err(|e| LuaError::external(format!("bad json: {e}")))?;

    info!("{:?}", args);
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("create Tokio runtime"));

    let grace: i32 = args.grace.parse().unwrap_or(-1);
    let timeout: i32 = args.timeout.parse().unwrap_or(30);

    let fut = async move {
        let node_c = CString::new(args.node).expect("Failed to convert name to CString");
        let ctx_c = CString::new(args.context).expect("Failed to convert context to CString");

        let res_ptr = unsafe {
            DrainNode(
                node_c.as_ptr(),
                ctx_c.as_ptr(),
                grace as i32,
                timeout as i32,
                args.ignore_ds as i32,
                args.delete_emptydir as i32,
                args.force as i32,
                args.dry_run as i32,
            )
        };

        if res_ptr.is_null() {
            return Err(LuaError::RuntimeError(
                "DrainNode returned null pointer".into(),
            ));
        }

        let out = unsafe { CStr::from_ptr(res_ptr) }
            .to_string_lossy()
            .into_owned();

        unsafe { free(res_ptr.cast()) };
        Ok(out)
    };

    rt.block_on(fut)
}
