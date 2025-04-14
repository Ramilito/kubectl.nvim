// lib.rs
use ::log::error;
use kube::{api::GroupVersionKind, config::KubeConfigOptions, Client, Config};
use mlua::prelude::*;
use mlua::Lua;
use std::sync::{Mutex, OnceLock};
use tokio::runtime::Runtime;

use crate::cmd::apply::apply_async;
use crate::cmd::edit::edit_async;
use crate::cmd::exec;
use crate::cmd::get::{
    get_api_resources_async, get_single_async, get_config, get_config_async, get_raw_async,
    get_resource_async, get_server_raw_async,
};
use crate::cmd::portforward::{portforward_list, portforward_start, portforward_stop};
use crate::cmd::restart::restart_async;
use crate::cmd::scale::scale_async;
use crate::processors::get_processors;

mod cmd;
mod dao;
mod describe;
mod events;
mod log;
mod processors;
mod store;
mod utils;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static CLIENT_INSTANCE: Mutex<Option<Client>> = Mutex::new(None);

fn init_runtime(_lua: &Lua, context_name: Option<String>) -> LuaResult<bool> {
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

async fn get_all_async(_lua: Lua, args: (String, Option<String>)) -> LuaResult<String> {
    let (kind, namespace) = args;
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let fut = async move {
        let result = store::get(&kind, namespace).await?;
        let json_str = k8s_openapi::serde_json::to_string(&result)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        Ok(json_str)
    };
    rt.block_on(fut)
}

async fn start_reflector_async(
    _lua: Lua,
    args: (String, Option<String>, Option<String>, Option<String>),
) -> LuaResult<()> {
    let (kind, group, version, namespace) = args;
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
        .clone();

    let fut = async move {
        let gvk = GroupVersionKind::gvk(&group.unwrap(), &version.unwrap(), &kind);
        let _ = store::init_reflector_for_kind(client.clone(), gvk, namespace).await;
        Ok(())
    };
    rt.block_on(fut)
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
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let fut = async move {
        let items = store::get(&kind, namespace).await?;
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
    };
    rt.block_on(fut)
}

#[mlua::lua_module(skip_memory_check)]
fn kubectl_client(lua: &Lua) -> LuaResult<mlua::Table> {
    let exports = lua.create_table()?;
    exports.set(
        "init_logging",
        lua.create_function(|_, path: String| {
            log::setup_logger(&path).map_err(|e| LuaError::external(format!("{:?}", e)))?;
            Ok(())
        })?,
    )?;
    std::panic::set_hook(Box::new(|panic_info| {
        error!("Panic occurred: {}", panic_info);
    }));

    exports.set("init_runtime", lua.create_function(init_runtime)?)?;
    exports.set(
        "start_reflector_async",
        lua.create_async_function(start_reflector_async)?,
    )?;
    exports.set("portforward_start", lua.create_function(portforward_start)?)?;
    exports.set("portforward_list", lua.create_function(portforward_list)?)?;
    exports.set("portforward_stop", lua.create_function(portforward_stop)?)?;
    exports.set("exec", lua.create_function(exec::exec)?)?;
    exports.set(
        "log_stream_async",
        lua.create_async_function(processors::pod::log_stream_async)?,
    )?;
    exports.set("apply_async", lua.create_async_function(apply_async)?)?;
    exports.set(
        "edit_async",
        lua.create_async_function(|lua, args| async move { edit_async(lua, args).await })?,
    )?;
    exports.set(
        "describe_async",
        lua.create_async_function(describe::describe_async)?,
    )?;
    exports.set("get_raw_async", lua.create_async_function(get_raw_async)?)?;
    exports.set(
        "get_server_raw_async",
        lua.create_async_function(get_server_raw_async)?,
    )?;
    exports.set(
        "get_api_resources_async",
        lua.create_async_function(get_api_resources_async)?,
    )?;
    exports.set("get_config", lua.create_function(get_config)?)?;
    exports.set(
        "get_config_async",
        lua.create_async_function(get_config_async)?,
    )?;
    exports.set("get_single_async", lua.create_async_function(get_single_async)?)?;
    exports.set(
        "get_resource_async",
        lua.create_async_function(get_resource_async)?,
    )?;
    exports.set("get_all_async", lua.create_async_function(get_all_async)?)?;
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
    exports.set(
        "deployment_set_images",
        lua.create_function(dao::deployment::set_images)?,
    )?;

    Ok(exports)
}
