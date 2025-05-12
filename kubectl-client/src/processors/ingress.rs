use k8s_openapi::api::networking::v1::HTTPIngressPath;
use k8s_openapi::api::networking::v1::Ingress;
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;
use std::collections::BTreeSet;

use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct IngressProcessed {
    namespace: String,
    name: String,
    class: FieldValue,
    hosts: FieldValue,
    address: FieldValue,
    ports: FieldValue,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct IngressProcessor;

impl Processor for IngressProcessor {
    type Row = IngressProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        use k8s_openapi::serde_json::{from_value, to_value};

        let ingress: Ingress =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;

        Ok(IngressProcessed {
            namespace: ingress.metadata.namespace.clone().unwrap_or_default(),
            name: ingress.metadata.name.clone().unwrap_or_default(),
            class: get_class(&ingress),
            hosts: get_hosts(&ingress),
            address: get_address(&ingress),
            ports: get_ports(&ingress),
            age: self.get_age(obj),
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "class", "hosts", "address", "ports"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |resource, field| match field {
            "namespace" => Some(resource.namespace.clone()),
            "name" => Some(resource.name.clone()),
            "class" => match mode {
                AccessorMode::Sort => resource.class.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(resource.class.value.clone()),
            },
            "hosts" => match mode {
                AccessorMode::Sort => resource.hosts.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(resource.hosts.value.clone()),
            },
            "address" => match mode {
                AccessorMode::Sort => resource.address.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(resource.address.value.clone()),
            },
            "ports" => match mode {
                AccessorMode::Sort => resource.ports.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(resource.ports.value.clone()),
            },
            "age" => match mode {
                AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
                AccessorMode::Filter => Some(resource.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn get_ports(ing: &Ingress) -> FieldValue {
    let mut ports: BTreeSet<i32> = BTreeSet::new();

    if let Some(spec) = &ing.spec {
        if let Some(rules) = &spec.rules {
            for rule in rules {
                if let Some(http) = &rule.http {
                    for HTTPIngressPath { backend, .. } in &http.paths {
                        if let Some(svc) = &backend.service {
                            ports.insert(svc.port.as_ref().and_then(|p| p.number).unwrap_or(80));
                        }
                    }
                }
            }
        }
        if spec.tls.as_ref().map_or(false, |tls| !tls.is_empty()) {
            ports.insert(443);
        }
    }

    FieldValue {
        value: ports
            .into_iter()
            .map(|p| p.to_string())
            .collect::<Vec<_>>()
            .join(", "),
        ..Default::default()
    }
}

fn get_hosts(ing: &Ingress) -> FieldValue {
    let mut hosts = Vec::new();

    if let Some(spec) = &ing.spec {
        if let Some(rules) = &spec.rules {
            for rule in rules {
                if let Some(h) = &rule.host {
                    hosts.push(h.clone());
                }
            }
        }
    }

    let value = if hosts.len() > 4 {
        format!("{}, +{} more...", hosts[..4].join(", "), hosts.len() - 4)
    } else {
        hosts.join(", ")
    };

    FieldValue {
        value,
        ..Default::default()
    }
}

fn get_address(ing: &Ingress) -> FieldValue {
    let mut addrs = Vec::new();

    if let Some(status) = &ing.status {
        if let Some(lb) = &status.load_balancer {
            if let Some(ing_vec) = &lb.ingress {
                for item in ing_vec {
                    if let Some(h) = &item.hostname {
                        addrs.push(h.clone());
                    } else if let Some(ip) = &item.ip {
                        addrs.push(ip.clone());
                    }
                }
            }
        }
    }

    FieldValue {
        value: addrs.join(", "),
        ..Default::default()
    }
}

fn get_class(ing: &Ingress) -> FieldValue {
    let by_spec = ing.spec.as_ref().and_then(|s| s.ingress_class_name.clone());

    let by_annotation = ing
        .metadata
        .annotations
        .as_ref()
        .and_then(|a| a.get("kubernetes.io/ingress.class").cloned());

    FieldValue {
        value: by_spec.or(by_annotation).unwrap_or_default(),
        ..Default::default()
    }
}
