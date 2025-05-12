// lib.rs
use k8s_openapi::serde_json;
use kube::api::DynamicObject;
use kube::{api::GroupVersionKind, config::KubeConfigOptions, Client, Config};
use mlua::prelude::*;
use mlua::Lua;
use std::backtrace::Backtrace;
use std::future::Future;
use std::panic;
use std::sync::{Mutex, OnceLock};
use structs::{FetchArgs, GetAllArgs, GetFallbackTableArgs, GetTableArgs, StartReflectorArgs};
use tokio::runtime::Runtime;
use tracing::error;

use crate::cmd::apply::apply_async;
use crate::cmd::config::{
    get_config, get_config_async, get_minified_config_async, get_version_async,
};
use crate::cmd::delete::delete_async;
use crate::cmd::edit::edit_async;
use crate::cmd::exec;
use crate::cmd::get::{
    get_api_resources_async, get_raw_async, get_resource_async, get_resources_async,
    get_server_raw_async, get_single_async,
};
use crate::cmd::portforward::{portforward_list, portforward_start, portforward_stop};
use crate::cmd::restart::restart_async;
use crate::cmd::scale::scale_async;
use crate::processors::processor;
use crate::store::get_store_map;

cfg_if::cfg_if! {
    if #[cfg(feature = "telemetry")] {
        use kubectl_telemetry as logging;
    } else {
        mod log;
        use log as logging;
    }
}

mod cmd;
mod dao;
mod describe;
mod drain;
mod events;
mod filter;
mod processors;
mod sort;
mod store;
mod structs;
mod utils;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static CLIENT_INSTANCE: Mutex<Option<Client>> = Mutex::new(None);

pub fn with_client<F, Fut, R>(f: F) -> LuaResult<R>
where
    F: FnOnce(Client) -> Fut,
    Fut: Future<Output = LuaResult<R>>,
{
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("create Tokio runtime"));

    let client = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("poisoned CLIENT lock".into()))?
        .as_ref()
        .cloned()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialised".into()))?;

    rt.block_on(f(client))
}

#[tracing::instrument]
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

//TODO: Should be combined with get_table_async with a pretty output param
#[tracing::instrument]
async fn get_all_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: GetAllArgs = serde_json::from_str(&json).unwrap();
    with_client(move |client| async move {
        let cached = (store::get(&args.gvk.k, args.namespace.clone()).await).unwrap_or_default();
        let resources: Vec<DynamicObject> = if cached.is_empty() {
            get_resources_async(
                &client,
                args.gvk.k,
                Some(args.gvk.g),
                Some(args.gvk.v),
                args.namespace,
            )
            .await
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?
        } else {
            cached
        };
        let json_str = k8s_openapi::serde_json::to_string(&resources)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        Ok(json_str)
    })
}

#[tracing::instrument]
async fn start_reflector_async(_lua: Lua, json: String) -> LuaResult<()> {
    let args: StartReflectorArgs = serde_json::from_str(&json).unwrap();

    with_client(move |client| async move {
        let gvk = GroupVersionKind::gvk(&args.gvk.g, &args.gvk.v, &args.gvk.k);
        let _ = store::init_reflector_for_kind(client.clone(), gvk, args.namespace).await;
        Ok(())
    })
}

#[tracing::instrument]
async fn fetch_all_async(
    _lua: Lua,
    args: (String, Option<String>, Option<String>, Option<String>),
) -> LuaResult<String> {
    let (kind, group, version, namespace) = args;

    with_client(move |client| async move {
        let mut items = get_resources_async(&client, kind, group, version, namespace)
            .await
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        for item in &mut items {
            crate::utils::strip_managed_fields(item);
        }
        let json_str = k8s_openapi::serde_json::to_string(&items)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        Ok(json_str)
    })
}

#[tracing::instrument]
async fn fetch_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: FetchArgs = serde_json::from_str(&json).unwrap();

    with_client(move |client| async move {
        get_resource_async(
            &client,
            args.gvk.k,
            Some(args.gvk.g),
            Some(args.gvk.v),
            args.name,
            args.namespace,
            args.output,
        )
        .await
    })
}

#[tracing::instrument]
pub async fn get_fallback_table_async(lua: Lua, json: String) -> LuaResult<String> {
    let args: GetFallbackTableArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let proc = processor("fallback");
    let processed = proc.process_fallback(
        &lua,
        args.name,
        args.namespace,
        args.sort_by,
        args.sort_order,
        args.filter,
        args.filter_label,
    )?;

    serde_json::to_string(&processed).map_err(|e| mlua::Error::RuntimeError(e.to_string()))
}

#[tracing::instrument]
async fn get_table_async(lua: Lua, json: String) -> LuaResult<String> {
    let args: GetTableArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;
    with_client(move |client| async move {
        let cached = (store::get(&args.gvk.k, args.namespace.clone()).await).unwrap_or_default();
        let resources: Vec<DynamicObject> = if cached.is_empty() {
            get_resources_async(
                &client,
                args.gvk.k.clone(),
                Some(args.gvk.g),
                Some(args.gvk.v),
                args.namespace,
            )
            .await
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?
        } else {
            cached
        };

        let processor = processor(args.gvk.k.to_lowercase().as_str());
        let processed = processor
            .process(
                &lua,
                &resources,
                args.sort_by,
                args.sort_order,
                args.filter,
                args.filter_label,
            )
            .map_err(mlua::Error::external)?;

        let json_str = k8s_openapi::serde_json::to_string(&processed)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        Ok(json_str)
    })
}

#[mlua::lua_module(skip_memory_check)]
fn kubectl_client(lua: &Lua) -> LuaResult<mlua::Table> {
    let exports = lua.create_table()?;
    exports.set(
        "init_logging",
        lua.create_function(|_, path: String| {
            logging::setup_logger(&path, "http://localhost:4317")
                .map_err(|e| LuaError::external(format!("{:?}", e)))?;
            Ok(())
        })?,
    )?;

    let default = panic::take_hook();

    panic::set_hook(Box::new(move |panic_info| {
        let bt = Backtrace::force_capture();
        error!(target: "panic",
               "panic: {panic_info}\n\nBacktrace:\n{bt}");
        default(panic_info);
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
        lua.create_async_function(cmd::stream::log_stream_async)?,
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
        "get_minified_config_async",
        lua.create_async_function(get_minified_config_async)?,
    )?;
    exports.set(
        "get_version_async",
        lua.create_async_function(get_version_async)?,
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
    exports.set("delete_async", lua.create_async_function(delete_async)?)?;
    exports.set("scale_async", lua.create_async_function(scale_async)?)?;
    exports.set("restart_async", lua.create_async_function(restart_async)?)?;
    exports.set(
        "deployment_set_images",
        lua.create_function(dao::deployment::set_images)?,
    )?;
    exports.set(
        "statefulset_set_images",
        lua.create_function(dao::statefulset::set_images)?,
    )?;
    exports.set(
        "daemonset_set_images",
        lua.create_function(dao::daemonset::set_images)?,
    )?;
    exports.set(
        "create_job_from_cronjob",
        lua.create_function(dao::cronjob::create_job_from_cronjob)?,
    )?;
    exports.set(
        "suspend_cronjob",
        lua.create_function(dao::cronjob::suspend_cronjob)?,
    )?;
    exports.set("cordon_node", lua.create_function(dao::node::cordon)?)?;
    exports.set("uncordon_node", lua.create_function(dao::node::uncordon)?)?;
    exports.set(
        "drain_node_async",
        lua.create_async_function(drain::drain_node_async)?,
    )?;

    Ok(exports)
}
