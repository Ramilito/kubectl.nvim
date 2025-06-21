use chrono::{Duration, Utc};
use k8s_openapi::{apimachinery::pkg::version::Info, serde_json};
use kube::api::DynamicObject;
use mlua::{prelude::*, Lua};
use rayon::prelude::*;
use std::fmt::Debug;
use tracing::{info, span, Level};

use crate::{
    events::symbols,
    filter::filter_dynamic,
    sort::sort_dynamic,
    utils::{time_since, AccessorMode, FieldValue},
};

/// Object-safe facade that hides the `Row` type.
pub trait DynProcessor: Send + Sync {
    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
        filter_label: Option<Vec<String>>,
    ) -> LuaResult<String>;

    fn process_fallback(
        &self,
        lua: &Lua,
        name: String,
        ns: Option<String>,
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
        filter_label: Option<Vec<String>>,
    ) -> LuaResult<mlua::Value>;
}
/* blanket-impl:  every real Processor automatically becomes a DynProcessor */
impl<T: Processor> DynProcessor for T {
    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
        filter_label: Option<Vec<String>>,
    ) -> LuaResult<String> {
        let processed = Processor::process(self, items, sort_by, sort_order, filter, filter_label)?;

        let json_span = span!(Level::INFO, "json_convert").entered();

        let mut buf = Vec::with_capacity(processed.len().saturating_mul(512).max(4 * 1024));
        serde_json::to_writer(&mut buf, &processed)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        let json_str = lua.create_string(&buf)?.to_str()?.to_owned();
        json_span.record("out_bytes", json_str.len() as u64);
        json_span.exit();
        Ok(json_str)
    }

    fn process_fallback(
        &self,
        lua: &Lua,
        name: String,
        ns: Option<String>,
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
        filter_label: Option<Vec<String>>,
    ) -> LuaResult<mlua::Value> {
        Processor::process_fallback(
            self,
            lua,
            name,
            ns,
            sort_by,
            sort_order,
            filter,
            filter_label,
        )
    }
}

pub trait Processor: Debug + Send + Sync {
    type Row: Debug + Clone + Send + Sync + serde::Serialize;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row>;

    fn filterable_fields(&self) -> &'static [&'static str];

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_>;

    fn labels_match(obj: &DynamicObject, wanted: &[(&str, &str)]) -> bool {
        match &obj.metadata.labels {
            Some(map) => wanted
                .iter()
                .all(|(k, v)| map.get(*k).map(|vv| vv == v).unwrap_or(false)),
            None => wanted.is_empty(),
        }
    }

    #[tracing::instrument(skip(self, items), fields(item_count = items.len()))]
    fn process(
        &self,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
        filter_label: Option<Vec<String>>,
    ) -> LuaResult<Vec<Self::Row>> {
        let parsed: Vec<(&str, &str)> = filter_label
            .as_deref()
            .unwrap_or(&[])
            .iter()
            .filter_map(|s| s.split_once('='))
            .collect();

        let mut rows: Vec<Self::Row> = items
            .par_iter()
            .filter(|obj| Self::labels_match(obj, &parsed))
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
        _name: String,
        _ns: Option<String>,
        _sort_by: Option<String>,
        _sort_order: Option<String>,
        _filter: Option<String>,
        _filter_label: Option<Vec<String>>,
    ) -> LuaResult<mlua::Value> {
        Err(LuaError::external("Not implemented for this processor"))
    }
}
