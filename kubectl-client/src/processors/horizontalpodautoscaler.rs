use k8s_openapi::api::autoscaling::v2::HorizontalPodAutoscaler;
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
    targets: FieldValue,
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
            "minpods" => Some(row.minpods.clone()),
            "maxpods" => Some(row.maxpods.clone()),
            "replicas" => Some(row.replicas.clone()),
            "targets" => match mode {
                AccessorMode::Sort => row.targets.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.targets.value.clone()),
            },
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

use crate::events::{color_status, symbols};
use k8s_openapi::api::autoscaling::v2::{MetricTarget, MetricValueStatus};
use std::collections::HashMap;

fn summarize_metrics(hpa: &HorizontalPodAutoscaler) -> FieldValue {
    let mut target_map: HashMap<String, String> = HashMap::new();
    if let Some(spec) = &hpa.spec {
        if let Some(mets) = &spec.metrics {
            for m in mets {
                if let Some(res) = &m.resource {
                    if let Some(t) = metric_target_to_string(&res.target) {
                        target_map.insert(res.name.clone(), t);
                    }
                }
            }
        }
    }

    let mut entries: BTreeMap<String, (String, String)> = BTreeMap::new();
    if let Some(status) = &hpa.status {
        if let Some(mets) = &status.current_metrics {
            for m in mets {
                if let Some(res) = &m.resource {
                    let cur =
                        metric_value_to_string(&res.current).unwrap_or_else(|| "<none>".into());
                    let tgt = target_map
                        .remove(&res.name)
                        .unwrap_or_else(|| "<none>".into());
                    entries.insert(res.name.clone(), (cur, tgt));
                }
            }
        }
    }

    let mut ordered = vec!["cpu".to_string(), "memory".to_string()];
    ordered.extend(
        entries
            .keys()
            .filter(|k| *k != "cpu" && *k != "memory")
            .cloned(),
    );

    let mut pieces = Vec::new();
    let mut worst = 0_u8;

    for key in ordered {
        if let Some((cur, tgt)) = entries.get(&key) {
            pieces.push(format!("{key}: {cur}/{tgt}"));
            if let (Some(c), Some(t)) = (percent(cur), percent(tgt)) {
                let ratio = c / t.max(1.0);
                if ratio >= 1.0 {
                    worst = worst.max(2);
                } else if ratio >= 0.8 {
                    worst = worst.max(1);
                }
            }
        }
    }

    let symbol = match worst {
        2 => Some(color_status("Error")),
        1 => Some(color_status("Warning")),
        _ => Some(symbols().note.clone()),
    };

    FieldValue {
        value: if pieces.is_empty() {
            "<none>".into()
        } else {
            pieces.join(", ")
        },
        symbol,
        ..Default::default()
    }
}

fn metric_target_to_string(t: &MetricTarget) -> Option<String> {
    t.average_utilization
        .map(|u| format!("{u}%"))
        .or_else(|| t.average_value.as_ref().map(|q| q.0.clone()))
        .or_else(|| t.value.as_ref().map(|q| q.0.clone()))
}

fn metric_value_to_string(v: &MetricValueStatus) -> Option<String> {
    v.average_utilization
        .map(|u| format!("{u}%"))
        .or_else(|| v.average_value.as_ref().map(|q| q.0.clone()))
        .or_else(|| v.value.as_ref().map(|q| q.0.clone()))
}

fn percent(s: &str) -> Option<f64> {
    if let Some(stripped) = s.strip_suffix('%') {
        stripped.trim().parse::<f64>().ok()
    } else {
        None
    }
}
