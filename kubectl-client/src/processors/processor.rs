use jiff::Timestamp;
use kube::api::DynamicObject;
use mlua::prelude::*;
use rayon::prelude::*;
use std::fmt::Debug;

use crate::{
    events::symbols,
    filter::filter_dynamic,
    sort::sort_dynamic,
    structs::Gvk,
    utils::{time_since_jiff, AccessorMode, FieldValue},
};

type FieldAccessorFn<'a, R> = Box<dyn Fn(&R, &str) -> Option<String> + 'a>;

/// Parameters for filtering and sorting resource rows.
/// Consolidates 5 separate parameters into a single struct.
#[derive(Debug, Clone, Default)]
pub struct FilterParams {
    pub sort_by: Option<String>,
    pub sort_order: Option<String>,
    pub filter: Option<String>,
    pub filter_label: Option<Vec<String>>,
    pub filter_key: Option<String>,
}

impl FilterParams {
    /// Parse label filters from "key=value" strings into tuples.
    pub fn parse_label_filters(&self) -> Vec<(&str, &str)> {
        self.filter_label
            .as_deref()
            .unwrap_or(&[])
            .iter()
            .filter_map(|s| s.split_once('='))
            .collect()
    }

    /// Parse key filters from comma/space-separated "path=value" string.
    pub fn parse_key_filters(&self) -> Vec<(String, String)> {
        self.filter_key
            .as_deref()
            .map(|s| {
                s.split([',', ' '])
                    .filter_map(|kv| kv.split_once('='))
                    .map(|(p, v)| (p.to_string(), v.to_string()))
                    .collect()
            })
            .unwrap_or_default()
    }
}

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
    fn process(&self, items: &[DynamicObject], params: &FilterParams) -> LuaResult<Vec<Self::Row>> {
        let label_filters = params.parse_label_filters();
        let key_filters = params.parse_key_filters();

        let mut rows: Vec<Self::Row> = items
            .par_iter()
            .filter(|obj| Self::labels_match(obj, &label_filters))
            .filter(|obj| Self::key_filters_match(obj, &key_filters))
            .map(|obj| self.build_row(obj).map_err(|e| e.to_string()))
            .collect::<Result<Vec<_>, _>>()
            .map_err(LuaError::external)?;

        sort_dynamic(
            &mut rows,
            params.sort_by.clone(),
            params.sort_order.clone(),
            self.field_accessor(AccessorMode::Sort),
        );

        if let Some(ref query) = params.filter {
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

    fn key_filters_match(obj: &DynamicObject, filters: &[(String, String)]) -> bool {
        filters
            .iter()
            .all(|(path, expect)| Self::json_value_at(obj, path).is_some_and(|v| v == expect))
    }

    fn get_age(&self, obj: &DynamicObject) -> FieldValue {
        let mut age = FieldValue {
            value: String::new(),
            ..Default::default()
        };

        if let Some(ts) = obj.metadata.creation_timestamp.as_ref() {
            age.value = time_since_jiff(&ts.0);
            age.sort_by = Some(ts.0.as_second().max(0) as usize);
            if let Ok(age_span) = Timestamp::now().since(ts.0) {
                // Check if age is less than 10 minutes (600 seconds)
                if age_span.get_seconds() < 600 {
                    age.symbol = Some(symbols().success.clone());
                }
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
        _params: &FilterParams,
    ) -> LuaResult<mlua::Value> {
        Err(LuaError::external("Not implemented for this processor"))
    }
}
