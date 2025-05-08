use k8s_openapi::api::autoscaling::v2::{
    ContainerResourceMetricStatus, HorizontalPodAutoscaler, MetricStatus, ResourceMetricStatus,
};
use k8s_openapi::apimachinery::pkg::api::resource::Quantity;
use k8s_openapi::serde_json::{from_value, to_value};
use kube::api::DynamicObject;
use mlua::prelude::*;
use std::collections::BTreeMap;

use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct HorizontalPodAutoscalerProcessed {
    namespace: String,
    name: String,
    reference: String,
    targets: String,
    minpods: String,
    maxpods: String,
    replicas: String,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct HorizontalPodAutoscalerProcessor;

impl Processor for HorizontalPodAutoscalerProcessor {
    type Row = HorizontalPodAutoscalerProcessed;

    fn build_row(&self, _lua: &Lua, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let hpa: HorizontalPodAutoscaler =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;

        let (namespace, name) = (
            hpa.metadata.namespace.clone().unwrap_or_default(),
            hpa.metadata.name.clone().unwrap_or_default(),
        );
        let (minpods, maxpods, reference) = hpa
            .spec
            .as_ref()
            .map(|s| {
                let ref_str = format!("{}/{}", s.scale_target_ref.kind, s.scale_target_ref.name);
                (
                    s.min_replicas
                        .map(|m| m.to_string())
                        .unwrap_or_else(|| "<none>".into()),
                    s.max_replicas.to_string(),
                    ref_str,
                )
            })
            .unwrap_or_else(|| ("<none>".into(), "<none>".into(), "<none>".into()));

        let replicas = hpa
            .status
            .as_ref()
            .and_then(|st| st.current_replicas.map(|n| n.to_string()))
            .unwrap_or_else(|| "<none>".into());

        let targets = summarize_metrics(&hpa);
        let age = self.get_age(obj);

        Ok(HorizontalPodAutoscalerProcessed {
            namespace,
            name,
            reference,
            targets,
            minpods,
            maxpods,
            replicas,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "reference", "targets"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "name" => Some(row.name.clone()),
            "reference" => Some(row.reference.clone()),
            "targets" => Some(row.targets.clone()),
            "minpods" => Some(row.minpods.clone()),
            "maxpods" => Some(row.maxpods.clone()),
            "replicas" => Some(row.replicas.clone()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn summarize_metrics(hpa: &HorizontalPodAutoscaler) -> String {
    let mut targets: BTreeMap<String, String> = BTreeMap::new();
    if let Some(spec) = &hpa.spec {
        if let Some(ms) = &spec.metrics {
            for m in ms {
                if let Some(r) = &m.resource {
                    let tgt = r
                        .target
                        .average_utilization
                        .map(|u| format!("{u}%"))
                        .or_else(|| r.target.average_value.as_ref().map(|q| q.0.clone()))
                        .or_else(|| r.target.value.as_ref().map(|q| q.0.clone()))
                        .unwrap_or_else(|| "<none>".into());
                    targets.insert(r.name.clone(), tgt);
                }
            }
        }
    }

    let mut out = Vec::new();
    if let Some(status) = &hpa.status {
        if let Some(ms) = &status.current_metrics {
            for m in ms {
                if let Some(r) = &m.resource {
                    let cur = r
                        .current
                        .average_utilization
                        .map(|u| format!("{u}%"))
                        .or_else(|| r.current.average_value.as_ref().map(|q| q.0.clone()))
                        .or_else(|| r.current.value.as_ref().map(|q| q.0.clone()))
                        .unwrap_or_else(|| "<none>".into());

                    let name = r.name.clone(); // e.g. "cpu" or "memory"
                    let tgt = targets.remove(&name).unwrap_or_else(|| "<none>".into());
                    out.push(format!("{name}: {cur}/{tgt}"));
                }
            }
        }
    }
    if out.is_empty() {
        "<none>".into()
    } else {
        out.join(", ")
    }
}

fn metric_status_value(ms: &MetricStatus) -> Option<String> {
    if let Some(r) = &ms.resource {
        return value_from_resource(r);
    }
    if let Some(p) = &ms.pods {
        return quantity_to_string(p.current.average_value.as_ref());
    }
    if let Some(o) = &ms.object {
        return quantity_to_string(o.current.value.as_ref());
    }
    if let Some(e) = &ms.external {
        return quantity_to_string(e.current.value.as_ref());
    }
    if let Some(c) = &ms.container_resource {
        return value_from_resource(c);
    }
    None
}

fn value_from_resource<R>(res: &R) -> Option<String>
where
    R: ResourceMetricLike,
{
    quantity_to_string(res.current_average_value())
        .or_else(|| res.current_average_utilization().map(|u| format!("{u}%")))
        .or_else(|| quantity_to_string(res.current_value()))
}

trait ResourceMetricLike {
    fn current_average_value(&self) -> Option<&Quantity>;
    fn current_average_utilization(&self) -> Option<i32>;
    fn current_value(&self) -> Option<&Quantity>;
}

impl ResourceMetricLike for ResourceMetricStatus {
    fn current_average_value(&self) -> Option<&Quantity> {
        self.current.average_value.as_ref()
    }
    fn current_average_utilization(&self) -> Option<i32> {
        self.current.average_utilization
    }
    fn current_value(&self) -> Option<&Quantity> {
        self.current.value.as_ref()
    }
}

impl ResourceMetricLike for ContainerResourceMetricStatus {
    fn current_average_value(&self) -> Option<&Quantity> {
        self.current.average_value.as_ref()
    }
    fn current_average_utilization(&self) -> Option<i32> {
        self.current.average_utilization
    }
    fn current_value(&self) -> Option<&Quantity> {
        self.current.value.as_ref()
    }
}

fn quantity_to_string(q: Option<&Quantity>) -> Option<String> {
    q.map(|q| q.0.clone())
}
