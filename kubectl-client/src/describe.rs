use k8s_openapi::serde_json;
use libc::free;
use mlua::{Lua, Result as LuaResult};
use std::ffi::{c_char, CStr, CString};
use tokio::runtime::Runtime;

use crate::{structs::CmdDescribeArgs, RUNTIME};

#[link(name = "kubectl_go")]
extern "C" {
    fn DescribeResource(
        cGroup: *const c_char,
        cVersion: *const c_char,
        cResource: *const c_char,
        cNamespace: *const c_char,
        cName: *const c_char,
        cKubeconfig: *const c_char,
    ) -> *mut c_char;
}

pub async fn describe_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdDescribeArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let group = CString::new(args.gvk.g).expect("Failed to convert group to CString");
    let name = CString::new(args.name).expect("Failed to convert name to CString");

    let fut = async {
        let group = CString::new(group).expect("Failed to convert group to CString");
        let version = CString::new(args.gvk.v).unwrap();
        let resource = CString::new(args.gvk.k).expect("Failed to convert kind to CString");
        let name = CString::new(name).expect("Failed to convert name to CString");
        let context = CString::new(args.context).expect("Failed to convert kubeconfig to CString");

        let ns_cstring = args
            .namespace
            .map(|ns| CString::new(ns).expect("Failed to convert namespace to CString"));
        let ns_ptr = ns_cstring
            .as_ref()
            .map_or(std::ptr::null(), |ns| ns.as_ptr());

        unsafe {
            let result_ptr = DescribeResource(
                group.as_ptr(),
                version.as_ptr(),
                resource.as_ptr(),
                ns_ptr,
                name.as_ptr(),
                context.as_ptr(),
            );
            if result_ptr.is_null() {
                eprintln!("Error: received null pointer from DescribeResource");
            } else {
                let result_str = CStr::from_ptr(result_ptr).to_string_lossy().into_owned();

                free(result_ptr.cast());
                return Ok(result_str.to_string());
            }
        }
        Ok("".to_string())
    };

    rt.block_on(fut)
}
