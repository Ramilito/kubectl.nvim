use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::api::core::v1::{Service, ServicePort};
use k8s_openapi::serde_json::{to_value, from_value};
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct ServiceProcessed {
    namespace: String,
    name: String,
    #[serde(rename = "type")]
    svc_type: FieldValue,
    #[serde(rename = "cluster-ip")]
    cluster_ip: String,
    #[serde(rename = "external-ip")]
    external_ip: String,
    ports: String,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct ServiceProcessor;

impl Processor for ServiceProcessor {
    type Row = ServiceProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let svc: Service = from_value(to_value(obj).map_err(LuaError::external)?)
            .map_err(LuaError::external)?;
        let namespace = svc.metadata.namespace.clone().unwrap_or_default();
        let name = svc.metadata.name.clone().unwrap_or_default();
        let svc_type = get_type(&svc);
        let cluster_ip = get_cluster_ip(&svc);
        let external_ip = get_external_ip(&svc);
        let ports = get_ports(&svc);
        let age = self.get_age(obj);
        Ok(ServiceProcessed {
            namespace,
            name,
            svc_type,
            cluster_ip,
            external_ip,
            ports,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "type", "cluster-ip", "external-ip", "ports"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "name" => Some(row.name.clone()),
            "type" => Some(row.svc_type.value.clone()),
            "cluster-ip" => Some(row.cluster_ip.clone()),
            "external-ip" => Some(row.external_ip.clone()),
            "ports" => Some(row.ports.clone()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn get_ports(svc: &Service) -> String {
    svc.spec
        .as_ref()
        .and_then(|s| s.ports.clone())
        .map(|ports: Vec<ServicePort>| {
            ports
                .iter()
                .map(|p| format!("{}/{}", p.port, p.protocol.clone().unwrap_or_default()))
                .collect::<Vec<_>>()
                .join(",")
        })
        .unwrap_or_default()
}

fn get_type(svc: &Service) -> FieldValue {
    let svc_type = svc
        .spec
        .as_ref()
        .and_then(|s| s.type_.clone())
        .unwrap_or_default();
    let (symbol, sort_by) = match svc_type.as_str() {
        "NodePort"     => ("KubectlDebug",   1),
        "LoadBalancer" => ("KubectlNote",    2),
        "ExternalName" => ("KubectlSuccess", 3),
        _              => ("",               0),
    };
    FieldValue {
        symbol: if symbol.is_empty() { None } else { Some(symbol.into()) },
        value: svc_type,
        sort_by: Some(sort_by),
        hint: None,
    }
}

fn get_cluster_ip(svc: &Service) -> String {
    let ip = svc
        .spec
        .as_ref()
        .and_then(|s| s.cluster_ip.clone())
        .unwrap_or_else(|| "<none>".into());
    if ip == "None" { "<none>".into() } else { ip }
}

fn lb_ingress_ips(svc: &Service) -> Vec<String> {
    svc.status
        .as_ref()
        .and_then(|st| st.load_balancer.as_ref())
        .and_then(|lb| lb.ingress.clone())
        .map(|ing| {
            ing.into_iter()
                .filter_map(|i| i.ip.or(i.hostname))
                .collect()
        })
        .unwrap_or_default()
}

fn get_external_ip(svc: &Service) -> String {
    let spec = match svc.spec.as_ref() {
        Some(s) => s,
        None => return "".into(),
    };
    match spec.type_.as_deref() {
        Some("ClusterIP") | None => "<none>".into(),
        Some("NodePort") => spec
            .external_ips
            .as_ref()
            .map(|v| v.join(","))
            .unwrap_or_else(|| "<none>".into()),
        Some("LoadBalancer") => {
            let mut ips = lb_ingress_ips(svc);
            if let Some(ext) = &spec.external_ips {
                ips.extend(ext.clone());
            }
            if ips.is_empty() { "<none>".into() } else { ips.join(",") }
        }
        Some("ExternalName") => spec.external_name.clone().unwrap_or_default(),
        _ => "".into(),
    }
}
