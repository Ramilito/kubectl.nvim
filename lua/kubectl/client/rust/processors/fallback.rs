use k8s_openapi::{
    apiextensions_apiserver::pkg::apis::apiextensions::v1::CustomResourceDefinition, serde_json,
};
use kube::{
    api::{DynamicObject, GroupVersionKind, ListParams, ResourceExt},
    discovery::{Discovery, Scope},
    Api,
};
use mlua::prelude::*;
use serde_json::{json, Value};
use serde_json_path::JsonPath;
use tokio::runtime::Runtime;

use super::processor::Processor;
use crate::{
    cmd::utils::dynamic_api,
    utils::{sort_dynamic, AccessorMode},
    CLIENT_INSTANCE, RUNTIME,
};

pub type FallbackRow = Value;

#[derive(Debug, Clone)]
pub struct FallbackProcessor;

impl Processor for FallbackProcessor {
    type Row = FallbackRow;

    fn build_row(&self, _lua: &Lua, _obj: &DynamicObject) -> LuaResult<Self::Row> {
        Err(LuaError::external(
            "FallbackProcessor does not implement `process`",
        ))
    }
    fn filterable_fields(&self) -> &'static [&'static str] {
        &[]
    }
    fn field_accessor(
        &self,
        _mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(|_, _| None)
    }
    fn process(
        &self,
        _lua: &Lua,
        _items: &[DynamicObject],
        _sort_by: Option<String>,
        _sort_order: Option<String>,
        _filter: Option<String>,
    ) -> LuaResult<mlua::Value> {
        Err(LuaError::external(
            "FallbackProcessor does not implement `process`",
        ))
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
        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("create Tokio runtime"));

        rt.block_on(async move {
            let client = CLIENT_INSTANCE
                .lock()
                .map_err(|_| LuaError::RuntimeError("client lock poisoned".into()))?
                .as_ref()
                .ok_or_else(|| LuaError::RuntimeError("client not initialised".into()))?
                .clone();

            let crd_api: Api<CustomResourceDefinition> = Api::all(client.clone());
            let crd = crd_api.get(&name).await.map_err(LuaError::external)?;
            let version_info = crd
                .spec
                .versions
                .iter()
                .find(|v| v.served)
                .ok_or_else(|| LuaError::external("No served version found in CRD"))?;

            let discovery = Discovery::new(client.clone())
                .filter(&[&crd.spec.group])
                .run()
                .await
                .map_err(LuaError::external)?;

            let gvk = GroupVersionKind {
                group: crd.spec.group.clone(),
                version: version_info.name.clone(),
                kind: crd.spec.names.kind.clone(),
            };

            let (ar, caps) = discovery
                .resolve_gvk(&gvk)
                .ok_or_else(|| LuaError::external(format!("Unable to resolve GVK: {gvk:?}")))?;

            let namespaced = matches!(caps.scope, Scope::Namespaced);
            let api: Api<DynamicObject> = dynamic_api(ar, caps, client, ns.as_deref(), false);

            let cr_list = api
                .list(&ListParams::default())
                .await
                .map_err(LuaError::external)?;

            let (headers, mut rows) = build_table_rows(&cr_list.items, version_info, namespaced)?;

            sort_dynamic(
                &mut rows,
                sort_by,
                sort_order,
                field_accessor(AccessorMode::Sort),
            );

            let output = json!({
                "headers": headers,
                "rows": rows
            });
            lua.to_value(&output)
        })
    }
}

fn build_table_rows(
    items: &[DynamicObject],
    version_info: &k8s_openapi::apiextensions_apiserver::pkg::apis::apiextensions::v1::CustomResourceDefinitionVersion,
    namespaced: bool,
) -> LuaResult<(Vec<String>, Vec<Value>)> {
    let columns = version_info.additional_printer_columns.as_ref();

    if let Some(cols) = columns {
        // ── CRD provides printer columns ──────────────────────────────
        let headers: Vec<String> = {
            let base = if namespaced {
                vec!["NAMESPACE", "NAME"]
            } else {
                vec!["NAME"]
            };
            base.into_iter()
                .map(str::to_string)
                .chain(cols.iter().map(|c| c.name.to_uppercase()))
                .collect()
        };

        let default_val = Value::String("<none>".into());
        let mut rows = Vec::with_capacity(items.len());

        for item in items {
            let item_json = serde_json::to_value(item).map_err(LuaError::external)?;
            let mut map = serde_json::Map::new();

            if namespaced {
                map.insert(
                    "namespace".into(),
                    Value::String(item.namespace().unwrap_or_default()),
                );
            }
            map.insert("name".into(), Value::String(item.name_any()));

            for col in cols {
                let path = fix_crd_path(&col.json_path);
                let val = JsonPath::parse(&path)
                    .ok()
                    .and_then(|p| p.query(&item_json).all().first().cloned())
                    .unwrap_or(&default_val);
                map.insert(col.name.to_lowercase(), val.clone());
            }
            rows.push(Value::Object(map));
        }
        Ok((headers, rows))
    } else {
        // ── fall-back: namespace, name, age ───────────────────────────
        let headers = vec!["NAMESPACE", "NAME", "AGE"]
            .into_iter()
            .map(str::to_string)
            .collect();
        let mut rows = Vec::with_capacity(items.len());

        for item in items {
            let mut map = serde_json::Map::new();
            map.insert(
                "namespace".into(),
                Value::String(item.namespace().unwrap_or_default()),
            );
            map.insert("name".into(), Value::String(item.name_any()));

            let creation_ts = item
                .metadata
                .creation_timestamp
                .as_ref()
                .map(|t| t.0.to_rfc3339())
                .unwrap_or_default();
            let age = if creation_ts.is_empty() {
                "".into()
            } else {
                crate::utils::time_since(&creation_ts)
            };
            map.insert("age".into(), Value::String(age));

            rows.push(Value::Object(map));
        }
        Ok((headers, rows))
    }
}

/// accessor used by `sort_dynamic`
fn field_accessor(_mode: AccessorMode) -> impl Fn(&Value, &str) -> Option<String> {
    |item, field| {
        if let Value::Object(map) = item {
            map.get(field).map(|v| match v {
                Value::String(s) => s.clone(),
                other => other.to_string(),
            })
        } else {
            None
        }
    }
}

/// CRD JSONPaths sometimes start with '.' — `serde_json_path` expects '$'
fn fix_crd_path(raw: &str) -> String {
    if raw.starts_with('.') {
        format!("${raw}")
    } else {
        raw.to_string()
    }
}
