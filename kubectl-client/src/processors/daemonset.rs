use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::api::apps::v1::DaemonSet;
use k8s_openapi::serde_json::{from_value, to_value};
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct DaemonsetProcessed {
    namespace: String,
    name: String,
    desired: i64,
    current: i64,
    ready: FieldValue,
    #[serde(rename = "up-to-date")]
    up_to_date: i64,
    available: i64,
    #[serde(rename = "node selector")]
    node_selector: i64,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct DaemonsetProcessor;

impl Processor for DaemonsetProcessor {
    type Row = DaemonsetProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let ds: DaemonSet =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;

        let namespace = ds.metadata.namespace.clone().unwrap_or_default();
        let name = ds.metadata.name.clone().unwrap_or_default();

        let desired = ds
            .status
            .as_ref()
            .map(|s| s.desired_number_scheduled)
            .unwrap_or(0) as i64;

        let current = ds
            .status
            .as_ref()
            .map(|s| s.current_number_scheduled)
            .unwrap_or(0) as i64;

        let up_to_date = ds
            .status
            .as_ref()
            .and_then(|s| s.updated_number_scheduled)
            .unwrap_or(0) as i64;

        let available = ds
            .status
            .as_ref()
            .and_then(|s| s.number_available)
            .unwrap_or(0) as i64;

        let ready = get_ready_from_daemonset(&ds);

        let node_selector = ds
            .spec
            .as_ref()
            .and_then(|s| s.template.spec.as_ref())
            .and_then(|ps| ps.node_selector.as_ref())
            .map(|ns| ns.len() as i64)
            .unwrap_or(0);

        let age = self.get_age(obj);

        Ok(DaemonsetProcessed {
            namespace,
            name,
            desired,
            current,
            ready,
            up_to_date,
            available,
            node_selector,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "name" => Some(row.name.clone()),
            "desired" => Some(row.desired.to_string()),
            "current" => Some(row.current.to_string()),
            "ready" => Some(row.ready.value.clone()),
            "up-to-date" => Some(row.up_to_date.to_string()),
            "available" => Some(row.available.to_string()),
            "node selector" => Some(row.node_selector.to_string()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn get_ready_from_daemonset(ds: &DaemonSet) -> FieldValue {
    let ready = ds.status.as_ref().map(|s| s.number_ready).unwrap_or(0) as u64;

    let desired = ds
        .status
        .as_ref()
        .map(|s| s.desired_number_scheduled)
        .unwrap_or(0) as u64;

    let symbol = if ready == desired {
        "KubectlNote"
    } else {
        "KubectlDeprecated"
    }
    .to_string();

    let value = format!("{}/{}", ready, desired);
    let sort_by = (ready * 1001) + desired;

    FieldValue {
        symbol: Some(symbol),
        value,
        sort_by: Some(sort_by as usize),
    }
}
