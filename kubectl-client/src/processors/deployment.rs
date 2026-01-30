use crate::processors::processor::{dynamic_to_typed, Processor};
use crate::utils::{pad_key, AccessorMode, FieldValue};
use k8s_openapi::api::apps::v1::Deployment;
use kube::api::DynamicObject;
use mlua::prelude::*;

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

#[derive(Debug, Clone)]
pub struct DeploymentProcessor;

impl Processor for DeploymentProcessor {
    type Row = DeploymentProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let deployment: Deployment = dynamic_to_typed(obj)?;
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
        let ready = get_ready_from_deployment(&deployment);
        let age = self.get_age(obj);
        Ok(DeploymentProcessed {
            namespace,
            name,
            ready,
            up_to_date,
            available,
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
        Box::new(move |res, field| match field {
            "namespace" => Some(res.namespace.clone()),
            "name" => Some(res.name.clone()),
            "ready" => match mode {
                AccessorMode::Sort => res.ready.sort_by.map(pad_key),
                AccessorMode::Filter => Some(res.ready.value.clone()),
            },
            "up-to-date" => Some(res.up_to_date.to_string()),
            "available" => Some(res.available.to_string()),
            "age" => match mode {
                AccessorMode::Sort => res.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(res.age.value.clone()),
            },
            _ => None,
        })
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
        hint: None,
    }
}
