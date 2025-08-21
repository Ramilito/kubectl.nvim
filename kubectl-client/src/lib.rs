// lib.rs
use ctor::dtor;
use k8s_openapi::serde_json;
use kube::api::DynamicObject;
use kube::config::ExecInteractiveMode;
use kube::{api::GroupVersionKind, config::KubeConfigOptions, Client, Config};
use metrics::nodes::{shutdown_node_collector, spawn_node_collector, NodeStat, SharedNodeStats};
use metrics::pods::{shutdown_pod_collector, spawn_pod_collector, PodStat, SharedPodStats};
use mlua::prelude::*;
use mlua::Lua;
use std::future::Future;
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use std::time::Duration;
use store::STORE_MAP;
use structs::{GetAllArgs, GetFallbackTableArgs, GetSingleArgs, GetTableArgs, StartReflectorArgs};
use tokio::runtime::Runtime;

use crate::cmd::apply::apply_async;
use crate::cmd::config::{
    get_config, get_config_async, get_minified_config_async, get_version_async,
};
use crate::cmd::delete::delete_async;
use crate::cmd::edit::edit_async;
use crate::cmd::get::{
    get_api_resources_async, get_raw_async, get_resources_async, get_server_raw_async, get_single,
    get_single_async,
};
use crate::cmd::portforward::{portforward_list, portforward_start, portforward_stop};
use crate::cmd::restart::restart_async;
use crate::cmd::scale::scale_async;
use crate::processors::processor_for;
use crate::statusline::get_statusline;
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
mod event_queue;
mod events;
mod filter;
mod metrics;
mod processors;
mod sort;
mod statusline;
mod store;
mod structs;
mod ui;
mod utils;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static CLIENT_INSTANCE: Mutex<Option<Client>> = Mutex::new(None);
static CLIENT_STREAM_INSTANCE: Mutex<Option<Client>> = Mutex::new(None);
static ACTIVE_CONTEXT: RwLock<Option<String>> = RwLock::new(None);
static POD_STATS: OnceLock<SharedPodStats> = OnceLock::new();
static NODE_STATS: OnceLock<SharedNodeStats> = OnceLock::new();

pub fn pod_stats() -> &'static SharedPodStats {
    POD_STATS.get_or_init(|| Arc::new(Mutex::new(Vec::<PodStat>::new())))
}

pub fn node_stats() -> &'static SharedNodeStats {
    NODE_STATS.get_or_init(|| Arc::new(Mutex::new(Vec::<NodeStat>::new())))
}

fn block_on<F: std::future::Future>(fut: F) -> F::Output {
    use tokio::{runtime::Handle, task};
    match Handle::try_current() {
        Ok(h) => task::block_in_place(|| h.block_on(fut)),
        Err(_) => {
            let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
            rt.block_on(fut)
        }
    }
}

pub fn with_client<F, Fut, R>(f: F) -> LuaResult<R>
where
    F: FnOnce(Client) -> Fut,
    Fut: Future<Output = LuaResult<R>>,
{
    let client = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("poisoned CLIENT lock".into()))?
        .as_ref()
        .cloned()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialised".into()))?;

    block_on(f(client))
}

pub fn with_stream_client<F, Fut, R>(f: F) -> LuaResult<R>
where
    F: FnOnce(Client) -> Fut,
    Fut: Future<Output = LuaResult<R>>,
{
    let client = CLIENT_STREAM_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("poisoned CLIENT lock".into()))?
        .as_ref()
        .cloned()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialised".into()))?;

    block_on(f(client))
}

#[tracing::instrument]
fn init_runtime(_lua: &Lua, context_name: Option<String>) -> LuaResult<(bool, String)> {
    shutdown_pod_collector();
    shutdown_node_collector();
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("create Tokio runtime"));

    let cli_res: LuaResult<(Client, Client)> = rt.block_on(async {
        use futures::future::join;

        let store_future = async {
            let store = get_store_map();
            store.write().await.clear();
        };

        let config_future = async {
            let opts = KubeConfigOptions {
                context: context_name.clone(),
                cluster: None,
                user: None,
            };

            let mut base_cfg = Config::from_kubeconfig(&opts)
                .await
                .map_err(LuaError::external)?;

            if let Some(exec) = base_cfg.auth_info.exec.as_mut() {
                exec.interactive_mode = Some(ExecInteractiveMode::Never);
                if let Some(args) = exec.args.as_mut() {
                    if let Some(pos) = args.iter().position(|a| a == "devicecode") {
                        args[pos] = "azurecli".into();
                    }
                }
            }

            let mut cfg_fast = base_cfg.clone();
            cfg_fast.read_timeout = Some(Duration::from_secs(20));
            let client_main = Client::try_from(cfg_fast).map_err(LuaError::external)?;

            let mut cfg_long = base_cfg;
            cfg_long.read_timeout = Some(Duration::from_secs(295));
            let client_long = Client::try_from(cfg_long).map_err(LuaError::external)?;

            Ok((client_main, client_long))
        };

        {
            let mut ctx = ACTIVE_CONTEXT
                .write()
                .map_err(|_| LuaError::RuntimeError("poisoned ACTIVE_CONTEXT lock".into()))?;
            *ctx = context_name.clone();
        }

        let ((), cli) = join(store_future, config_future).await;
        cli
    });

    let (client_main, client_long) = match cli_res {
        Ok(pair) => pair,
        Err(e) => {
            tracing::warn!(error = %e, "failed to initialise kube clients");
            return Ok((false, e.to_string()));
        }
    };

    {
        *CLIENT_INSTANCE.lock().unwrap() = Some(client_main.clone());
        *CLIENT_STREAM_INSTANCE.lock().unwrap() = Some(client_long.clone());
    }

    Ok((true, String::new()))
}

