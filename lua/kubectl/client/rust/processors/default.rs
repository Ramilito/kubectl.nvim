use crate::processors::processor::Processor;
use crate::utils::AccessorMode;
use k8s_openapi::serde_json;
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct DefaultProcessor;

impl Processor for DefaultProcessor {
    type Row = DynamicObject;

    fn build_row(&self, _lua: &Lua, obj: &DynamicObject) -> LuaResult<Self::Row> {
        Ok(obj.clone())
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &[]
    }

    fn field_accessor(
        &self,
        _mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(|_, _| None)
    }

    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        _sort_by: Option<String>,
        _sort_order: Option<String>,
        _filter: Option<String>,
        _filter_label: Option<Vec<String>>,
    ) -> LuaResult<mlua::Value> {
        let json_vec: Vec<serde_json::Value> = items
            .iter()
            .map(|obj| serde_json::to_value(obj).map_err(LuaError::external))
            .collect::<Result<_, _>>()?;

        lua.to_value(&json_vec)
    }
}
