use crate::events::symbols;
use crate::processors::processor::{dynamic_to_typed, Processor};
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::api::apps::v1::ReplicaSet;
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct ReplicaSetProcessed {
    namespace: String,
    name: String,
    desired: FieldValue,
    current: FieldValue,
    ready: FieldValue,
    age: FieldValue,
    containers: String,
    images: String,
    selector: String,
}

#[derive(Debug, Clone)]
pub struct ReplicaSetProcessor;

impl Processor for ReplicaSetProcessor {
    type Row = ReplicaSetProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let rs: ReplicaSet = dynamic_to_typed(obj)?;

        let namespace = rs.metadata.namespace.clone().unwrap_or_default();
        let name = rs.metadata.name.clone().unwrap_or_default();

        let desired = rs.spec.as_ref().and_then(|s| s.replicas).unwrap_or(0);
        let current = rs
            .status
            .as_ref().map(|s| s.replicas)
            .unwrap_or(0);
        let ready = rs
            .status
            .as_ref()
            .and_then(|s| s.ready_replicas)
            .unwrap_or(0);

        let desired_fv = make_repl_field(desired, desired, true);
        let current_fv = make_repl_field(current, desired, false);
        let ready_fv = make_repl_field(ready, desired, false);

        let age = self.get_age(obj);
        let containers = container_names(&rs);
        let images = container_images(&rs);
        let selector = selectors(&rs);

        Ok(ReplicaSetProcessed {
            namespace,
            name,
            desired: desired_fv,
            current: current_fv,
            ready: ready_fv,
            age,
            containers,
            images,
            selector,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "containers", "images", "selector"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |r, f| match f {
            "namespace" => Some(r.namespace.clone()),
            "name" => Some(r.name.clone()),
            "desired" => Some(r.desired.value.clone()),
            "current" => Some(r.current.value.clone()),
            "ready" => Some(r.ready.value.clone()),
            "containers" => Some(r.containers.clone()),
            "images" => Some(r.images.clone()),
            "selector" => Some(r.selector.clone()),
            "age" => match mode {
                AccessorMode::Sort => r.age.sort_by.map(|n| n.to_string()),
                AccessorMode::Filter => Some(r.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn make_repl_field(value: i32, desired: i32, always_note: bool) -> FieldValue {
    let symbol = if always_note {
        symbols().note.clone()
    } else if value < desired {
        symbols().deprecated.clone()
    } else {
        symbols().note.clone()
    };
    FieldValue {
        value: value.to_string(),
        sort_by: Some(value as usize),
        symbol: Some(symbol),
        hint: None,
    }
}

fn selectors(rs: &ReplicaSet) -> String {
    rs.spec
        .as_ref()
        .and_then(|s| s.selector.match_labels.clone())
        .map(|m| {
            let mut v: Vec<_> = m.into_iter().map(|(k, v)| format!("{k}={v}")).collect();
            v.sort();
            v.join(",")
        })
        .unwrap_or_default()
}

fn container_names(rs: &ReplicaSet) -> String {
    rs.spec
        .as_ref()
        .and_then(|s| s.template.as_ref())
        .and_then(|tpl| tpl.spec.as_ref())
        .map(|pod| {
            pod.containers
                .iter()
                .map(|c| c.name.clone())
                .collect::<Vec<_>>()
                .join(",")
        })
        .unwrap_or_default()
}

fn container_images(rs: &ReplicaSet) -> String {
    rs.spec
        .as_ref()
        .and_then(|s| s.template.as_ref())
        .and_then(|tpl| tpl.spec.as_ref())
        .map(|pod| {
            pod.containers
                .iter()
                .filter_map(|c| c.image.clone())
                .collect::<Vec<_>>()
                .join(",")
        })
        .unwrap_or_default()
}
