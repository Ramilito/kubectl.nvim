// lib.rs
use kube::config::KubeConfigOptions;
use kube::{Client, Config};
use mlua::prelude::*;
use std::sync::Mutex;
use tokio::runtime::Runtime;

mod resource;
mod store;
mod utils;
mod watcher;

static RUNTIME: Mutex<Option<Runtime>> = Mutex::new(None);
static CLIENT_INSTANCE: Mutex<Option<Client>> = Mutex::new(None);

fn init_runtime(_lua: &Lua, context_name: Option<String>) -> LuaResult<bool> {
    let mut rt_guard = RUNTIME.lock().unwrap();
    let mut client_guard = CLIENT_INSTANCE.lock().unwrap();
    let new_rt = Runtime::new().expect("Failed to create Tokio runtime");
    let new_client = new_rt.block_on(async {
        let options = KubeConfigOptions {
            context: context_name.clone(),
            cluster: None,
            user: None,
        };
        let config = Config::from_kubeconfig(&options)
            .await
            .expect("Failed to load kubeconfig");
        Client::try_from(config).expect("Failed to create Kubernetes client")
    });
    *rt_guard = Some(new_rt);
    *client_guard = Some(new_client);
    Ok(true)
}

fn get_resource(
    _lua: &Lua,
    args: (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    let (resource, group, version, name, namespace) = args;
    let rt_guard = RUNTIME.lock().unwrap();
    let client_guard = CLIENT_INSTANCE.lock().unwrap();
    let rt = rt_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;
    resource::get_resource(rt, client, resource, group, version, name, namespace)
}

fn start_watcher(
    _lua: &Lua,
    args: (String, Option<String>, Option<String>, Option<String>),
) -> LuaResult<()> {
    let (resource, group, version, namespace) = args;
    let rt_guard = RUNTIME.lock().unwrap();
    let client_guard = CLIENT_INSTANCE.lock().unwrap();
    let rt = rt_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;
    watcher::start(rt, client, resource, group, version, namespace)
}

fn get_store(_lua: &Lua, args: (String, Option<String>)) -> LuaResult<String> {
    let (key, namespace) = args;
    if let Some(json_str) = store::to_json(&key, namespace) {
        Ok(json_str)
    } else {
        Err(mlua::Error::RuntimeError("No data for given key".into()))
    }
}

#[mlua::lua_module(skip_memory_check)]
fn kubectl_client(lua: &Lua) -> LuaResult<mlua::Table> {
    let exports = lua.create_table()?;
    exports.set("init_runtime", lua.create_function(init_runtime)?)?;
    exports.set("get_resource", lua.create_function(get_resource)?)?;
    exports.set("start_watcher", lua.create_function(start_watcher)?)?;
    exports.set("get_store", lua.create_function(get_store)?)?;
    Ok(exports)
}
