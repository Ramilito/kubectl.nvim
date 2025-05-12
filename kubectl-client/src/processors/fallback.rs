use k8s_openapi::{
    apiextensions_apiserver::pkg::apis::apiextensions::v1::CustomResourceDefinition, serde_json,
};
use kube::{
    api::{DynamicObject, GroupVersionKind, ListParams, ResourceExt},
    discovery::{Discovery, Scope},
    Api,
};
use mlua::prelude::*;
use serde_json_path::JsonPath;
use std::collections::HashMap;

use super::processor::Processor;
use crate::{
    cmd::utils::dynamic_api,
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
    ) -> LuaResult<Vec<Self::Row>> {
        Err(LuaError::external("use process_fallback"))
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
        with_client(move |client| async move {
            let crd_api: Api<CustomResourceDefinition> = Api::all(client.clone());
            let crd = crd_api.get(&name).await.map_err(LuaError::external)?;
            let version = crd
                .spec
                .versions
                .iter()
                .find(|v| v.served)
                .ok_or_else(|| LuaError::external("No served version"))?;

            let discovery = Discovery::new(client.clone())
                .filter(&[&crd.spec.group])
                .run()
                .await
                .map_err(LuaError::external)?;

            let gvk = GroupVersionKind {
                group: crd.spec.group.clone(),
                version: version.name.clone(),
                kind: crd.spec.names.kind.clone(),
            };
            let (ar, caps) = discovery
                .resolve_gvk(&gvk)
                .ok_or_else(|| LuaError::external(format!("Unable to resolve GVK: {gvk:?}")))?;

            let namespaced = matches!(caps.scope, Scope::Namespaced);
            let api: Api<DynamicObject> = dynamic_api(ar, caps, client, ns.as_deref(), false);

            let items = api
                .list(&ListParams::default())
                .await
                .map_err(LuaError::external)?
                .items;

            let cols: Vec<PrinterCol> = version
                .additional_printer_columns
                .as_ref()
                .map(|v| {
                    v.iter()
                        .map(|c| PrinterCol {
                            name: c.name.clone(),
                            json_path: c.json_path.clone(),
                        })
                        .collect()
                })
                .unwrap_or_default();

            let runtime = RuntimeFallbackProcessor { cols: cols.clone(), namespaced };
            let rows_vec = runtime.process(
                &items,
                sort_by.clone(),
                sort_order.clone(),
                filter.clone(),
                filter_label.clone(),
            )?;
            let rows_lua = lua.to_value(&rows_vec)?;

            let mut headers: Vec<String> = if namespaced {
                vec!["NAMESPACE".into(), "NAME".into()]
            } else {
                vec!["NAME".into()]
            };
            headers.push("AGE".into());
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
