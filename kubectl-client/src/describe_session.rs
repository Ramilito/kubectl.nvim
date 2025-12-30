use libc::free;
use mlua::{prelude::*, UserData, UserDataMethods};
use std::ffi::{c_char, c_int, c_ulonglong, CStr, CString};

use crate::structs::CmdDescribeArgs;

#[link(name = "kubectl_go")]
extern "C" {
    fn CreateDescribeSession(
        cGroup: *const c_char,
        cVersion: *const c_char,
        cResource: *const c_char,
        cNamespace: *const c_char,
        cName: *const c_char,
        cContext: *const c_char,
    ) -> c_ulonglong;

    fn DescribeSessionRead(sessionID: c_ulonglong) -> *mut c_char;

    fn DescribeSessionIsOpen(sessionID: c_ulonglong) -> c_int;

    fn DescribeSessionClose(sessionID: c_ulonglong);
}

fn make_cstring(s: String, field: &str) -> LuaResult<CString> {
    CString::new(s).map_err(|e| LuaError::RuntimeError(format!("invalid {field} (null byte): {e}")))
}

/// A streaming describe session that polls for updates.
/// Wraps Go DescribeSession via FFI.
pub struct DescribeSession {
    session_id: u64,
}

impl DescribeSession {
    pub fn new(args: CmdDescribeArgs) -> LuaResult<Self> {
        let group = make_cstring(args.gvk.g, "group")?;
        let version = make_cstring(args.gvk.v, "version")?;
        let resource = make_cstring(args.gvk.k, "resource")?;
        let name = make_cstring(args.name, "name")?;
        let context = make_cstring(args.context, "context")?;
        let namespace = make_cstring(args.namespace.unwrap_or_default(), "namespace")?;

        let session_id = unsafe {
            CreateDescribeSession(
                group.as_ptr(),
                version.as_ptr(),
                resource.as_ptr(),
                namespace.as_ptr(),
                name.as_ptr(),
                context.as_ptr(),
            )
        };

        if session_id == 0 {
            return Err(LuaError::RuntimeError(
                "Failed to create describe session".into(),
            ));
        }

        Ok(DescribeSession { session_id })
    }

    fn read_content(&self) -> LuaResult<Option<String>> {
        unsafe {
            let result_ptr = DescribeSessionRead(self.session_id);
            if result_ptr.is_null() {
                return Ok(None);
            }

            let result_str = CStr::from_ptr(result_ptr).to_string_lossy().into_owned();
            free(result_ptr.cast());
            Ok(Some(result_str))
        }
    }

    fn is_open(&self) -> bool {
        unsafe { DescribeSessionIsOpen(self.session_id) != 0 }
    }

    fn close(&self) {
        unsafe {
            DescribeSessionClose(self.session_id);
        }
    }
}

impl Drop for DescribeSession {
    fn drop(&mut self) {
        self.close();
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

/// Create a new describe session.
/// Called from Lua with a config table.
pub fn describe_session(_lua: &Lua, config: mlua::Table) -> LuaResult<DescribeSession> {
    let args = CmdDescribeArgs {
        name: config.get("name")?,
        namespace: config.get("namespace")?,
        context: config.get("context")?,
        gvk: crate::structs::Gvk {
            k: config.get::<mlua::Table>("gvk")?.get("k")?,
            v: config.get::<mlua::Table>("gvk")?.get("v")?,
            g: config.get::<mlua::Table>("gvk")?.get("g")?,
        },
    };

    DescribeSession::new(args)
}
