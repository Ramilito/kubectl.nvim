use crate::events::{color_status, symbols};
use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::api::core::v1::{Node, NodeCondition};
use k8s_openapi::serde_json::{from_value, to_value};
use kube::api::DynamicObject;
use mlua::prelude::*;
use std::collections::BTreeMap;

#[derive(Debug, Clone, serde::Serialize)]
pub struct NodeProcessed {
    name: String,
    status: FieldValue,
    roles: FieldValue,
    age: FieldValue,
    version: String,
    #[serde(rename = "os-image")]
    os_image: String,
    #[serde(rename = "internal-ip")]
    internal_ip: FieldValue,
    #[serde(rename = "external-ip")]
    external_ip: FieldValue,
}

#[derive(Debug, Clone)]
pub struct NodeProcessor;

impl Processor for NodeProcessor {
    type Row = NodeProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let node: Node =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;

        let name = node.metadata.name.clone().unwrap_or_default();
        let status = get_status(&node);
        let roles = get_roles(&node);
        let age = self.get_age(obj);

        let version = node
            .status
            .as_ref()
            .map(|s| s.node_info.as_ref().unwrap().kubelet_version.clone())
            .unwrap_or_default();

        let os_image = node
            .status
            .as_ref()
            .map(|s| s.node_info.as_ref().unwrap().os_image.clone())
            .unwrap_or_default();

        let (internal, external) = split_ips(&node);
        let internal_ip = FieldValue {
            value: internal.clone(),
            sort_by: self.ip_to_u32(&internal),
            ..Default::default()
        };
        let external_ip = FieldValue {
            value: external.clone(),
            sort_by: self.ip_to_u32(&external),
            ..Default::default()
        };

        Ok(NodeProcessed {
            name,
            status,
            roles,
            age,
            version,
            os_image,
            internal_ip,
            external_ip,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &[
            "name",
            "status",
            "roles",
            "version",
            "internal-ip",
            "external-ip",
        ]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "name" => Some(row.name.clone()),
            "status" => match mode {
                AccessorMode::Sort => Some(row.status.value.to_string()),
                AccessorMode::Filter => Some(row.status.value.clone()),
            },
            "roles" => Some(row.roles.value.clone()),
            "version" => Some(row.version.clone()),
            "internal-ip" => Some(row.internal_ip.value.clone()),
            "external-ip" => Some(row.external_ip.value.clone()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

pub fn get_status(node: &Node) -> FieldValue {
    let conditions: BTreeMap<_, _> = node
        .status
        .as_ref()
        .and_then(|s| s.conditions.as_ref())
        .map(|conds| conds.iter().map(|c| (c.type_.clone(), c)).collect())
        .unwrap_or_default();

    if node
        .spec
        .as_ref()
        .and_then(|s| s.unschedulable)
        .unwrap_or(false)
    {
        return FieldValue {
            symbol: Some(symbols().warning.clone()),
            value: "SchedulingDisabled".into(),
            ..Default::default()
        };
    }

    match conditions.get("Ready") {
        Some(NodeCondition { status: s, .. }) if s == "True" => FieldValue {
            symbol: Some(symbols().success.clone()),
            value: "Ready".into(),
            ..Default::default()
        },
        Some(_) => FieldValue {
            symbol: Some(color_status("NotReady")),
            value: "NotReady".into(),
            ..Default::default()
        },
        None => FieldValue {
            symbol: Some(color_status("Error")),
            value: "Unknown".into(),
            ..Default::default()
        },
    }
}

fn get_roles(node: &Node) -> FieldValue {
    let mut role = None;

    if let Some(labels) = &node.metadata.labels {
        for k in labels.keys() {
            if let Some(val) = k.strip_prefix("node-role.kubernetes.io/") {
                role = Some(val.to_string());
                break;
            }
            if k.ends_with("kubernetes.io/role") {
                role = labels.get(k).cloned();
                break;
            }
        }
    }

    FieldValue {
        value: role.unwrap_or_else(|| "<none>".into()),
        ..Default::default()
    }
}

fn split_ips(node: &Node) -> (String, String) {
    let mut internal = "<none>".to_string();
    let mut external = "<none>".to_string();

    if let Some(status) = &node.status {
        if let Some(addresses) = &status.addresses {
            for addr in addresses {
                match addr.type_.as_str() {
                    "InternalIP" => internal = addr.address.clone(),
                    "ExternalIP" => external = addr.address.clone(),
                    _ => {}
                }
            }
        }
    }
    (internal, external)
}
