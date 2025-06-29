use crate::events::color_status;
use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::api::core::v1::Namespace;
use k8s_openapi::serde_json::{from_value, to_value};
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct NamespaceProcessed {
    name: String,
    status: FieldValue,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct NamespaceProcessor;

impl Processor for NamespaceProcessor {
    type Row = NamespaceProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let node: Namespace =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;

        let name = node.metadata.name.clone().unwrap_or_default();
        let status = get_status(&node);
        let age = self.get_age(obj);

        Ok(NamespaceProcessed { name, status, age })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["name", "status"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "name" => Some(row.name.clone()),
            "status" => match mode {
                AccessorMode::Sort => Some(row.status.value.to_string()),
                AccessorMode::Filter => Some(row.status.value.clone()),
            },
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn get_status(ns: &Namespace) -> FieldValue {
    let phase = ns.status.as_ref().and_then(|s| s.phase.as_ref());

    match phase {
        Some(phase) => FieldValue {
            value: phase.into(),
            symbol: Some(color_status(phase)),
            ..Default::default()
        },
        None => FieldValue {
            value: "Unknown".to_string(),
            symbol: Some(color_status("Unknown")),
            ..Default::default()
        },
    }
}
