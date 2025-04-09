use super::processor::Processor;
use crate::cmd::utils::dynamic_api;
use crate::{CLIENT_INSTANCE, RUNTIME};
use k8s_openapi::apiextensions_apiserver::pkg::apis::apiextensions::v1::CustomResourceDefinition;
use k8s_openapi::serde_json;
use kube::api::GroupVersionKind;
use kube::discovery::Discovery;
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

            let api: Api<DynamicObject> = dynamic_api(ar, caps, client, ns.as_deref(), false);

            let cr_list = api
                .list(&ListParams::default())
                .await
                .map_err(LuaError::external)?;

            let columns = version_info
                .additional_printer_columns
                .as_ref()
                .ok_or_else(|| LuaError::external("No additionalPrinterColumns found"))?;

            let headers: Vec<String> = std::iter::once("NAME".to_string())
                .chain(columns.iter().map(|col| col.name.to_uppercase()))
                .collect();

            let mut rows = Vec::new();
            for item in cr_list.items {
                let mut item_data = serde_json::Map::new();
                let item_json = serde_json::to_value(&item).map_err(LuaError::external)?;

                item_data.insert("name".to_string(), Value::String(item.name_any()));
                let value = &Value::String("<none>".into());
                for col in columns {
                    let path = fix_crd_path(&col.json_path);
                    let value = JsonPath::parse(&path)
                        .ok()
                        .and_then(|p| p.query(&item_json).all().first().cloned())
                        .unwrap_or(value);
                    item_data.insert(col.name.to_lowercase(), value.clone());
                }

                rows.push(Value::Object(item_data));
            }

            let output = json!({
                "headers": headers,
                "rows": rows
            });

            Ok(lua.to_value(&output)?)
        };

        rt.block_on(fut)
    }
}

fn fix_crd_path(raw: &str) -> String {
    if raw.starts_with('.') {
        format!("${}", raw)
    } else {
        raw.to_string()
    }
}
