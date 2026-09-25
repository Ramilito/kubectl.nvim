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
use std::sync::{Arc, OnceLock, RwLock};
use std::time::{Duration, Instant};
use tokio::try_join;

use super::processor::{FilterParams, Processor};
use crate::{
    cmd::utils::dynamic_api,
    store,
    structs::Gvk,
    utils::{AccessorMode, FieldValue},
    with_client,
};

#[derive(Debug, Clone)]
struct PrinterCol {
    name: String,
    json_path: String,
}

const COLUMNS_TTL: Duration = Duration::from_secs(60);
static COLUMN_CACHE: OnceLock<ColumnCache> = OnceLock::new();

pub(crate) fn clear_column_cache() {
    if let Some(cache) = COLUMN_CACHE.get() {
        cache.clear();
    }
}

struct CachedColumns {
    expires_at: Instant,
    by_version: HashMap<String, Vec<PrinterCol>>,
}

#[derive(Default)]
struct ColumnCache {
    entries: RwLock<HashMap<String, CachedColumns>>,
}

impl ColumnCache {
    fn clear(&self) {
        if let Ok(mut entries) = self.entries.write() {
            entries.clear();
        }
    }

    fn cached_columns(&self, crd_name: &str, version: &str) -> Option<Vec<PrinterCol>> {
        let entries = self.entries.read().ok()?;
        let entry = entries.get(crd_name)?;
        if Instant::now() >= entry.expires_at {
            return None;
        }
        Some(entry.by_version.get(version).cloned().unwrap_or_default())
    }

    async fn load_columns(
        &self,
        api: &Api<CustomResourceDefinition>,
        crd_name: &str,
        version: &str,
    ) -> LuaResult<Vec<PrinterCol>> {
        if let Some(cols) = self.cached_columns(crd_name, version) {
            return Ok(cols);
        }

        // A single GET supplies every version. Only a successful response (including
        // 404) is cached; permission and transport errors remain errors.
        let crd = api.get_opt(crd_name).await.map_err(LuaError::external)?;
        let mut by_version = HashMap::new();
        if let Some(crd) = crd {
            for version in crd.spec.versions.into_iter().filter(|v| v.served) {
                let cols = version
                    .additional_printer_columns
                    .unwrap_or_default()
                    .into_iter()
                    .map(|col| PrinterCol {
                        name: col.name,
                        json_path: col.json_path,
                    })
                    .collect();
                by_version.insert(version.name, cols);
            }
        }

        let cols = by_version.get(version).cloned().unwrap_or_default();
        let entry = CachedColumns {
            expires_at: Instant::now() + COLUMNS_TTL,
            by_version,
        };
        if let Ok(mut entries) = self.entries.write() {
            entries.insert(crd_name.to_owned(), entry);
        }
        Ok(cols)
    }
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
    type Resource = serde_json::Value;

    fn build_row(&self, item_json: &Self::Resource, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let mut extra = HashMap::<String, FieldValue>::new();
        for col in &self.cols {
            let raw_val = JsonPath::parse(&fix_crd_path(&col.json_path))
                .ok()
                .and_then(|p| p.query(item_json).all().first().cloned());

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
                    hint: None,
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
    type Resource = (); // never used

    fn build_row(&self, _resource: &Self::Resource, _obj: &DynamicObject) -> LuaResult<Self::Row> {
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
        _items: &[Arc<DynamicObject>],
        _params: &FilterParams,
    ) -> LuaResult<Vec<Self::Row>> {
        Err(LuaError::external("use process_fallback"))
    }

    #[tracing::instrument(skip_all)]
    fn process_fallback(
        &self,
        lua: &Lua,
        gvk: Gvk,
        ns: Option<String>,
        params: &FilterParams,
    ) -> LuaResult<mlua::Value> {
        let params = params.clone();
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

            let cached = store::get(&gvk.kind, ns.clone()).unwrap_or_default();
            let load_items = async {
                if !cached.is_empty() {
                    return Ok(cached);
                }
                let list = api
                    .list(&ListParams::default())
                    .await
                    .map_err(LuaError::external)?;
                Ok(list.items.into_iter().map(Arc::new).collect::<Vec<_>>())
            };
            let load_columns = COLUMN_CACHE.get_or_init(ColumnCache::default).load_columns(
                &crd_api,
                &crd_name,
                &gvk.version,
            );
            let (mut cols, items) = try_join!(load_columns, load_items)?;

            let namespaced = matches!(caps.scope, Scope::Namespaced);
            let canonical: &[&str] = if namespaced {
                &["NAMESPACE", "NAME"]
            } else {
                &["NAME"]
            };

            let mut seen: HashSet<String> = canonical.iter().map(|s| s.to_string()).collect();

            cols.retain(|column| seen.insert(column.name.to_uppercase()));

            let mut headers: Vec<String> = canonical.iter().map(|s| s.to_string()).collect();
            headers.extend(cols.iter().map(|c| c.name.to_uppercase()));

            let runtime = RuntimeFallbackProcessor { cols, namespaced };

            let rows_vec = runtime.process(&items, &params)?;
            let rows_lua = lua.to_value(&rows_vec)?;

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
