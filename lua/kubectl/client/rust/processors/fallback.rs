use super::processor::Processor;
use crate::cmd::utils::dynamic_api;
use crate::utils::{sort_dynamic, AccessorMode};
use crate::{CLIENT_INSTANCE, RUNTIME};
use k8s_openapi::apiextensions_apiserver::pkg::apis::apiextensions::v1::CustomResourceDefinition;
use k8s_openapi::serde_json;
use kube::api::GroupVersionKind;
use kube::discovery::{Discovery, Scope};
use kube::{
    api::{DynamicObject, ListParams, ResourceExt},
    Api,
};
use mlua::prelude::*;
use serde_json::{json, Value};
use serde_json_path::JsonPath;
use tokio::runtime::Runtime;

#[derive(Debug, Clone, serde::Serialize)]
pub struct FallbackProcessed {
    data: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone)]
pub struct FallbackProcessor;

impl Processor for FallbackProcessor {
    fn process(
        &self,
        _lua: &Lua,
        _items: &[DynamicObject],
        _sort_by: Option<String>,
        _sort_order: Option<String>,
        _filter: Option<String>,
    ) -> LuaResult<mlua::Value> {
        Err(LuaError::external("Not implemented for this processor"))
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
        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

        let fut = async move {
            let client = CLIENT_INSTANCE
                .lock()
                .map_err(|_| {
                    LuaError::RuntimeError("Failed to acquire lock on client instance".into())
                })?
                .as_ref()
                .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
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
                .ok_or_else(|| LuaError::external(format!("Unable to resolve GVK: {:?}", gvk)))?;

            let include_namespace = matches!(caps.scope.clone(), Scope::Namespaced);
            let api: Api<DynamicObject> = dynamic_api(ar, caps, client, ns.as_deref(), false);

            let cr_list = api
                .list(&ListParams::default())
                .await
                .map_err(LuaError::external)?;

            let columns = version_info.additional_printer_columns.as_ref();

            let (headers, mut rows) = if let Some(cols) = columns {
                let headers: Vec<String> = if include_namespace {
                    std::iter::once("NAMESPACE".to_string())
                        .chain(std::iter::once("NAME".to_string()))
                        .chain(cols.iter().map(|c| c.name.to_uppercase()))
                        .collect()
                } else {
                    std::iter::once("NAME".to_string())
                        .chain(cols.iter().map(|c| c.name.to_uppercase()))
                        .collect()
                };

                let default_value = Value::String("<none>".into());
                let mut rows = Vec::new();
                for item in cr_list.items {
                    let item_json = serde_json::to_value(&item).map_err(LuaError::external)?;
                    let mut map = serde_json::Map::new();
                    if include_namespace {
                        map.insert(
                            "namespace".to_string(),
                            Value::String(item.clone().metadata.namespace.unwrap()),
                        );
                    }
                    map.insert("name".to_string(), Value::String(item.name_any()));

                    for col in cols {
                        let path = fix_crd_path(&col.json_path);
                        map.insert(
                            col.name.to_lowercase(),
                            JsonPath::parse(&path)
                                .ok()
                                .and_then(|p| p.query(&item_json).all().first().cloned())
                                .unwrap_or(&default_value.clone())
                                .clone(),
                        );
                    }
                    rows.push(Value::Object(map));
                }
                (headers, rows)
            } else {
                let headers = vec![
                    "NAMESPACE".to_string(),
                    "NAME".to_string(),
                    "AGE".to_string(),
                ];
                let mut rows = Vec::new();

                for item in cr_list.items {
                    let mut map = serde_json::Map::new();
                    // "NAMESPACE"
                    map.insert(
                        "namespace".into(),
                        Value::String(item.namespace().unwrap_or_default()),
                    );
                    // "NAME"
                    map.insert("name".into(), Value::String(item.name_any()));
                    // "AGE" (based on creationTimestamp)
                    let creation_ts = item
                        .metadata
                        .creation_timestamp
                        .map(|t| t.0.to_rfc3339())
                        .unwrap_or_default();
                    let age_str = if !creation_ts.is_empty() {
                        crate::utils::time_since(&creation_ts)
                    } else {
                        "".into()
                    };
                    map.insert("age".into(), Value::String(age_str));
                    rows.push(Value::Object(map));
                }
                (headers, rows)
            };

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
        };

        rt.block_on(fut)
    }
}

fn field_accessor(_mode: AccessorMode) -> impl Fn(&Value, &str) -> Option<String> {
    move |item: &Value, field: &str| {
        if let Value::Object(map) = item {
            map.get(field).and_then(|v| {
                if v.is_string() {
                    v.as_str().map(|s| s.to_string())
                } else {
                    Some(v.to_string())
                }
            })
        } else {
            None
        }
    }
}

fn fix_crd_path(raw: &str) -> String {
    if raw.starts_with('.') {
        format!("${}", raw)
    } else {
        raw.to_string()
    }
}
