use k8s_openapi::api::core::v1::ConfigMap;
use k8s_openapi::serde_json::{from_value, to_value};
use kube::api::DynamicObject;
use mlua::prelude::*;

use crate::processors::processor::Processor;
use crate::utils::{pad_key, AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct ConfigmapProcessed {
    namespace: String,
    name: String,
    #[serde(rename = "data")]
    binary_data: FieldValue,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ConfigmapProcessor;

impl Processor for ConfigmapProcessor {
    type Row = ConfigmapProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let map: ConfigMap =
            from_value(to_value(obj).expect("Failed to convert DynamicObject to JSON Value"))
                .expect("Failed to convert JSON Value into ClusterRoleBinding");
        let binary_data = map.data.as_ref().map_or(0, |map| map.len());
        Ok(ConfigmapProcessed {
            namespace: map.metadata.namespace.clone().unwrap_or_default(),
            name: map.metadata.name.clone().unwrap_or_default(),
            binary_data: FieldValue {
                value: binary_data.to_string(),
                sort_by: Some(binary_data),
                ..Default::default()
            },
            age: self.get_age(obj),
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "binary_data"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |resource, field| match field {
            "namespace" => Some(resource.namespace.clone()),
            "name" => Some(resource.name.clone()),
            "data" => match mode {
                AccessorMode::Sort => resource.binary_data.sort_by.map(pad_key),
                AccessorMode::Filter => Some(resource.binary_data.value.clone()),
            },
            "age" => match mode {
                AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
                AccessorMode::Filter => Some(resource.age.value.clone()),
            },
            _ => None,
        })
    }
}
