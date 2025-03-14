use mlua::{Lua, Result as LuaResult};
use std::ffi::{c_char, CStr, CString};

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
        // Convert to lower case or do any other transforms you need.
        let kind = kind.to_lowercase();

        // Determine kubeconfig path.
        // let kubeconfig = std::env::var("KUBECONFIG").unwrap_or_else(|_| {
        //     let home = std::env::var("HOME").expect("HOME not set");
        //     format!("{}/.kube/config", home)
        // });

        let home = std::env::var("HOME").expect("HOME not set");
        let kubeconfig = format!("{}/.kube/config", home);
        // -- Convert all strings to CStrings here --
        let c_group = CString::new(group).expect("Failed to convert group to CString");
        let c_kind = CString::new(kind).expect("Failed to convert kind to CString");
        let c_ns = CString::new(namespace).expect("Failed to convert namespace to CString");
        let c_name = CString::new(name).expect("Failed to convert name to CString");
        let c_kubeconfig =
            CString::new(kubeconfig).expect("Failed to convert kubeconfig to CString");

        // Call the FFI function with proper null-terminated pointers.
        unsafe {
            let result_ptr = DescribeResource(
                c_group.as_ptr(),
                c_kind.as_ptr(),
                c_ns.as_ptr(),
                c_name.as_ptr(),
                c_kubeconfig.as_ptr(),
            );
            if result_ptr.is_null() {
                eprintln!("Error: received null pointer from DescribeResource");
            } else {
                let result_str = CStr::from_ptr(result_ptr).to_string_lossy().into_owned();
                // println!("Description:\n{}", result_str);

                return Ok(result_str.to_string());
            }
        }
        Ok("test".to_string())
    };

    rt.block_on(fut)
}
