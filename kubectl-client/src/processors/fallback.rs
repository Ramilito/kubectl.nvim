use k8s_openapi::{
    apiextensions_apiserver::pkg::apis::apiextensions::v1::CustomResourceDefinition, serde_json,
};
use kube::{
    api::{DynamicObject, GroupVersionKind, ListParams, ResourceExt},
    discovery::{pinned_kind, Scope},
    Api,
};
use mlua::prelude::*;
use serde_json_path::JsonPath;
use std::collections::{HashMap, HashSet};
use tokio::try_join;

use super::processor::Processor;
use crate::{
    cmd::utils::dynamic_api,
    structs::Gvk,
    utils::{AccessorMode, FieldValue},
    with_client,
};

#[derive(Debug, Clone)]
struct PrinterCol {
    name: String,
    json_path: String,
}

#[derive(Debug, Clone)]
struct RuntimeFallbackProcessor {
    cols: Vec<PrinterCol>,
    namespaced: bool,
}

#[derive(Debug, Clone, serde::Serialize)]
struct FallbackRow {
    namespace: Option<String>,
    name: String,
    age: FieldValue,
    #[serde(flatten)]
    extra: HashMap<String, FieldValue>,
}

impl Processor for RuntimeFallbackProcessor {
    type Row = FallbackRow;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let item_json = serde_json::to_value(obj).map_err(LuaError::external)?;

        let mut extra = HashMap::<String, FieldValue>::new();
        for col in &self.cols {
            let raw_val = JsonPath::parse(&fix_crd_path(&col.json_path))
                .ok()
                .and_then(|p| p.query(&item_json).all().first().cloned());

            let str_val = raw_val
                .as_ref()
                .and_then(|v| v.as_str().map(str::to_string))
                .unwrap_or_else(|| raw_val.map(|v| v.to_string()).unwrap_or_default());

            extra.insert(
                col.name.to_lowercase(),
                FieldValue {
                    value: str_val,
                    symbol: None,
                    sort_by: None,
                },
            );
        }

        Ok(FallbackRow {
            namespace: if self.namespaced {
                Some(obj.namespace().unwrap_or_default())
            } else {
                None
            },
            name: obj.name_any(),
            age: self.get_age(obj),
            extra,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "age"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => row.namespace.clone(),
            "name" => Some(row.name.clone()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            other => row.extra.get(other).and_then(|f| match mode {
                AccessorMode::Sort => f.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(f.value.clone()),
            }),
        })
    }
}

#[derive(Debug, Clone, Default)]
pub struct FallbackProcessor;

impl Processor for FallbackProcessor {
    type Row = (); // never used

    fn build_row(&self, _obj: &DynamicObject) -> LuaResult<Self::Row> {
        Err(LuaError::external("use process_fallback"))
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &[]
    }

    fn field_accessor(
        &self,
        _mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String>> {
        Box::new(|_, _| None)
    }

    fn process(
        &self,
        _items: &[DynamicObject],
        _sort_by: Option<String>,
        _sort_order: Option<String>,
        _filter: Option<String>,
        _filter_label: Option<Vec<String>>,
        _filter_key: Option<String>,
    ) -> LuaResult<Vec<Self::Row>> {
        Err(LuaError::external("use process_fallback"))
    }

    #[tracing::instrument]
    fn process_fallback(
        &self,
        lua: &Lua,
        gvk: Gvk,
        ns: Option<String>,
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
        filter_label: Option<Vec<String>>,
        filter_key: Option<String>,
    ) -> LuaResult<mlua::Value> {
        with_client(move |client| async move {
            let gvk = GroupVersionKind {
                group: gvk.g,
                version: gvk.v,
                kind: gvk.k.to_string(),
            };

            let (ar, caps) = pinned_kind(&client, &gvk)
                .await
                .map_err(|e| LuaError::external(e.to_string()))?;

            let api: Api<DynamicObject> = dynamic_api(
                ar.clone(),
                caps.clone(),
                client.clone(),
                ns.as_deref(),
                false,
            );
            let crd_api: Api<CustomResourceDefinition> = Api::all(client.clone());
            let crd_name = format!("{}.{}", ar.plural, gvk.group);

            let lp = ListParams::default();
            let (crd_opt, list) = try_join!(crd_api.get_opt(&crd_name), api.list(&lp),)
                .map_err(LuaError::external)?;

            let mut cols: Vec<PrinterCol> = if let Some(crd) = crd_opt {
                crd.spec
                    .versions
                    .iter()
                    .find(|v| v.served && v.name == gvk.version)
                    .and_then(|v| v.additional_printer_columns.as_ref())
                    .map(|v| {
                        v.iter()
                            .map(|c| PrinterCol {
                                name: c.name.clone(),
                                json_path: c.json_path.clone(),
                            })
                            .collect()
                    })
                    .unwrap_or_default()
            } else {
                Vec::new()
            };

            let canonical: &[&str] = if matches!(caps.scope, Scope::Namespaced) {
                &["NAMESPACE", "NAME"]
            } else {
                &["NAME"]
            };

            let mut seen: HashSet<String> = canonical.iter().map(|s| s.to_string()).collect();

            cols.retain(|c| {
                let up = c.name.to_uppercase();
                if seen.contains(&up) {
                    false
                } else {
                    seen.insert(up);
                    true
                }
            });

            let items = list.items;
            let namespaced = matches!(caps.scope, Scope::Namespaced);
            let runtime = RuntimeFallbackProcessor {
                cols: cols.clone(),
                namespaced,
            };

            let rows_vec = runtime.process(
                &items,
                sort_by.clone(),
                sort_order.clone(),
                filter.clone(),
                filter_label.clone(),
                filter_key.clone(),
            )?;
            let rows_lua = lua.to_value(&rows_vec)?;

            let mut headers: Vec<String> = canonical.iter().map(|s| s.to_string()).collect();
            headers.extend(cols.iter().map(|c| c.name.to_uppercase()));

            let headers_lua = lua.to_value(&headers)?;
            let tbl = lua.create_table()?;
            tbl.set("headers", headers_lua)?;
            tbl.set("rows", rows_lua)?;
            Ok(mlua::Value::Table(tbl))
        })
    }
}

fn fix_crd_path(raw: &str) -> String {
    if raw.starts_with('.') {
        format!("${raw}")
    } else {
        raw.to_string()
    }
}
