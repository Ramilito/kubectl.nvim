use crate::processors::processor::Processor;
use crate::utils::{filter_dynamic, sort_dynamic, AccessorMode, FieldValue};
use k8s_openapi::api::apps::v1::Deployment;
use k8s_openapi::serde_json::{self};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

#[derive(Debug, Clone, serde::Serialize)]
pub struct DeploymentProcessed {
    namespace: String,
    name: String,
    ready: FieldValue,
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
            let deployment: Deployment = serde_json::from_value(
                serde_json::to_value(obj).expect("Failed to convert DynamicObject to JSON Value"),
            )
            .expect("Failed to convert JSON Value into Deployment");

            let namespace = deployment.metadata.namespace.clone().unwrap_or_default();
            let name = deployment.metadata.name.clone().unwrap_or_default();

            let up_to_date = deployment
                .status
                .as_ref()
                .and_then(|s| s.updated_replicas)
                .unwrap_or(0) as i64;

            let available = deployment
                .status
                .as_ref()
                .and_then(|s| s.available_replicas)
                .unwrap_or(0) as i64;

            let age = self.get_age(obj);
            let ready = get_ready_from_deployment(&deployment);

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
            AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
            AccessorMode::Filter => Some(resource.age.value.clone()),
        },
        _ => None,
    }
}
fn get_ready_from_deployment(deployment: &Deployment) -> FieldValue {
    let available = deployment
        .status
        .as_ref()
        .and_then(|s| s.available_replicas)
        .unwrap_or(0) as u64;
    let unavailable = deployment
        .status
        .as_ref()
        .and_then(|s| s.unavailable_replicas)
        .unwrap_or(0) as u64;
    let replicas = deployment
        .spec
        .as_ref()
        .and_then(|s| s.replicas)
        .or_else(|| deployment.status.as_ref().and_then(|s| s.replicas))
        .unwrap_or(0) as u64;

    let symbol = if available == replicas && unavailable == 0 {
        "KubectlNote".to_string()
    } else {
        "KubectlDeprecated".to_string()
    };

    let value = format!("{}/{}", available, replicas);
    let sort_by = (available * 1001) + replicas;

    FieldValue {
        symbol: Some(symbol),
        value,
        sort_by: Some(sort_by as usize),
    }
}
