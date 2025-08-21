use k8s_openapi::api::core::v1::{Event as CoreEvent, ObjectReference};
use k8s_openapi::api::events::v1::Event;
use k8s_openapi::chrono::{DateTime, Utc};
use kube::api::DynamicObject;
use mlua::prelude::*;

use crate::processors::processor::Processor;
use crate::utils::{time_since, AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct EventProcessed {
    namespace: String,
    #[serde(rename = "last-seen")]
    last_seen: FieldValue,
    #[serde(rename = "type")]
    type_: FieldValue,
    reason: String,
    object: String,
    count: FieldValue,
    message: String,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct EventProcessor;

impl Processor for EventProcessor {
    type Row = EventProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        use k8s_openapi::serde_json::{from_value, to_value};

        let v = to_value(obj).map_err(LuaError::external)?;
        if let Ok(ev) = from_value::<Event>(v.clone()) {
            let namespace = ev.metadata.namespace.clone().unwrap_or_default();

            let (object_kind, object_name) = ev
                .regarding
                .as_ref()
                .map(|r: &ObjectReference| {
                    (
                        r.kind.clone().unwrap_or_default(),
                        r.name.clone().unwrap_or_default(),
                    )
                })
                .unwrap_or_default();

            let last_seen = last_seen_field(
                ev.series.as_ref().map(|s| s.last_observed_time.0.to_utc()),
                ev.event_time.as_ref().map(|t| t.0),
                ev.metadata.creation_timestamp.as_ref().map(|t| t.0),
                None,
            );

            let count_i = ev.series.as_ref().map(|s| s.count).unwrap_or(1);
            let count = count_field(count_i);
            let mut message = ev.note.clone().unwrap_or_default();
            let mess_length = message.trim_end_matches(&['\r', '\n'][..]).len();
            message.truncate(mess_length);

            Ok(EventProcessed {
                namespace,
                last_seen,
                type_: text_field(ev.type_.clone().unwrap_or_default()),
                reason: ev.reason.clone().unwrap_or_default(),
                object: object_string(object_kind, object_name),
                count,
                message,
            })
        } else {
            let ev: CoreEvent = from_value(v).map_err(LuaError::external)?;

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
            let count = count_field(count_i);
            let mut message = ev.message.clone().unwrap_or_default();
            let mess_length = message.trim_end_matches(&['\r', '\n'][..]).len();
            message.truncate(mess_length);

            Ok(EventProcessed {
                namespace,
                last_seen,
                type_: text_field(ev.type_.clone().unwrap_or_default()),
                reason: ev.reason.clone().unwrap_or_default(),
                object: object_string(object_kind, object_name),
                count,
                message,
            })
        }
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &[
            "namespace",
            "last_seen",
            "type",
            "reason",
            "object",
            "count",
            "message",
        ]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "last_seen" => match mode {
                AccessorMode::Sort => Some(row.last_seen.sort_by?.to_string()),
                AccessorMode::Filter => Some(row.last_seen.value.clone()),
            },
            "type" => Some(row.type_.value.clone()),
            "reason" => Some(row.reason.clone()),
            "object" => Some(row.object.clone()),
            "count" => match mode {
                AccessorMode::Sort => Some(row.count.sort_by?.to_string()),
                AccessorMode::Filter => Some(row.count.value.clone()),
            },
            "message" => Some(row.message.clone()),
            _ => None,
        })
    }
}

/* -------------------- helpers -------------------- */

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

fn text_field(s: String) -> FieldValue {
    FieldValue {
        value: s,
        ..Default::default()
    }
}

fn count_field(n: i32) -> FieldValue {
    FieldValue {
        value: n.to_string(),
        sort_by: Some(n.try_into().unwrap()),
        ..Default::default()
    }
}

fn last_seen_field(
    series_last: Option<DateTime<Utc>>,
    event_time: Option<DateTime<Utc>>,
    created: Option<DateTime<Utc>>,
    last_timestamp: Option<DateTime<Utc>>,
) -> FieldValue {
    let ts = series_last.or(event_time).or(last_timestamp).or(created);

    let mut f = FieldValue::default();
    if let Some(t) = ts {
        f.value = time_since(&t.to_rfc3339());
        f.sort_by = Some(t.timestamp_millis().try_into().unwrap());
    }
    f
}
