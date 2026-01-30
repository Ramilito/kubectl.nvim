use crate::events::symbols;
use crate::processors::processor::{dynamic_to_typed, Processor};
use crate::utils::{AccessorMode, FieldValue};
use jiff::Timestamp;
use k8s_openapi::api::batch::v1::Job;
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct JobProcessed {
    namespace: String,
    name: String,
    completions: FieldValue,
    duration: String,
    containers: String,
    images: String,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct JobProcessor;

impl Processor for JobProcessor {
    type Row = JobProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let job: Job = dynamic_to_typed(obj)?;

        let namespace = job.metadata.namespace.clone().unwrap_or_default();
        let name = job.metadata.name.clone().unwrap_or_default();

        let desired = job.spec.as_ref().and_then(|s| s.completions).unwrap_or(0);
        let succeeded = job.status.as_ref().and_then(|s| s.succeeded).unwrap_or(0);
        let completions = FieldValue {
            value: format!("{succeeded}/{desired}"),
            symbol: Some(if succeeded == desired {
                symbols().note.clone()
            } else {
                symbols().deprecated.clone()
            }),
            sort_by: Some(succeeded as usize),
            hint: None,
        };

        let duration = {
            let create_ts = job
                .metadata
                .creation_timestamp
                .as_ref()
                .map(|t| t.0)
                .unwrap_or_else(Timestamp::now);
            let end_ts = job
                .status
                .as_ref()
                .and_then(|s| s.completion_time.as_ref().map(|t| t.0))
                .unwrap_or_else(Timestamp::now);

            human_duration_jiff(create_ts, end_ts)
        };

        let containers = container_data(&job, |c| c.name.clone());
        let images = container_data(&job, |c| c.image.clone().unwrap_or_default());
        let age = self.get_age(obj);

        Ok(JobProcessed {
            namespace,
            name,
            completions,
            duration,
            containers,
            images,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "containers", "images", "duration"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "name" => Some(row.name.clone()),
            "completions" => Some(row.completions.value.clone()),
            "duration" => Some(row.duration.clone()),
            "containers" => Some(row.containers.clone()),
            "images" => Some(row.images.clone()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn container_data<F>(job: &Job, map: F) -> String
where
    F: Fn(&k8s_openapi::api::core::v1::Container) -> String,
{
    job.spec
        .as_ref()
        .and_then(|s| s.template.spec.as_ref())
        .map(|pod| {
            pod.containers
                .iter()
                .map(&map)
                .collect::<Vec<_>>()
                .join(",")
        })
        .unwrap_or_default()
}

fn human_duration_jiff(start: Timestamp, end: Timestamp) -> String {
    let secs = end.since(start).map(|s| s.get_seconds()).unwrap_or(0);
    if secs < 60 {
        format!("{secs}s")
    } else if secs < 3600 {
        format!("{}m", secs / 60)
    } else if secs < 86_400 {
        format!("{}h", secs / 3600)
    } else {
        format!("{}d", secs / 86_400)
    }
}
