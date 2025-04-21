use k8s_openapi::api::core::v1::ConfigMap;
use k8s_openapi::serde_json::{self};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

use crate::processors::processor::Processor;
use crate::utils::{filter_dynamic, sort_dynamic, AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct ConfigmapProcessed {
    namespace: String,
    name: String,
    #[serde(rename = "data")]
    binary_data: usize,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ConfigmapProcessor;

impl Processor for ConfigmapProcessor {
    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
    ) -> LuaResult<mlua::Value> {
        let mut data = Vec::new();

        for obj in items {
            let map: ConfigMap = serde_json::from_value(
                serde_json::to_value(obj).expect("Failed to convert DynamicObject to JSON Value"),
            )
            .expect("Failed to convert JSON Value into ClusterRoleBinding");

            let namespace = map.metadata.namespace.clone().unwrap_or_default();
            let name = map.metadata.name.clone().unwrap_or_default();
            let binary_data = map.data.as_ref().map_or(0, |map| map.len());
            let age = self.get_age(obj);

            data.push(ConfigmapProcessed {
                namespace,
                name,
                binary_data,
                age,
            });
        }
        sort_dynamic(
            &mut data,
            sort_by,
            sort_order,
            field_accessor(AccessorMode::Sort),
        );

        let data = if let Some(ref filter_value) = filter {
            filter_dynamic(
                &data,
                filter_value,
                &["namespace", "name", "binary_data"],
                field_accessor(AccessorMode::Filter),
            )
            .into_iter()
            .cloned()
            .collect()
        } else {
            data
        };

        lua.to_value(&data)
    }
}

fn field_accessor(mode: AccessorMode) -> impl Fn(&ConfigmapProcessed, &str) -> Option<String> {
    move |resource, field| match field {
        "namespace" => Some(resource.namespace.clone()),
        "name" => Some(resource.name.clone()),
        "binary_data" => Some(resource.binary_data.clone().to_string()),
        "age" => match mode {
            AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
            AccessorMode::Filter => Some(resource.age.value.clone()),
        },
        _ => None,
    }
}
