use chrono::{Duration, Utc};
use kube::api::DynamicObject;
use mlua::prelude::*;
use rayon::prelude::*;
use std::fmt::Debug;

use crate::{
    events::symbols,
    filter::filter_dynamic,
    sort::sort_dynamic,
    structs::Gvk,
    utils::{time_since, AccessorMode, FieldValue},
};

type FieldAccessorFn<'a, R> = Box<dyn Fn(&R, &str) -> Option<String> + 'a>;

pub trait Processor: Debug + Send + Sync {
    type Row: Debug + Clone + Send + Sync + serde::Serialize;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row>;

    fn filterable_fields(&self) -> &'static [&'static str];

    fn field_accessor(&self, mode: AccessorMode) -> FieldAccessorFn<'_, Self::Row>;

    fn labels_match(obj: &DynamicObject, wanted: &[(&str, &str)]) -> bool {
        match &obj.metadata.labels {
            Some(map) => wanted
                .iter()
                .all(|(k, v)| map.get(*k).map(|vv| vv == v).unwrap_or(false)),
            None => wanted.is_empty(),
        }
    }

    fn json_value_at<'a>(obj: &'a DynamicObject, path: &str) -> Option<&'a str> {
        if let Some(key) = path.strip_prefix("metadata.labels.") {
            return obj.metadata.labels.as_ref()?.get(key).map(String::as_str);
        }
        if path == "metadata.name" {
            return obj.metadata.name.as_deref();
        }
        if path == "metadata.namespace" {
            return obj.metadata.namespace.as_deref();
        }
        if let Some(field) = path.strip_prefix("metadata.ownerReferences.") {
            return obj
                .metadata
                .owner_references
                .as_ref()?
                .iter()
                .find_map(|r| match field {
                    "kind" => Some(r.kind.as_str()),
                    "name" => Some(r.name.as_str()),
                    "uid" => Some(r.uid.as_str()),
                    "apiVersion" => Some(r.api_version.as_str()),
                    _ => None,
                });
        }

        let mut segs = path.split('.');
        let top_key = segs.next()?;
        let mut cur = obj.data.get(top_key)?;
        for s in segs {
            cur = cur.get(s)?;
        }
        cur.as_str()
    }

    #[tracing::instrument(skip(self, items), fields(item_count = items.len()))]
    fn process(
        &self,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
        filter_label: Option<Vec<String>>,
        filter_key: Option<String>,
    ) -> LuaResult<Vec<Self::Row>> {
        let parsed: Vec<(&str, &str)> = filter_label
            .as_deref()
            .unwrap_or(&[])
            .iter()
            .filter_map(|s| s.split_once('='))
            .collect();

        let key_filters: Vec<(String, String)> = filter_key
            .as_deref()
            .map(|s| {
                s.split([',', ' '])
                    .filter_map(|kv| kv.split_once('='))
                    .map(|(p, v)| (p.to_string(), v.to_string()))
                    .collect()
            })
            .unwrap_or_default();

        let mut rows: Vec<Self::Row> = items
            .par_iter()
            .filter(|obj| Self::labels_match(obj, &parsed))
            .filter(|obj| {
                key_filters.iter().all(|(path, expect)| {
                    Self::json_value_at(obj, path).is_some_and(|v| v == expect)
                })
            })
            .map(|obj| self.build_row(obj).map_err(|e| e.to_string()))
            .collect::<Result<Vec<_>, _>>()
            .map_err(LuaError::external)?;

        sort_dynamic(
            &mut rows,
            sort_by,
            sort_order,
            self.field_accessor(AccessorMode::Sort),
        );

        if let Some(ref query) = filter {
            rows = filter_dynamic(
                &rows,
                query,
                self.filterable_fields(),
                self.field_accessor(AccessorMode::Filter),
            )
            .into_iter()
            .cloned()
            .collect();
        }

        Ok(rows)
    }

    fn get_age(&self, obj: &DynamicObject) -> FieldValue {
        let mut age = FieldValue {
            value: String::new(),
            ..Default::default()
        };

        if let Some(ts) = obj.metadata.creation_timestamp.as_ref() {
            age.value = time_since(&ts.0.to_rfc3339()).to_string();
            age.sort_by = Some(ts.0.timestamp().max(0) as usize);
            let ten_minutes = Duration::minutes(10);
            let age_duration = Utc::now().signed_duration_since(ts.0);
            if age_duration < ten_minutes {
                age.symbol = Some(symbols().success.clone());
            }
        }

        age
    }

    fn ip_to_u32(&self, ip: &str) -> Option<usize> {
        let octets: Vec<&str> = ip.split('.').collect();
        if octets.len() != 4 {
            return None;
        }
        let mut num = 0;
        for octet in octets {
            let val: usize = octet.parse().ok()?;
            num = (num << 8) | val;
        }
        Some(num)
    }
    fn process_fallback(
        &self,
        _lua: &Lua,
        _gvk: Gvk,
        _ns: Option<String>,
        _sort_by: Option<String>,
        _sort_order: Option<String>,
        _filter: Option<String>,
        _filter_label: Option<Vec<String>>,
        _filter_key: Option<String>,
    ) -> LuaResult<mlua::Value> {
        Err(LuaError::external("Not implemented for this processor"))
    }
}
