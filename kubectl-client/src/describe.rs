use k8s_openapi::serde_json;
use libc::free;
use mlua::{Error as LuaError, Lua, Result as LuaResult};
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

fn make_cstring(s: String, field: &str) -> LuaResult<CString> {
    CString::new(s).map_err(|e| LuaError::RuntimeError(format!("invalid {field} (null byte): {e}")))
}

pub async fn describe_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdDescribeArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let group = make_cstring(args.gvk.g, "group")?;
    let version = make_cstring(args.gvk.v, "version")?;
    let resource = make_cstring(args.gvk.k, "resource")?;
    let name = make_cstring(args.name, "name")?;
    let context = make_cstring(args.context, "context")?;
    let ns_cstring = args.namespace.map(|ns| make_cstring(ns, "namespace")).transpose()?;

    let fut = async move {
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
                return Err(LuaError::RuntimeError(
                    "DescribeResource returned null pointer".into(),
                ));
            }

            let result_str = CStr::from_ptr(result_ptr).to_string_lossy().into_owned();
            free(result_ptr.cast());
            Ok(result_str)
        }
    };

    rt.block_on(fut)
}