fn init_metrics(_lua: &Lua, _args: ()) -> LuaResult<bool> {
    with_client(|client| async move {
        spawn_pod_collector(client.clone());
        spawn_node_collector(client);
        Ok(())
    })?;
    Ok(true)
}

#[tracing::instrument]
fn get_all(lua: &Lua, json: String) -> LuaResult<String> {
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
pub async fn get_fallback_table_async(lua: Lua, json: String) -> LuaResult<String> {
    let args: GetFallbackTableArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let proc = processor_for("fallback");
    let processed = proc.process_fallback(
        &lua,
        args.gvk,
        args.namespace,
        args.sort_by,
        args.sort_order,
        args.filter,
        args.filter_label,
        args.filter_key,
    )?;

    serde_json::to_string(&processed).map_err(|e| mlua::Error::RuntimeError(e.to_string()))
}

#[tracing::instrument]
async fn get_container_table_async(lua: Lua, json: String) -> LuaResult<String> {
    let args: GetSingleArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let pod = store::get_single(&args.gvk.k, args.namespace.clone(), &args.name)
        .await
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))
        .unwrap();

    let vec = match pod {
        Some(p) => vec![p],
        None => Vec::new(),
    };
    let proc = processor_for("container");
    let processed = proc
        .process(&lua, &vec, None, None, None, None, None)
        .map_err(mlua::Error::external)?;

    Ok(processed)
}

#[tracing::instrument]
async fn get_table_async(lua: Lua, json: String) -> LuaResult<String> {
    let args: GetTableArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;
    let cached = store::get(&args.gvk.k, args.namespace.clone())
        .await
        .unwrap_or_default();
    let proc = processor_for(&args.gvk.k.to_lowercase());

    proc.process(
        &lua,
        &cached,
        args.sort_by,
        args.sort_order,
        args.filter,
        args.filter_label,
        args.filter_key,
    )
}

#[tracing::instrument]
pub async fn get_statusline_async(_lua: Lua, _args: ()) -> LuaResult<String> {
    with_client(|client| async move {
        let statusline = match get_statusline(client).await {
            Ok(s) => s,
            Err(_) => return Ok(String::new()),
        };

        let json_str = k8s_openapi::serde_json::to_string(&statusline)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        Ok(json_str)
    })
}

/// Runs automatically when the cdylib is unloaded
#[dtor]
fn on_unload() {
    shutdown_pod_collector();
    shutdown_node_collector();

    {
        *CLIENT_INSTANCE.lock().unwrap() = None;
        *CLIENT_STREAM_INSTANCE.lock().unwrap() = None;
    }
    {
        let mut ctx = ACTIVE_CONTEXT.write().unwrap();
        *ctx = None;
    }

    {
        if let Some(map) = STORE_MAP.get() {
            let _ = map;
        }
    }
}

#[tracing::instrument]
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

    exports.set("init_runtime", lua.create_function(init_runtime)?)?;

    exports.set("init_metrics", lua.create_function(init_metrics)?)?;
    exports.set(
        "start_reflector_async",
        lua.create_async_function(start_reflector_async)?,
    )?;

    exports.set(
        "start_dashboard",
        lua.create_function(|_, view_name: String| ui::dashboard::Session::new(view_name))?,
    )?;
    exports.set("portforward_start", lua.create_function(portforward_start)?)?;
    exports.set("portforward_list", lua.create_function(portforward_list)?)?;
    exports.set("portforward_stop", lua.create_function(portforward_stop)?)?;
    exports.set(
        "debug",
        lua.create_function(
            |_, (ns, pod, image, target): (String, String, String, Option<String>)| {
                with_stream_client(|client| async move {
                    cmd::exec::open_debug(client, ns, pod, image, target)
                })
            },
        )?,
    )?;
    exports.set(
        "exec",
        lua.create_function(
            |_, (ns, pod, container, cmd): (String, String, Option<String>, Vec<String>)| {
                with_stream_client(|client| async move {
                    cmd::exec::Session::new(client, ns, pod, container, cmd, true)
                })
            },
        )?,
    )?;
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
    exports.set("get_single", lua.create_function(get_single)?)?;
    exports.set(
        "get_single_async",
        lua.create_async_function(get_single_async)?,
    )?;
    exports.set("get_all", lua.create_function(get_all)?)?;
    exports.set("get_all_async", lua.create_async_function(get_all_async)?)?;
    exports.set(
        "get_container_table_async",
        lua.create_async_function(get_container_table_async)?,
    )?;
    exports.set(
        "get_table_async",
        lua.create_async_function(get_table_async)?,
    )?;
    exports.set(
        "get_fallback_table_async",
        lua.create_async_function(get_fallback_table_async)?,
    )?;
    exports.set(
        "get_statusline_async",
        lua.create_async_function(get_statusline_async)?,
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

    event_queue::install(lua, &exports)?;

    Ok(exports)
}
