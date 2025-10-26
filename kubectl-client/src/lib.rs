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
use store::STORE_MAP;
use structs::{GetAllArgs, GetFallbackTableArgs, GetSingleArgs, GetTableArgs, StartReflectorArgs};
use tokio::runtime::Runtime;

use crate::cmd::get::get_resources_async;
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
static BASE_CONFIG: Mutex<Option<Config>> = Mutex::new(None);

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
pub async fn init_client_async(_lua: Lua, _args: String) -> LuaResult<bool> {
    use tokio::time::Duration;
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let base_cfg = {
        BASE_CONFIG.lock().unwrap().clone().ok_or_else(|| {
            LuaError::RuntimeError("Base kube Config not prepared (call init_runtime first)".into())
        })?
    };

    let cli_res: LuaResult<(Client, Client)> = rt.block_on(async {
        let mut cfg_fast = base_cfg.clone();
        cfg_fast.read_timeout = Some(Duration::from_secs(20));
        let mut cfg_long = base_cfg.clone();
        cfg_long.read_timeout = Some(Duration::from_secs(295));

        let fast_task = tokio::spawn(async move { Client::try_from(cfg_fast) });
        let long_task = tokio::spawn(async move { Client::try_from(cfg_long) });

        let (client_main_res, client_long_res) = tokio::try_join!(fast_task, long_task)
            .map_err(|e| LuaError::RuntimeError(format!("join error building clients: {e}")))?;

        let client_main = client_main_res.map_err(LuaError::external)?;
        let client_long = client_long_res.map_err(LuaError::external)?;

        client_main
            .apiserver_version()
            .await
            .map_err(LuaError::external)?;
        Ok::<_, LuaError>((client_main, client_long))
    });

    let (client_main, client_long) = match cli_res {
        Ok(pair) => pair,
        Err(e) => {
            tracing::warn!(error = %e, "failed to initialise kube clients");
            return Ok(false);
        }
    };

    *CLIENT_INSTANCE.lock().unwrap() = Some(client_main.clone());
    *CLIENT_STREAM_INSTANCE.lock().unwrap() = Some(client_long.clone());

    Ok(true)
}

#[tracing::instrument]
fn init_runtime(_lua: &Lua, context_name: Option<String>) -> LuaResult<(bool, String)> {
    shutdown_pod_collector();
    shutdown_node_collector();

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("create Tokio runtime"));
    {
        let mut ctx = ACTIVE_CONTEXT
            .write()
            .map_err(|_| LuaError::RuntimeError("poisoned ACTIVE_CONTEXT lock".into()))?;
        *ctx = context_name.clone();
    }

    let init_res: LuaResult<()> = rt.block_on(async {
        let store_future = async {
            let store = get_store_map();
            store.write().await.clear();
            Ok::<(), LuaError>(())
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

            {
                let mut slot = BASE_CONFIG.lock().unwrap();
                *slot = Some(base_cfg);
            }

            {
                *CLIENT_INSTANCE.lock().unwrap() = None;
                *CLIENT_STREAM_INSTANCE.lock().unwrap() = None;
            }

            Ok::<(), LuaError>(())
        };

        tokio::try_join!(store_future, config_future).map(|_| ())
    });

    if let Err(e) = init_res {
        tracing::warn!(error = %e, "failed to prepare kube config");
        return Ok((false, e.to_string()));
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

    exports.set(
        "init_client_async",
        lua.create_async_function(init_client_async)?,
    )?;
    exports.set("init_runtime", lua.create_function(init_runtime)?)?;
    exports.set("init_metrics", lua.create_function(init_metrics)?)?;
    exports.set(
        "start_reflector_async",
        lua.create_async_function(start_reflector_async)?,
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
    exports.set(
        "drain_node_async",
        lua.create_async_function(drain::drain_node_async)?,
    )?;

    exports.set(
        "start_dashboard",
        lua.create_function(|_, view_name: String| ui::dashboard::Session::new(view_name))?,
    )?;
    exports.set(
        "describe_async",
        lua.create_async_function(describe::describe_async)?,
    )?;

    dao::install(lua, &exports)?;
    cmd::install(lua, &exports)?;
    event_queue::install(lua, &exports)?;

    Ok(exports)
}
