use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

pub trait Processor: Send + Sync {
    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
    ) -> LuaResult<mlua::Value>;
}
