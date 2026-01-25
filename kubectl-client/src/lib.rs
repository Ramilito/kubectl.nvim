// lib.rs
use k8s_openapi::serde_json;
use kube::api::DynamicObject;
use kube::config::ExecInteractiveMode;
use kube::{api::GroupVersionKind, config::KubeConfigOptions, Client, Config};
use health::{get_health_status, shutdown_health_collector, spawn_health_collector};
use metrics::nodes::{shutdown_node_collector, spawn_node_collector, NodeStat, SharedNodeStats};
use metrics::pods::{shutdown_pod_collector, spawn_pod_collector, PodKey, PodStat, SharedPodStats};
use std::collections::HashMap;
use mlua::prelude::*;
use mlua::Lua;
use std::future::Future;
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use structs::{GetAllArgs, GetFallbackTableArgs, GetSingleArgs, GetTableArgs, StartReflectorArgs};
use tokio::runtime::Runtime;

use crate::cmd::get::get_resources_async;
use crate::processors::{processor_for, FilterParams};
use crate::statusline::get_statusline;
use crate::store::shutdown_all_reflectors;

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
mod describe_session;
mod drain;
mod event_queue;
mod health;
mod events;
mod filter;
mod hover;
mod lineage;
mod metrics;
mod processors;
mod sort;
mod statusline;
mod store;
mod streaming;
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
    POD_STATS.get_or_init(|| Arc::new(Mutex::new(HashMap::<PodKey, PodStat>::new())))
}

pub fn node_stats() -> &'static SharedNodeStats {
    NODE_STATS.get_or_init(|| Arc::new(Mutex::new(HashMap::<String, NodeStat>::new())))
}

/// Clears all cached pod metrics (called on context change)
pub fn clear_pod_stats() {
    if let Ok(mut guard) = pod_stats().lock() {
        guard.clear();
    }
}

/// Clears all cached node metrics (called on context change)
pub fn clear_node_stats() {
    if let Ok(mut guard) = node_stats().lock() {
        guard.clear();
    }
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
        BASE_CONFIG
            .lock()
            .map_err(|_| LuaError::RuntimeError("poisoned BASE_CONFIG lock".into()))?
            .clone()
            .ok_or_else(|| {
                LuaError::RuntimeError(
                    "Base kube Config not prepared (call init_runtime first)".into(),
                )
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

    *CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("poisoned CLIENT_INSTANCE lock".into()))? =
        Some(client_main.clone());
    *CLIENT_STREAM_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("poisoned CLIENT_STREAM_INSTANCE lock".into()))? =
        Some(client_long.clone());

    Ok(true)
}

#[tracing::instrument]
fn init_runtime(_lua: &Lua, context_name: Option<String>) -> LuaResult<(bool, String)> {
    // Stop collectors and clear stale metrics from previous context
    shutdown_pod_collector();
    shutdown_node_collector();
    shutdown_health_collector();
    clear_pod_stats();
    clear_node_stats();

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("create Tokio runtime"));
    {
        let mut ctx = ACTIVE_CONTEXT
            .write()
            .map_err(|_| LuaError::RuntimeError("poisoned ACTIVE_CONTEXT lock".into()))?;
        *ctx = context_name.clone();
    }

    let init_res: LuaResult<()> = rt.block_on(async {
        let store_future = async {
            shutdown_all_reflectors().await;
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
                let mut slot = BASE_CONFIG
                    .lock()
                    .map_err(|_| LuaError::RuntimeError("poisoned BASE_CONFIG lock".into()))?;
                *slot = Some(base_cfg);
            }

            {
                *CLIENT_INSTANCE
                    .lock()
                    .map_err(|_| LuaError::RuntimeError("poisoned CLIENT_INSTANCE lock".into()))? =
                    None;
                *CLIENT_STREAM_INSTANCE
                    .lock()
                    .map_err(|_| {
                        LuaError::RuntimeError("poisoned CLIENT_STREAM_INSTANCE lock".into())
                    })? = None;
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
        spawn_node_collector(client.clone());
        spawn_health_collector(client);
        Ok(())
    })?;
    Ok(true)
}

