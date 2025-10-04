use std::collections::{HashMap, HashSet};

use http::Uri;
use k8s_openapi::serde_json::{self};
use kube::{
    api::{ApiResource, DynamicObject, ListParams, ResourceExt, TypeMeta},
    core::GroupVersionKind,
    discovery::{verbs, ApiCapabilities, Discovery, Scope},
    error::DiscoveryError,
    Client, Error,
};
use mlua::prelude::*;
use mlua::Either;
use serde::Serialize;
use serde_json::{json, to_string};
use tokio::time::{timeout, Duration};
use tracing::{trace_span, warn, Instrument};

use super::utils::{dynamic_api, resolve_api_resource};
use crate::{
    store,
    structs::{GetServerRawArgs, GetSingleArgs},
    with_client,
};

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum OutputMode {
    Pretty,
    Yaml,
    Json,
}

impl OutputMode {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "yaml" => OutputMode::Yaml,
            "json" => OutputMode::Json,
            _ => OutputMode::Pretty,
        }
    }
    pub fn format(&self, obj: DynamicObject) -> String {
        match self {
            OutputMode::Yaml => serde_yaml::to_string(&obj)
                .unwrap_or_else(|e| format!("YAML formatting error: {}", e)),
            OutputMode::Pretty => serde_json::to_string_pretty(&obj)
                .unwrap_or_else(|e| format!("Pretty formatting error: {}", e)),
            OutputMode::Json => serde_json::to_string(&obj)
                .unwrap_or_else(|e| format!("JSON formatting error: {}", e)),
        }
    }
}

impl Default for OutputMode {
    fn default() -> Self {
        Self::Pretty
    }
}

#[tracing::instrument(skip(client))]
pub async fn get_resources_async(
    client: &Client,
    kind: String,
    group: Option<String>,
    version: Option<String>,
    namespace: Option<String>,
) -> Result<Vec<DynamicObject>, Error> {
    let (ar, caps) = if let (Some(g), Some(v)) = (group, version) {
        let gvk = GroupVersionKind::gvk(g.as_str(), v.as_str(), kind.as_str());
        kube::discovery::pinned_kind(client, &gvk).await?
    } else {
        let discovery = kube::discovery::Discovery::new(client.clone())
            .run()
            .await?;
        resolve_api_resource(&discovery, &kind).ok_or_else(|| {
            Error::Discovery(DiscoveryError::MissingResource(format!(
                "Resource not found in cluster: {kind}"
            )))
        })?
    };
    let ar_api_version = ar.api_version.clone();
    let ar_kind = ar.kind.clone();
    let api = dynamic_api(ar, caps, client.clone(), namespace.as_deref(), true);
    let mut list = api.list(&ListParams::default()).await?;

    for obj in &mut list.items {
        obj.managed_fields_mut().clear();
        obj.data["api_version"] = json!(ar_api_version.clone());
        if obj.types.is_none() {
            obj.types = Some(TypeMeta {
                kind: ar_kind.clone(),
                api_version: ar_api_version.clone(),
            });
        }
    }

    Ok(list.items)
}

#[tracing::instrument(skip(client))]
pub async fn get_resource_async(
    client: &Client,
    kind: String,
    group: Option<String>,
    version: Option<String>,
    name: String,
    namespace: Option<String>,
    output: Option<String>,
) -> LuaResult<String> {
    let output_mode = output
        .as_deref()
        .map(OutputMode::from_str)
        .unwrap_or_default();

    let (ar, caps) = if let (Some(g), Some(v)) = (group, version) {
        let gvk = GroupVersionKind::gvk(g.as_str(), v.as_str(), kind.as_str());
        kube::discovery::pinned_kind(client, &gvk)
            .await
            .map_err(mlua::Error::external)?
    } else {
        let discovery = Discovery::new(client.clone())
            .run()
            .await
            .map_err(mlua::Error::external)?;
        resolve_api_resource(&discovery, &kind).ok_or_else(|| {
            mlua::Error::external(format!("Resource not found in cluster: {kind}"))
        })?
    };

    let api = dynamic_api(ar, caps, client.clone(), namespace.as_deref(), false);

    let mut obj = api.get(&name).await.map_err(mlua::Error::external)?;
    obj.managed_fields_mut().clear();

    Ok(output_mode.format(obj))
}

#[tracing::instrument]
pub fn get_single(lua: &Lua, json: String) -> LuaResult<String> {
    let args: GetSingleArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let output_mode = args
        .output
        .as_deref()
        .map(OutputMode::from_str)
        .unwrap_or_default();

    with_client(move |client| async move {
        if let Some(found) =
            store::get_single(&args.gvk.k, args.namespace.clone(), &args.name).await?
        {
            return Ok(output_mode.format(found));
        }
        let result = get_resource_async(
            &client,
            args.gvk.k,
            Some(args.gvk.g),
            Some(args.gvk.v),
            args.name,
            args.namespace,
            args.output,
        );

        result.await
    })
}

#[tracing::instrument]
pub async fn get_single_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: GetSingleArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let output_mode = args
        .output
        .as_deref()
        .map(OutputMode::from_str)
        .unwrap_or_default();

    with_client(move |client| async move {
        if args.cached.unwrap_or(true) {
            if let Some(found) =
                store::get_single(&args.gvk.k, args.namespace.clone(), &args.name).await?
            {
                return Ok(output_mode.format(found));
            }
        }
        let result = get_resource_async(
            &client,
            args.gvk.k,
            Some(args.gvk.g),
            Some(args.gvk.v),
            args.name,
            args.namespace,
            args.output,
        );

        result.await
    })
}

