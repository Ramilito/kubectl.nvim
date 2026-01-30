use crate::events::symbols;
use crate::processors::processor::Processor;
use crate::utils::{time_since_jiff, AccessorMode, FieldValue};
use k8s_openapi::api::batch::v1::CronJob;
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct CronJobProcessed {
    namespace: String,
    name: String,
    schedule: String,
    suspend: FieldValue,
    active: FieldValue,
    #[serde(rename = "last schedule")]
    last_schedule: String,
    containers: String,
    images: String,
    selector: String,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct CronJobProcessor;

impl Processor for CronJobProcessor {
    type Row = CronJobProcessed;
    type Resource = CronJob;

    fn build_row(&self, cj: &Self::Resource, obj: &DynamicObject) -> LuaResult<Self::Row> {

        let namespace = cj.metadata.namespace.clone().unwrap_or_default();
        let name = cj.metadata.name.clone().unwrap_or_default();

        let schedule = cj
            .spec
            .as_ref()
            .map(|s| s.schedule.clone())
            .unwrap_or_default();

        let suspend_flag = cj.spec.as_ref().and_then(|s| s.suspend).unwrap_or(false);
        let suspend = FieldValue {
            value: suspend_flag.to_string(),
            symbol: Some(if suspend_flag {
                symbols().error.clone()
            } else {
                symbols().success.clone()
            }),
            ..Default::default()
        };

        let active_count = cj
            .status
            .as_ref()
            .and_then(|s| s.active.as_ref().map(|v| v.len()))
            .unwrap_or(0) as i32;
        let desired = 0; // CronJobs don't have desired replicas; colour purely informational
        let active = FieldValue {
            value: active_count.to_string(),
            sort_by: Some(active_count as usize),
            symbol: Some(if active_count > desired {
                symbols().note.clone()
            } else {
                symbols().deprecated.clone()
            }),
            hint: None,
        };

        let last_schedule = cj
            .status
            .as_ref()
            .and_then(|s| s.last_schedule_time.as_ref())
            .map(|t| time_since_jiff(&t.0))
            .unwrap_or_else(|| "<none>".into());

        let containers = fetch_container_data(&cj, true);
        let images = fetch_container_data(&cj, false);
        let selector = fetch_selector(&cj);
        let age = self.get_age(obj);

        Ok(CronJobProcessed {
            namespace,
            name,
            schedule,
            suspend,
            active,
            last_schedule,
            containers,
            images,
            selector,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &[
            "namespace",
            "name",
            "schedule",
            "containers",
            "images",
            "selector",
        ]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "name" => Some(row.name.clone()),
            "schedule" => Some(row.schedule.clone()),
            "suspend" => Some(row.suspend.value.clone()),
            "active" => Some(row.active.value.clone()),
            "last schedule" => Some(row.last_schedule.clone()),
            "containers" => Some(row.containers.clone()),
            "images" => Some(row.images.clone()),
            "selector" => Some(row.selector.clone()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn fetch_selector(cj: &CronJob) -> String {
    cj.spec
        .as_ref()
        .and_then(|t| t.job_template.spec.clone())
        .and_then(|s| s.selector.clone())
        .and_then(|sel| sel.match_labels.clone())
        .map(|m| {
            let mut v: Vec<String> = m.into_iter().map(|(k, v)| format!("{k}={v}")).collect();
            v.sort();
            v.join(",")
        })
        .unwrap_or_else(|| "<none>".into())
}

fn fetch_container_data(cj: &CronJob, want_names: bool) -> String {
    cj.spec
        .as_ref()
        .and_then(|s| s.job_template.spec.as_ref())
        .and_then(|js| js.template.spec.as_ref())
        .map(|pod| {
            pod.containers
                .iter()
                .map(|c| {
                    if want_names {
                        c.name.clone()
                    } else {
                        c.image.clone().unwrap_or_default()
                    }
                })
                .collect::<Vec<_>>()
                .join(",")
        })
        .unwrap_or_default()
}
