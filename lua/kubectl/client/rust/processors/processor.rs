use kube::api::DynamicObject;
use mlua::{prelude::*, Lua};

use crate::utils::{filter_dynamic, sort_dynamic, time_since, AccessorMode, FieldValue};

/// Object-safe facade that hides the `Row` type.
pub trait DynProcessor: Send + Sync {
    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
    ) -> LuaResult<mlua::Value>;

    fn process_fallback(
        &self,
        lua: &Lua,
        name: String,
        ns: Option<String>,
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
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
    ) -> LuaResult<mlua::Value> {
        Processor::process(self, lua, items, sort_by, sort_order, filter)
    }

    fn process_fallback(
        &self,
        lua: &Lua,
        name: String,
        ns: Option<String>,
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
    ) -> LuaResult<mlua::Value> {
        Processor::process_fallback(self, lua, name, ns, sort_by, sort_order, filter)
    }
}

pub trait Processor: Send + Sync {
    type Row: Clone + serde::Serialize;
    fn build_row(&self, lua: &Lua, obj: &DynamicObject) -> LuaResult<Self::Row>;
    fn filterable_fields(&self) -> &'static [&'static str];

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_>;

    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
    ) -> LuaResult<mlua::Value> {
        let mut rows: Vec<Self::Row> = items
            .iter()
            .map(|obj| self.build_row(lua, obj))
            .collect::<LuaResult<_>>()?;

        sort_dynamic(
            &mut rows,
            sort_by,
            sort_order,
            self.field_accessor(AccessorMode::Sort),
        );

        let rows = if let Some(ref query) = filter {
            filter_dynamic(
                &rows,
                query,
                self.filterable_fields(),
                self.field_accessor(AccessorMode::Filter),
            )
            .into_iter()
            .cloned()
            .collect()
        } else {
            rows
        };

        lua.to_value(&rows)
    }

    fn get_age(&self, pod_val: &DynamicObject) -> FieldValue {
        let mut age = FieldValue {
            value: "".to_string(),
            ..Default::default()
        };
        let creation_ts = pod_val
            .metadata
            .creation_timestamp
            .as_ref()
            .map(|t| t.0.to_rfc3339())
            .unwrap_or_default();

        age.value = if !creation_ts.is_empty() {
            time_since(&creation_ts).to_string()
        } else {
            "".to_string()
        };

        age.sort_by = Some(
            pod_val
                .metadata
                .creation_timestamp
                .as_ref()
                .map(|time| time.0.timestamp())
                .expect("Times")
                .max(0) as usize,
        );
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
    ) -> LuaResult<mlua::Value> {
        Err(LuaError::external("Not implemented for this processor"))
    }
}
