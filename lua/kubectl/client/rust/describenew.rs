use mlua::{Lua, Result as LuaResult};
use std::ffi::{c_char, CStr};

use crate::RUNTIME;

#[link(name = "kubedescribe")]
extern "C" {
    fn DescribeResource(
        cGroup: *const c_char,
        cKind: *const c_char,
        cNamespace: *const c_char,
        cName: *const c_char,
        cKubeconfig: *const c_char,
    ) -> *mut c_char;
}

pub async fn describe_async(
    _lua: Lua,
    args: (String, String, String, String, bool),
) -> LuaResult<String> {
    let (kind, namespace, name, group, show_events) = args;

    let rt_guard = RUNTIME.lock().unwrap();
    let rt = rt_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".into()))?;

    let fut = async {
        let kind = kind.to_lowercase();

        let kubeconfig = std::env::var("KUBECONFIG").unwrap_or_else(|_| {
            let home = std::env::var("HOME").expect("HOME not set");
            format!("{}/.kube/config", home)
        });
        unsafe {
            let result_ptr = DescribeResource(
                group.as_ptr() as *const c_char,
                kind.as_ptr() as *const c_char,
                namespace.as_ptr() as *const c_char,
                name.as_ptr() as *const c_char,
                kubeconfig.as_ptr() as *const c_char,
            );
            if result_ptr.is_null() {
                eprintln!("Error: received null pointer from DescribeResource");
            } else {
                let result_str = CStr::from_ptr(result_ptr).to_string_lossy().into_owned();
                println!("Description:\n{}", result_str);
            }
        }

        Ok("test".to_string())
    };

    rt.block_on(fut)
}
