// lib.rs
use kube::{config::KubeConfigOptions, Client, Config};
use mlua::prelude::*;
use mlua::{Lua, Value};
use std::sync::Mutex;
use tokio::runtime::Runtime;

use crate::cmd::apply::apply_async;
use crate::cmd::edit::edit_async;
use crate::cmd::get::get_async;
use crate::cmd::portforward::{portforward_list, portforward_start, portforward_stop};
use crate::processors::get_processors;

mod cmd;
mod describe;
mod events;
mod processors;
mod resources;
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

async fn get_resources_async(
    _lua: Lua,
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
    resources::get_resources(rt, client, resource, group, version, name, namespace)
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

fn get_store(lua: &Lua, args: (String, Option<String>)) -> LuaResult<Value> {
    let (key, namespace) = args;

    if let Some(json_str) = store::get(&key, namespace) {
        Ok(lua.to_value(&json_str)?)
    } else {
        Err(mlua::Error::RuntimeError("No data for given key".into()))
    }
}

fn get_table(
    lua: &Lua,
    args: (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<Value> {
    let (kind, namespace, sort_by, sort_order, filter) = args;

    let items = store::get(&kind, namespace)
        .ok_or_else(|| mlua::Error::RuntimeError("No data for given key".into()))?;
    let processors = get_processors();
    let processor = processors
        .get(kind.as_str())
        .unwrap_or_else(|| processors.get("default").unwrap());
    let processed = processor.process(&lua, &items, sort_by, sort_order, filter);

    Ok(processed?)
}

async fn get_table_async(
    lua: Lua,
    args: (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    let (kind, namespace, sort_by, sort_order, filter) = args;

    let items = store::get(&kind, namespace)
        .ok_or_else(|| mlua::Error::RuntimeError("No data for given key".into()))?;
    let processors = get_processors();
    let processor = processors
        .get(kind.as_str())
        .unwrap_or_else(|| processors.get("default").unwrap());
    let processed = processor
        .process(&lua, &items, sort_by, sort_order, filter)
        .map_err(|e| mlua::Error::external(e))?;

    let json_str = k8s_openapi::serde_json::to_string(&processed)
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    Ok(json_str)
}

#[mlua::lua_module(skip_memory_check)]
fn kubectl_client(lua: &Lua) -> LuaResult<mlua::Table> {
    let exports = lua.create_table()?;
    exports.set("init_runtime", lua.create_function(init_runtime)?)?;
    exports.set("start_watcher", lua.create_function(start_watcher)?)?;
    exports.set("portforward_start", lua.create_function(portforward_start)?)?;
    exports.set("portforward_list", lua.create_function(portforward_list)?)?;
    exports.set("portforward_stop", lua.create_function(portforward_stop)?)?;
    exports.set("apply_async", lua.create_async_function(apply_async)?)?;
    exports.set("edit_async", lua.create_async_function(edit_async)?)?;
    exports.set(
        "describe_async",
        lua.create_async_function(describe::describe_async)?,
    )?;
    exports.set(
        "log_stream_async",
        lua.create_async_function(processors::pod::log_stream_async)?,
    )?;
    exports.set("get_async", lua.create_async_function(get_async)?)?;
    exports.set(
        "get_resources_async",
        lua.create_async_function(get_resources_async)?,
    )?;
    exports.set("get_store", lua.create_function(get_store)?)?;
    exports.set("get_table", lua.create_function(get_table)?)?;
    exports.set(
        "get_table_async",
        lua.create_async_function(get_table_async)?,
    )?;
    Ok(exports)
}
