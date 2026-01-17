use mlua::{Lua, Result as LuaResult, Table as LuaTable};

use crate::cmd::apply::apply_async;
use crate::cmd::config::{
    get_config, get_config_async, get_minified_config_async, get_version_async,
};
use crate::cmd::delete::delete_async;
use crate::cmd::drift::get_drift;
use crate::cmd::edit::edit_async;
use crate::cmd::exec::{
    await_status_or_timeout, open_debug, open_exec, open_node_shell, NodeShellConfig,
    NodeShellSession, Session,
};
use crate::cmd::get::{
    get_api_resources_async, get_raw_async, get_server_raw_async, get_single, get_single_async,
};
use crate::cmd::log_session::{fetch_logs_async, log_session};
use crate::cmd::portforward::{portforward_list, portforward_start, portforward_stop};
use crate::cmd::restart::restart_async;
use crate::cmd::scale::scale_async;
use crate::hover::get_hover_async;
use crate::with_stream_client;

pub mod apply;
pub mod config;
pub mod delete;
pub mod drift;
pub mod edit;
pub mod exec;
pub mod get;
pub mod log_session;
pub mod portforward;
pub mod restart;
pub mod scale;
pub mod utils;

pub fn install(lua: &Lua, exports: &LuaTable) -> LuaResult<()> {
    exports.set("portforward_start", lua.create_function(portforward_start)?)?;
    exports.set("portforward_list", lua.create_function(portforward_list)?)?;
    exports.set("portforward_stop", lua.create_function(portforward_stop)?)?;
    exports.set("apply_async", lua.create_async_function(apply_async)?)?;
    exports.set(
        "edit_async",
        lua.create_async_function(|lua, args| async move { edit_async(lua, args).await })?,
    )?;
    exports.set("delete_async", lua.create_async_function(delete_async)?)?;
    exports.set("scale_async", lua.create_async_function(scale_async)?)?;
    exports.set("restart_async", lua.create_async_function(restart_async)?)?;
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
    exports.set(
        "debug",
        lua.create_function(
            |_, (ns, pod, image, target): (String, String, String, Option<String>)| {
                with_stream_client(|client| async move {
                    let proc = open_debug(&client, &ns, &pod, &image, target.as_deref()).await?;
                    Ok(Session::from_attached(proc))
                })
            },
        )?,
    )?;
    exports.set(
        "exec",
        lua.create_function(
            |_, (ns, pod, container, cmd): (String, String, Option<String>, Vec<String>)| {
                with_stream_client(|client| async move {
                    let proc = open_exec(&client, &ns, &pod, &container, &cmd, true)
                        .await
                        .map_err(mlua::Error::external)?;
                    let proc = await_status_or_timeout(proc)
                        .await
                        .map_err(mlua::Error::external)?;
                    Ok(Session::from_attached(proc))
                })
            },
        )?,
    )?;
    exports.set(
        "node_shell",
        lua.create_function(|_, config: NodeShellConfig| {
            with_stream_client(|client| async move {
                let (proc, pod_name) = open_node_shell(&client, &config).await?;
                Ok(NodeShellSession::new(proc, client, config.namespace, pod_name))
            })
        })?,
    )?;
    exports.set(
        "log_stream_async",
        lua.create_async_function(fetch_logs_async)?,
    )?;
    exports.set("log_session", lua.create_function(log_session)?)?;
    exports.set("get_drift", lua.create_function(get_drift)?)?;
    exports.set(
        "get_hover_async",
        lua.create_async_function(get_hover_async)?,
    )?;

    Ok(())
}
