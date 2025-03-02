use crate::processors::processor::Processor;
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

pub struct DefaultProcessor;

impl Processor for DefaultProcessor {
    fn process(&self, lua: &Lua, items: &[DynamicObject]) -> LuaResult<mlua::Value> {
        Ok(lua.to_value(&items)?)
    }
}
