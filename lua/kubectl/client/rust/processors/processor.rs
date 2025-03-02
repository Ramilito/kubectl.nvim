use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

pub trait Processor: Send + Sync {
    fn process(&self, lua: &Lua, items: &[DynamicObject]) -> LuaResult<mlua::Value>;
}
