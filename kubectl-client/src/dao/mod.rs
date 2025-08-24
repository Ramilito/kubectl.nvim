use mlua::{Lua, Result as LuaResult, Table as LuaTable};

use crate::dao;

pub mod cronjob;
pub mod daemonset;
pub mod deployment;
pub mod node;
pub mod statefulset;

pub fn install(lua: &Lua, exports: &LuaTable) -> LuaResult<()> {
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
    Ok(())
}