#[tracing::instrument]
pub async fn get_server_raw_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: GetServerRawArgs = k8s_openapi::serde_json::from_str(&json).unwrap();

    with_client(move |client| async move {
        let full_url_str = format!("/{}", args.path.trim_start_matches('/'));
        let full_url: Uri = full_url_str.parse().map_err(LuaError::external)?;

        let req = http::Request::get(full_url)
            .body(Vec::new())
            .map_err(LuaError::external)?;

        let text = timeout(Duration::from_millis(2000), client.request_text(req))
            .await
            .map_err(|_| LuaError::external("request timed out"))?
            .map_err(LuaError::external)?;

        Ok(text)
    })
}

#[tracing::instrument]
pub async fn get_raw_async(_lua: Lua, args: (String, Option<String>, bool)) -> LuaResult<String> {
    let (url, _name, is_fallback) = args;

    with_client(move |client| async move {
        let mut req = http::Request::get(url)
            .body(Vec::new())
            .map_err(LuaError::external)?;
        if is_fallback {
            req.headers_mut().insert(
                http::header::ACCEPT,
                "application/json;as=Table;g=meta.k8s.io;v=v1"
                    .parse()
                    .unwrap(),
            );
        }

        let res = client.request_status::<serde_json::Value>(req).await;
        match res {
            Ok(either) => match either {
                Either::Left(resp) => {
                    let json = to_string(&resp).map_err(LuaError::external)?;
                    Ok(json)
                }
                Either::Right(status) => {
                    let err_json = to_string(&json!({
                        "error": format!("HTTP error: {:?}", status),
                        "status": status.code,
                    }))
                    .map_err(LuaError::external)?;
                    Ok(err_json)
                }
            },
            Err(e) => {
                let err_json = to_string(&json!({
                    "error": e.to_string(),
                    "status": null,
                }))
                .map_err(LuaError::external)?;
                Ok(err_json)
            }
        }
    })
}

#[derive(Serialize, Debug)]
struct FallbackResource {
    gvk: GroupVersionKind,
    plural: String,
    namespaced: bool,
    api_version: String,
    crd_name: String,
    short_names: Vec<String>,
}

impl FallbackResource {
    fn from_ar_cap(
        ar: &ApiResource,
        cap: &ApiCapabilities,
        shortnames_by_crd: &HashMap<String, Vec<String>>,
    ) -> Self {
        let crd_name = if ar.group.is_empty() {
            ar.plural.clone()
        } else {
            format!("{}.{}", ar.plural, ar.group)
        };

        Self {
            gvk: GroupVersionKind {
                group: ar.group.clone(),
                version: ar.version.clone(),
                kind: ar.kind.clone(),
            },
            plural: ar.plural.clone(),
            api_version: ar.api_version.clone(),
            namespaced: cap.scope == Scope::Namespaced,
            short_names: shortnames_by_crd
                .get(&crd_name)
                .cloned()
                .unwrap_or_default(),
            crd_name,
        }
    }
}

#[tracing::instrument]
pub async fn get_api_resources_async(_lua: Lua, _args: ()) -> LuaResult<String> {
    with_client(|client| async move {
        let discovery = Discovery::new(client.clone())
            .exclude(&[r"metrics.k8s.io", r"events.k8s.io"])
            .run()
            .await
            .map_err(|e| LuaError::external(format!("discovery: {e}")))?;

        let mut sn_map: HashMap<String, HashSet<String>> = HashMap::new();

        for group in discovery.groups() {
            let g_name = group.name();
            for ver in group.versions() {
                let span = trace_span!("disc_doc", group = %g_name, version = %ver);

                let result = async {
                    if g_name.is_empty() {
                        client.list_core_api_resources(ver).await
                    } else {
                        let gv = format!("{g_name}/{ver}");
                        client.list_api_group_resources(&gv).await
                    }
                }
                .instrument(span)
                .await;

                match result {
                    Ok(list) => {
                        let group_str = list
                            .group_version
                            .split_once('/')
                            .map(|(g, _)| g)
                            .unwrap_or("");

                        for r in list.resources {
                            let key = if group_str.is_empty() {
                                r.name.clone()
                            } else {
                                format!("{}.{}", r.name, group_str)
                            };

                            let names: HashSet<String> =
                                r.short_names.unwrap_or_default().into_iter().collect();
                            sn_map.entry(key).or_default().extend(names);
                        }
                    }
                    Err(e) => warn!("skip discovery doc {g_name}/{ver}: {e}"),
                }
            }
        }

        let sn_map: HashMap<String, Vec<String>> = sn_map
            .into_iter()
            .map(|(k, set)| {
                let mut v: Vec<String> = set.into_iter().collect();
                v.sort_unstable();
                (k, v)
            })
            .collect();

        let resources: Vec<FallbackResource> = discovery
            .groups()
            .flat_map(|g| {
                g.recommended_resources()
                    .into_iter()
                    .filter(|(ar, caps)| {
                        caps.supports_operation(verbs::LIST) && ar.plural != "componentstatuses"
                    })
                    .map(|(ar, caps)| FallbackResource::from_ar_cap(&ar, &caps, &sn_map))
            })
            .collect();

        serde_json::to_string(&resources).map_err(|e| LuaError::external(format!("serialize: {e}")))
    })
}
