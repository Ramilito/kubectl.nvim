use crate::processors::processor::Processor;
use crate::utils::{filter_dynamic, sort_dynamic, time_since};
use k8s_openapi::serde_json::{self, Value};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

#[derive(Debug, Clone, serde::Serialize)]
pub struct ProcessedStatus {
    pub symbol: String,
    pub value: String,
    pub sort_by: i64,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DeploymentProcessed {
    namespace: String,
    name: String,
    ready: ProcessedStatus,
    #[serde(rename = "up-to-date")]
    up_to_date: i64,
    available: i64,
    age: String,
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

            let age = if !creation_ts.is_empty() {
                format!("{}", time_since(&creation_ts))
            } else {
                "".to_string()
            };

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

        let accessor = field_accessor();
        sort_dynamic(&mut data, sort_by, sort_order, &accessor);

        let data = if let Some(ref filter_value) = filter {
            filter_dynamic(
                &data,
                filter_value,
                &["namespace", "name", "ready"],
                &accessor,
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

fn field_accessor() -> impl Fn(&DeploymentProcessed, &str) -> Option<String> {
    |pod, field| match field {
        "namespace" => Some(pod.namespace.clone()),
        "name" => Some(pod.name.clone()),
        "ready" => Some(pod.ready.value.clone()),
        "up_to_date" => Some(pod.up_to_date.to_string()),
        "available" => Some(pod.available.to_string()),
        "age" => Some(pod.age.clone()),
        _ => None,
    }
}

fn get_ready(row: &Value) -> ProcessedStatus {
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

    ProcessedStatus {
        symbol,
        value,
        sort_by,
    }
}
