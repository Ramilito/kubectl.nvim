use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::api::autoscaling::v2::HorizontalPodAutoscaler;
use k8s_openapi::serde_json::{from_value, to_value};
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct HorizontalPodAutoscalerProcessed {
    namespace: String,
    name: String,
    reference: String,
    targets: String,
    minpods: String,
    maxpods: String,
    replicas: String,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct HorizontalPodAutoscalerProcessor;

impl Processor for HorizontalPodAutoscalerProcessor {
    type Row = HorizontalPodAutoscalerProcessed;

    fn build_row(&self, _lua: &Lua, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let hpa: HorizontalPodAutoscaler =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;
        let namespace = hpa.metadata.namespace.clone().unwrap_or_default();
        let name = hpa.metadata.name.clone().unwrap_or_default();
        let reference = "".to_string();
        let targets = "".to_string();
        let minpods = "".to_string();
        let maxpods = "".to_string();
        let replicas = "".to_string();
        let age = self.get_age(obj);

        Ok(HorizontalPodAutoscalerProcessed {
            namespace,
            name,
            reference,
            targets,
            minpods,
            maxpods,
            replicas,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "reference", "targets"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "name" => Some(row.name.clone()),
            "reference" => Some(row.reference.clone()),
            "targets" => Some(row.targets.clone()),
            "minpods" => Some(row.minpods.clone()),
            "maxpods" => Some(row.maxpods.clone()),
            "replicas" => Some(row.replicas.clone()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}
