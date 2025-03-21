use mlua::{Lua, Result as LuaResult};
use tokio::runtime::Runtime;
use std::ffi::{c_char, CStr, CString};

use crate::RUNTIME;

#[link(name = "kubedescribe")]
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

pub async fn describe_async(
    _lua: Lua,
    args: (String, String, String, String),
) -> LuaResult<String> {
    let (kind, namespace, name, group) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

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
        let group = CString::new(group).expect("Failed to convert group to CString");
        let version = CString::new("v1").unwrap();
        let resource = CString::new(kind).expect("Failed to convert kind to CString");
        let ns = CString::new(namespace).expect("Failed to convert namespace to CString");
        let name = CString::new(name).expect("Failed to convert name to CString");
        let kubeconfig = CString::new(kubeconfig).expect("Failed to convert kubeconfig to CString");

        unsafe {
            let result_ptr = DescribeResource(
                group.as_ptr(),
                version.as_ptr(),
                resource.as_ptr(),
                ns.as_ptr(),
                name.as_ptr(),
                kubeconfig.as_ptr(),
            );
            if result_ptr.is_null() {
                eprintln!("Error: received null pointer from DescribeResource");
            } else {
                let result_str = CStr::from_ptr(result_ptr).to_string_lossy().into_owned();
                return Ok(result_str.to_string());
            }
        }
        Ok("test".to_string())
    };

    rt.block_on(fut)
}
