// lib.rs
use kube::api::DynamicObject;
use kube::{api::GroupVersionKind, config::KubeConfigOptions, Client, Config};
use mlua::prelude::*;
use mlua::Lua;
use std::sync::{Mutex, OnceLock};
use store::get_store_map;
use tokio::runtime::Runtime;
use tracing::error;

use crate::cmd::apply::apply_async;
use crate::cmd::edit::edit_async;
use crate::cmd::exec;
use crate::cmd::get::{
    get_api_resources_async, get_config, get_config_async, get_raw_async, get_resource_async,
    get_resources_async, get_server_raw_async, get_single_async,
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
        use futures::future::join;

        let store_future = async {
            let store_map = get_store_map();
            let mut map_writer = store_map.write().await;
            map_writer.clear();
        };

        let config_future = async {
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
        };

        let ((), client_result) = join(store_future, config_future).await;
        client_result
    })?;

    let mut client_guard = CLIENT_INSTANCE.lock().unwrap();
    *client_guard = Some(new_client);

    Ok(true)
}

async fn get_minified_config_async(_lua: Lua, args: Option<String>) -> LuaResult<String> {
    let context_name = args;
    let full = kube::config::Kubeconfig::read().map_err(LuaError::external)?;

    let current_ctx = match context_name {
        Some(user_ctx) => user_ctx,
        None => full
            .current_context
            .clone()
            .ok_or_else(|| LuaError::external("no current-context in kubeconfig"))?,
    };

    let named_ctx: &kube::config::NamedContext = full
        .contexts
        .iter()
        .find(|c| c.name == current_ctx)
        .ok_or_else(|| LuaError::external(format!("context '{}' not found", current_ctx)))?;

    let ctx_obj = named_ctx
        .context
        .as_ref()
        .ok_or_else(|| LuaError::external(format!("context '{}' is empty", current_ctx)))?;

    let cluster = full
        .clusters
        .iter()
        .find(|c| c.name == ctx_obj.cluster)
        .ok_or_else(|| LuaError::external(format!("cluster '{}' not found", &ctx_obj.cluster)))?;

    let user_name = ctx_obj
        .user
        .as_ref()
        .ok_or_else(|| LuaError::external(format!("no user set for context '{}'", current_ctx)))?;
    let user = full
        .auth_infos
        .iter()
        .find(|u| &u.name == user_name)
        .ok_or_else(|| LuaError::external(format!("user '{}' not found", user_name)))?;

    let slim = kube::config::Kubeconfig {
        clusters: vec![cluster.clone()],
        contexts: vec![named_ctx.clone()],
        auth_infos: vec![user.clone()],
        current_context: Some(current_ctx),
        preferences: Default::default(),
        extensions: Default::default(),
        ..Default::default()
    };
    k8s_openapi::serde_json::to_string_pretty(&slim).map_err(LuaError::external)
}

async fn get_all_async(
    _lua: Lua,
    args: (String, Option<String>, Option<String>, Option<String>),
) -> LuaResult<String> {
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
        let cached = (store::get(&kind, namespace.clone()).await).unwrap_or_default();
        let resources: Vec<DynamicObject> = if cached.is_empty() {
            get_resources_async(&client, kind, group, version, namespace)
                .await
                .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?
        } else {
            cached
        };
        let json_str = k8s_openapi::serde_json::to_string(&resources)
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

async fn fetch_all_async(
    _lua: Lua,
    args: (String, Option<String>, Option<String>, Option<String>),
) -> LuaResult<String> {
    let (kind, group, version, namespace) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        let mut items = get_resources_async(client, kind, group, version, namespace)
            .await
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        for item in &mut items {
            crate::utils::strip_managed_fields(item);
        }
        let json_str = k8s_openapi::serde_json::to_string(&items)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        Ok(json_str)
    };

    rt.block_on(fut)
}

async fn fetch_async(
    _lua: Lua,
    args: (
        String,
        Option<String>,
        Option<String>,
        String,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    let (kind, group, version, name, namespace, output) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        get_resource_async(client, kind, group, version, name, namespace, output).await
    };

    rt.block_on(fut)
}

async fn get_table_async(
    lua: Lua,
    args: (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    let (kind, group, version, namespace, sort_by, sort_order, filter) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
        .clone();

    let fut = async move {
        let cached = (store::get(&kind, namespace.clone()).await).unwrap_or_default();
        let resources: Vec<DynamicObject> = if cached.is_empty() {
            get_resources_async(&client, kind.clone(), group, version, namespace)
                .await
                .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?
        } else {
            cached
        };

        let processors = get_processors();
        let processor = processors
            .get(kind.to_lowercase().as_str())
            .unwrap_or_else(|| processors.get("default").unwrap());
        let processed = processor
            .process(&lua, &resources, sort_by, sort_order, filter)
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
    exports.set(
        "get_single_async",
        lua.create_async_function(get_single_async)?,
    )?;
    exports.set("fetch_async", lua.create_async_function(fetch_async)?)?;
    exports.set(
        "fetch_all_async",
        lua.create_async_function(fetch_all_async)?,
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
    exports.set(
        "get_minified_config_async",
        lua.create_async_function(get_minified_config_async)?,
    )?;
    exports.set("restart_async", lua.create_async_function(restart_async)?)?;
    exports.set(
        "deployment_set_images",
        lua.create_function(dao::deployment::set_images)?,
    )?;

    Ok(exports)
}