/// Synchronous version of get_all - blocks the Neovim main thread.
/// NOTE: Required for Neovim command completion (e.g., :Kubens) which must be synchronous.
/// For all other uses, prefer get_all_async.
#[tracing::instrument]
fn get_all(_lua: &Lua, json: String) -> LuaResult<String> {
    let args: GetAllArgs = serde_json::from_str(&json)
        .map_err(|e| mlua::Error::external(format!("invalid JSON in get_all: {e}")))?;
    with_client(move |client| async move {
        let cached = store::get(&args.gvk.k, args.namespace.clone()).unwrap_or_default();
        let resources: Vec<DynamicObject> = if cached.is_empty() {
            get_resources_async(&client, args.gvk.k, args.gvk.g, args.gvk.v, args.namespace)
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
    let args: GetAllArgs = serde_json::from_str(&json)
        .map_err(|e| mlua::Error::external(format!("invalid JSON in get_all_async: {e}")))?;
    with_client(move |client| async move {
        let cached = store::get(&args.gvk.k, args.namespace.clone()).unwrap_or_default();
        let resources: Vec<DynamicObject> = if cached.is_empty() {
            get_resources_async(&client, args.gvk.k, args.gvk.g, args.gvk.v, args.namespace)
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
    let args: StartReflectorArgs = serde_json::from_str(&json)
        .map_err(|e| mlua::Error::external(format!("invalid JSON in start_reflector_async: {e}")))?;

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
    let params = FilterParams {
        sort_by: args.sort_by,
        sort_order: args.sort_order,
        filter: args.filter,
        filter_label: args.filter_label,
        filter_key: args.filter_key,
    };
    let processed = proc.process_fallback(&lua, args.gvk, args.namespace, &params)?;

    serde_json::to_string(&processed).map_err(|e| mlua::Error::RuntimeError(e.to_string()))
}

#[tracing::instrument]
fn get_container_table(lua: &Lua, json: String) -> LuaResult<String> {
    let args: GetSingleArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let pod = store::get_single(&args.gvk.k, args.namespace.clone(), &args.name)
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

    let vec = match pod {
        Some(p) => vec![p],
        None => Vec::new(),
    };
    let proc = processor_for("container");
    proc.process(&lua, &vec, &FilterParams::default())
}

#[tracing::instrument]
fn get_table(lua: &Lua, json: String) -> LuaResult<String> {
    let args: GetTableArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;
    let cached = store::get(&args.gvk.k, args.namespace.clone()).unwrap_or_default();
    let proc = processor_for(&args.gvk.k.to_lowercase());
    let params = FilterParams {
        sort_by: args.sort_by,
        sort_order: args.sort_order,
        filter: args.filter,
        filter_label: args.filter_label,
        filter_key: args.filter_key,
    };
    proc.process(&lua, &cached, &params)
}

#[tracing::instrument]
pub async fn get_statusline_async(_lua: Lua, _args: ()) -> LuaResult<String> {
    with_client(|client| async move {
        let statusline = match get_statusline(client).await {
            Ok(s) => s,
            Err(e) => {
                tracing::warn!("Failed to get statusline data: {}", e);
                return Ok(String::new());
            }
        };

        let json_str = k8s_openapi::serde_json::to_string(&statusline)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        Ok(json_str)
    })
}

#[tracing::instrument]
async fn shutdown_async(_lua: Lua, _args: ()) -> LuaResult<String> {
    shutdown_pod_collector();
    shutdown_node_collector();
    shutdown_health_collector();
    shutdown_all_reflectors().await;

    {
        *CLIENT_INSTANCE
            .lock()
            .map_err(|_| LuaError::RuntimeError("poisoned CLIENT_INSTANCE lock".into()))? = None;
        *CLIENT_STREAM_INSTANCE
            .lock()
            .map_err(|_| LuaError::RuntimeError("poisoned CLIENT_STREAM_INSTANCE lock".into()))? =
            None;
    }
    {
        let mut ctx = ACTIVE_CONTEXT
            .write()
            .map_err(|_| LuaError::RuntimeError("poisoned ACTIVE_CONTEXT lock".into()))?;
        *ctx = None;
    }

    logging::shutdown();

    Ok("Done".to_string())
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

    exports.set("shutdown_async", lua.create_async_function(shutdown_async)?)?;
    exports.set("get_all", lua.create_function(get_all)?)?;
    exports.set("get_all_async", lua.create_async_function(get_all_async)?)?;
    exports.set(
        "get_container_table_async",
        lua.create_function(get_container_table)?,
    )?;
    exports.set(
        "get_table_async",
        lua.create_function(get_table)?,
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
        "start_buffer_dashboard",
        lua.create_function(|_, view_name: String| ui::BufferSession::new(view_name))?,
    )?;

    exports.set(
        "describe_session",
        lua.create_function(describe_session::describe_session)?,
    )?;

    exports.set(
        "toggle_json",
        lua.create_function(|lua, input: String| {
            match cmd::log_session::toggle_json(&input) {
                Some(result) => {
                    let tbl = lua.create_table()?;
                    tbl.set("json", result.json)?;
                    tbl.set("start_idx", result.start_idx)?;
                    tbl.set("end_idx", result.end_idx)?;
                    Ok(mlua::Value::Table(tbl))
                }
                None => Ok(mlua::Value::Nil),
            }
        })?,
    )?;

    // Sync health check - reads cached result from background task
    exports.set(
        "get_health_status",
        lua.create_function(|lua, _: ()| {
            let (ok, last_ok) = get_health_status();
            let tbl = lua.create_table()?;
            tbl.set("ok", ok)?;
            tbl.set("time_of_ok", last_ok)?;
            Ok(tbl)
        })?,
    )?;

    // Lineage graph builder
    exports.set(
        "build_lineage_graph",
        lua.create_function(|lua, (resources_json, root_name): (String, String)| {
            lineage::build_lineage_graph(lua, resources_json, root_name)
        })?,
    )?;

    // Lineage graph builder for worker threads (used with commands.run_async)
    exports.set(
        "build_lineage_graph_worker",
        lua.create_function(|_, json_input: String| {
            lineage::build_lineage_graph_worker(json_input)
        })?,
    )?;

    // Get related nodes from stored lineage tree
    exports.set(
        "get_lineage_related_nodes",
        lua.create_function(lineage::get_lineage_related_nodes)?,
    )?;

    // Export lineage graph to DOT format
    exports.set(
        "export_lineage_dot",
        lua.create_function(lineage::export_lineage_dot)?,
    )?;

    // Export lineage graph to Mermaid format
    exports.set(
        "export_lineage_mermaid",
        lua.create_function(lineage::export_lineage_mermaid)?,
    )?;

    // Export lineage subgraph to DOT format
    exports.set(
        "export_lineage_subgraph_dot",
        lua.create_function(lineage::export_lineage_subgraph_dot)?,
    )?;

    // Export lineage subgraph to Mermaid format
    exports.set(
        "export_lineage_subgraph_mermaid",
        lua.create_function(lineage::export_lineage_subgraph_mermaid)?,
    )?;

    // Find orphan resources
    exports.set(
        "find_lineage_orphans",
        lua.create_function(lineage::find_lineage_orphans)?,
    )?;

    // Compute impact analysis
    exports.set(
        "compute_lineage_impact",
        lua.create_function(lineage::compute_lineage_impact)?,
    )?;

    dao::install(lua, &exports)?;
    cmd::install(lua, &exports)?;
    event_queue::install(lua, &exports)?;

    Ok(exports)
}
