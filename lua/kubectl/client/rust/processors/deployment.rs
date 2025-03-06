use crate::processors::processor::Processor;
use crate::utils::{filter_dynamic, get_age, sort_dynamic, time_since, AccessorMode, FieldValue};
use k8s_openapi::serde_json::{self, Value};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

#[derive(Debug, Clone, serde::Serialize)]
pub struct Status {
    pub symbol: String,
    pub value: String,
    pub sort_by: i64,
}

#[derive(Debug, Clone, serde::Serialize)]
struct Age {
    symbol: String,
    value: String,
    sort_by: i64,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DeploymentProcessed {
    namespace: String,
    name: String,
    ready: Status,
    #[serde(rename = "up-to-date")]
    up_to_date: i64,
    available: i64,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DeploymentProcessor;

impl Processor for DeploymentProcessor {
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
            let raw_json = serde_json::to_value(obj).unwrap_or(Value::Null);

            let namespace = obj.metadata.namespace.clone().unwrap_or_default();
            let name = obj.metadata.name.clone().unwrap_or_default();

            let creation_ts = obj
                .metadata
                .creation_timestamp
                .as_ref()
                .map(|t| t.0.to_rfc3339())
                .unwrap_or_default();

            let up_to_date = raw_json
                .pointer("/status/updatedReplicas")
                .and_then(Value::as_i64)
                .unwrap_or(0);

            let available = raw_json
                .pointer("/status/availableReplicas")
                .and_then(Value::as_i64)
                .unwrap_or(0);

            let age = get_age(&obj);
            let ready = get_ready(&raw_json);

            data.push(DeploymentProcessed {
                namespace,
                name,
                ready,
                up_to_date,
                available,
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
                &["namespace", "name", "ready"],
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

fn field_accessor(mode: AccessorMode) -> impl Fn(&DeploymentProcessed, &str) -> Option<String> {
    move |resource, field| match field {
        "namespace" => Some(resource.namespace.clone()),
        "name" => Some(resource.name.clone()),
        "ready" => Some(resource.ready.value.clone()),
        "up_to_date" => Some(resource.up_to_date.to_string()),
        "available" => Some(resource.available.to_string()),
        "age" => match mode {
            AccessorMode::Sort => Some(resource.age.sort_by.to_string()),
            AccessorMode::Filter => Some(resource.age.value.clone()),
        },
        _ => None,
    }
}

fn get_ready(row: &Value) -> Status {
    let available = row
        .get("status")
        .and_then(|s| {
            s.get("availableReplicas")
                .or_else(|| s.get("readyReplicas"))
        })
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let unavailable = row
        .get("status")
        .and_then(|s| s.get("unavailableReplicas"))
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let replicas = row
        .get("spec")
        .and_then(|s| s.get("replicas"))
        .or_else(|| row.get("status").and_then(|s| s.get("replicas")))
        .and_then(|v| v.as_i64())
        .unwrap_or(0);

    // For simplicity, we use fixed strings for symbols.
    // In your full application, these might come from your highlight/event module.
    let symbol = if available == replicas && unavailable == 0 {
        "KubectlNote".to_string()
    } else {
        "KubectlDeprecated".to_string()
    };

    let value = format!("{}/{}", available, replicas);
    let sort_by = (available * 1000) + replicas;

    Status {
        symbol,
        value,
        sort_by,
    }
}
