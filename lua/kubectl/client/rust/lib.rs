// lib.rs
use kube::{config::KubeConfigOptions, Client, Config};
use mlua::prelude::*;
use mlua::{Lua, Value};
use std::sync::{Mutex, OnceLock};
use tokio::runtime::Runtime;

use crate::cmd::apply::apply_async;
use crate::cmd::edit::edit_async;
use crate::cmd::exec;
use crate::cmd::get::{
    get_async, get_config, get_config_async, get_raw_async, get_resource_async,
    get_server_raw_async,
};
use crate::cmd::portforward::{portforward_list, portforward_start, portforward_stop};
use crate::cmd::restart::restart_async;
use crate::cmd::scale::scale_async;
use crate::errors::LogErrorExt;
use crate::processors::get_processors;

mod cmd;
mod dao;
mod describe;
mod errors;
mod events;
mod processors;
mod resources;
mod store;
mod utils;
mod watcher;

static LOG_PATH: OnceLock<Option<String>> = OnceLock::new();
static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static CLIENT_INSTANCE: Mutex<Option<Client>> = Mutex::new(None);

fn init_runtime(lua: &Lua, context_name: Option<String>) -> LuaResult<bool> {
    LOG_PATH.get_or_init(|| {
        Some(
            lua.load("return vim.fn.stdpath('log')")
                .eval()
                .unwrap_or_else(|_| "default_log".to_string()),
        )
    });

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let new_client = rt.block_on(async {
        let options = KubeConfigOptions {
            context: context_name.clone(),
            cluster: None,
            user: None,
        };
        let config = Config::from_kubeconfig(&options)
            .await
            .map_err(LuaError::external)?;
        let client = Client::try_from(config).map_err(LuaError::external)?;
        Ok::<Client, mlua::Error>(client)
    })?;

    let mut client_guard = CLIENT_INSTANCE.lock().unwrap();
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
    let (kind, group, version, name, namespace) = args;
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE.lock().unwrap();
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    resources::get_resources(rt, client, kind, group, version, name, namespace)
}

async fn start_watcher_async(
    _lua: Lua,
    args: (String, Option<String>, Option<String>, Option<String>),
) -> LuaResult<()> {
    let (resource, group, version, namespace) = args;
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE.lock().unwrap();
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
    processor.process(lua, &items, sort_by, sort_order, filter)
}

pub async fn get_fallback_table_async(
    lua: Lua,
    args: (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    let (name, namespace, sort_by, sort_order, filter) = args;

    let processors = get_processors();
    let processor = processors
        .get("fallback")
        .unwrap_or_else(|| processors.get("default").unwrap());
    let processed = processor
        .process_fallback(&lua, name, namespace, sort_by, sort_order, filter)
        .map_err(mlua::Error::external)?;

    let json_str = k8s_openapi::serde_json::to_string(&processed)
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    Ok(json_str)
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
        .map_err(mlua::Error::external)?;

    let json_str = k8s_openapi::serde_json::to_string(&processed)
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    Ok(json_str)
}

#[mlua::lua_module(skip_memory_check)]
fn kubectl_client(lua: &Lua) -> LuaResult<mlua::Table> {
    let exports = lua.create_table()?;
    exports.set("init_runtime", lua.create_function(init_runtime)?)?;
    exports.set(
        "start_watcher_async",
        lua.create_async_function(start_watcher_async)?,
    )?;
    exports.set("portforward_start", lua.create_function(portforward_start)?)?;
    exports.set("portforward_list", lua.create_function(portforward_list)?)?;
    exports.set("portforward_stop", lua.create_function(portforward_stop)?)?;
    exports.set("exec", lua.create_function(exec::exec)?)?;
    exports.set("apply_async", lua.create_async_function(apply_async)?)?;
    exports.set(
        "edit_async",
        lua.create_async_function(
            |lua, args| async move { edit_async(lua, args).await.log_err() },
        )?,
    )?;
    exports.set(
        "describe_async",
        lua.create_async_function(describe::describe_async)?,
    )?;
    exports.set(
        "log_stream_async",
        lua.create_async_function(processors::pod::log_stream_async)?,
    )?;
    exports.set("get_raw_async", lua.create_async_function(get_raw_async)?)?;
    exports.set(
        "get_server_raw_async",
        lua.create_async_function(get_server_raw_async)?,
    )?;
    exports.set("get_config", lua.create_function(get_config)?)?;
    exports.set(
        "get_config_async",
        lua.create_async_function(get_config_async)?,
    )?;
    exports.set("get_async", lua.create_async_function(get_async)?)?;
    exports.set(
        "get_resource_async",
        lua.create_async_function(get_resource_async)?,
    )?;
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
    exports.set(
        "get_fallback_table_async",
        lua.create_async_function(get_fallback_table_async)?,
    )?;

    exports.set("scale_async", lua.create_async_function(scale_async)?)?;

    exports.set("restart_async", lua.create_async_function(restart_async)?)?;

    exports.set("pod_set_images", lua.create_function(dao::pod::set_images)?)?;
    exports.set(
        "deployment_set_images",
        lua.create_function(dao::deployment::set_images)?,
    )?;

    Ok(exports)
}
