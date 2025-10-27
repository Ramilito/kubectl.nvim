use crate::processors::processor::Processor;
use crate::utils::{pad_key, AccessorMode, FieldValue};
use k8s_openapi::api::apps::v1::StatefulSet;
use k8s_openapi::serde_json::{from_value, to_value};
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct StatefulsetProcessed {
    namespace: String,
    name: String,
    ready: FieldValue,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct StatefulsetProcessor;

impl Processor for StatefulsetProcessor {
    type Row = StatefulsetProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let statefulset: StatefulSet =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;
        let namespace = statefulset.metadata.namespace.clone().unwrap_or_default();
        let name = statefulset.metadata.name.clone().unwrap_or_default();
        let age = self.get_age(obj);
        let ready = get_ready_from_statefulset(&statefulset);
        Ok(StatefulsetProcessed {
            namespace,
            name,
            ready,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "ready"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |r, field| match field {
            "namespace" => Some(r.namespace.clone()),
            "name" => Some(r.name.clone()),
            "ready" => match mode {
                AccessorMode::Sort => r.ready.sort_by.map(pad_key),
                AccessorMode::Filter => Some(r.ready.value.clone()),
            },
            "age" => match mode {
                AccessorMode::Sort => r.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(r.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn get_ready_from_statefulset(ss: &StatefulSet) -> FieldValue {
    let available = ss
        .status
        .as_ref()
        .and_then(|s| s.available_replicas)
        .unwrap_or(0) as u64;
    let ready_replicas = ss
        .status
        .as_ref()
        .and_then(|s| s.ready_replicas)
        .unwrap_or(0) as u64;
    let symbol = if available == ready_replicas {
        "KubectlNote"
    } else {
        "KubectlDeprecated"
    }
    .to_string();
    let value = format!("{}/{}", available, ready_replicas);
    let sort_by = (available * 1001) + ready_replicas;
    FieldValue {
        symbol: Some(symbol),
        value,
        sort_by: Some(sort_by as usize),
    }
}
