use jiff::Timestamp;
use k8s_openapi::api::core::v1::{Event as CoreEvent, ObjectReference};
use kube::api::DynamicObject;
use mlua::prelude::*;

use crate::events::color_status;
use crate::processors::processor::Processor;
use crate::utils::{pad_key, time_since_jiff, AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct EventProcessed {
    namespace: String,
    #[serde(rename = "last seen")]
    last_seen: FieldValue,
    #[serde(rename = "type")]
    type_: FieldValue,
    reason: String,
    object: String,
    count: FieldValue,
    message: String,
    name: String,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct EventProcessor;

impl Processor for EventProcessor {
    type Row = EventProcessed;
    type Resource = CoreEvent;

    fn build_row(&self, ev: &Self::Resource, _obj: &DynamicObject) -> LuaResult<Self::Row> {

        let namespace = ev.metadata.namespace.clone().unwrap_or_default();

        let (object_kind, object_name) = {
            let r: &ObjectReference = &ev.involved_object;
            (
                r.kind.clone().unwrap_or_default(),
                r.name.clone().unwrap_or_default(),
            )
        };
        let last_seen = last_seen_field(
            ev.series
                .as_ref()
                .and_then(|s| s.last_observed_time.as_ref().map(|t| t.0)),
            ev.event_time.as_ref().map(|t| t.0),
            ev.metadata.creation_timestamp.as_ref().map(|t| t.0),
            ev.last_timestamp.as_ref().map(|t| t.0),
        );

        let count_i = ev.count.unwrap_or(1);

        let count = FieldValue {
            value: count_i.to_string(),
            sort_by: Some(count_i.try_into().unwrap()),
            ..Default::default()
        };
        let mut message = ev.message.clone().unwrap_or_default();
        message = message.replace("\n", "");

        let name = ev.metadata.name.clone().unwrap_or_default();
        Ok(EventProcessed {
            namespace,
            last_seen,
            type_: FieldValue {
                value: ev.type_.clone().unwrap_or_default(),
                symbol: Some(color_status(&ev.type_.clone().unwrap_or_default())),
                ..Default::default()
            },
            reason: ev.reason.clone().unwrap_or_default(),
            object: object_string(object_kind, object_name),
            count,
            message,
            name,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &[
            "namespace",
            "last seen",
            "type",
            "reason",
            "object",
            "count",
            "message",
            "name",
        ]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "last seen" => match mode {
                AccessorMode::Sort => Some(row.last_seen.sort_by?.to_string()),
                AccessorMode::Filter => Some(row.last_seen.value.clone()),
            },
            "type" => match mode {
                AccessorMode::Sort => Some(row.type_.value.to_string()),
                AccessorMode::Filter => Some(row.type_.value.clone()),
            },
            "reason" => Some(row.reason.clone()),
            "object" => Some(row.object.clone()),
            "count" => match mode {
                AccessorMode::Sort => row.count.sort_by.map(pad_key),
                AccessorMode::Filter => Some(row.count.value.clone()),
            },
            "message" => Some(row.message.clone()),
            "name" => Some(row.name.clone()),
            _ => None,
        })
    }
}

fn object_string(kind: String, name: String) -> String {
    let k = if kind.is_empty() {
        String::from("?")
    } else {
        kind.to_lowercase()
    };
    if name.is_empty() {
        k
    } else {
        format!("{}/{}", k, name)
    }
}

fn last_seen_field(
    series_last: Option<Timestamp>,
    event_time: Option<Timestamp>,
    created: Option<Timestamp>,
    last_timestamp: Option<Timestamp>,
) -> FieldValue {
    let ts = series_last.or(event_time).or(last_timestamp).or(created);

    let mut f = FieldValue::default();
    if let Some(t) = ts {
        f.value = time_since_jiff(&t);
        f.sort_by = Some(t.as_millisecond().max(0) as usize);
    }
    f
}
