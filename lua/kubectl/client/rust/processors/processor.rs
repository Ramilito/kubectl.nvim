use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

use crate::utils::time_since;
use crate::utils::FieldValue;

pub trait Processor: Send + Sync {
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
        _lua: &Lua,
        _name: String,
        _ns: Option<String>,
        _sort_by: Option<String>,
        _sort_order: Option<String>,
        _filter: Option<String>,
    ) -> LuaResult<mlua::Value> {
        Err(LuaError::external("Not implemented for this processor"))
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
}
