use k8s_openapi::serde_json;
use kube::{
    api::{ApiResource, DynamicObject, GroupVersionKind, Patch, PatchParams},
    discovery::{ApiCapabilities, Scope},
    Api, Client, Discovery, ResourceExt,
};
use mlua::prelude::*;

use crate::{CLIENT_INSTANCE, RUNTIME};

pub async fn apply_async(_lua: Lua, args: Option<String>) -> LuaResult<()> {
    let path = args;

    let (client, rt_handle) = {
        let client = {
            let client_guard = CLIENT_INSTANCE.lock().unwrap();
            client_guard
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?
                .clone()
        };

        let rt_handle = {
            let rt_guard = RUNTIME.lock().unwrap();
            rt_guard
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".into()))?
                .handle()
                .clone()
        };

        (client, rt_handle)
    };

    let discovery = rt_handle.block_on(async {
        Discovery::new(client.clone())
            .run()
            .await
            .map_err(|e| mlua::Error::external(e))
    })?;

    let ssapply = PatchParams::apply("kubectl-light").force();
    let pth = path.clone().expect("apply needs a -f file supplied");
    let yaml = std::fs::read_to_string(&pth).map_err(|e| mlua::Error::external(e))?;

    for doc in multidoc_deserialize(&yaml)? {
        let mut obj: DynamicObject =
            serde_yaml::from_value(doc).map_err(|e| mlua::Error::external(e))?;

        let namespace = obj.metadata.namespace.as_deref();

        let gvk = if let Some(tm) = &obj.types {
            GroupVersionKind::try_from(tm).map_err(|e| mlua::Error::external(e))?
        } else {
            return Err(mlua::Error::RuntimeError("Missing object types".into()));
        };

        let name = obj.name_any();
        if let Some((ar, caps)) = discovery.resolve_gvk(&gvk) {
            let api = dynamic_api(ar, caps, client.clone(), namespace, false);

            let data: serde_json::Value =
                serde_json::to_value(&obj).map_err(|e| mlua::Error::external(e))?;

            let _r = rt_handle.block_on(async {
                api.patch(&name, &ssapply, &Patch::Apply(data))
                    .await
                    .map_err(|e| mlua::Error::external(e))
            });
        } else {
            return Err(mlua::Error::RuntimeError(
                "Cannot apply document for unknown ".into(),
            ));
        }
    }

    Ok(())
}

pub fn multidoc_deserialize(data: &str) -> LuaResult<Vec<serde_yaml::Value>> {
    use serde::Deserialize;
    let mut docs = vec![];
    for de in serde_yaml::Deserializer::from_str(data) {
        docs.push(serde_yaml::Value::deserialize(de).map_err(|e| mlua::Error::external(e))?);
    }
    Ok(docs)
}
fn dynamic_api(
    ar: ApiResource,
    caps: ApiCapabilities,
    client: Client,
    ns: Option<&str>,
    all: bool,
) -> Api<DynamicObject> {
    if caps.scope == Scope::Cluster || all {
        Api::all_with(client, &ar)
    } else if let Some(namespace) = ns {
        Api::namespaced_with(client, namespace, &ar)
    } else {
        Api::default_namespaced_with(client, &ar)
    }
}

fn resolve_api_resource(
    discovery: &Discovery,
    name: &str,
) -> Option<(ApiResource, ApiCapabilities)> {
    // iterate through groups to find matching kind/plural names at recommended versions
    // and then take the minimal match by group.name (equivalent to sorting groups by group.name).
    // this is equivalent to kubectl's api group preference
    discovery
        .groups()
        .flat_map(|group| {
            group
                .resources_by_stability()
                .into_iter()
                .map(move |res| (group, res))
        })
        .filter(|(_, (res, _))| {
            // match on both resource name and kind name
            // ideally we should allow shortname matches as well
            name.eq_ignore_ascii_case(&res.kind) || name.eq_ignore_ascii_case(&res.plural)
        })
        .min_by_key(|(group, _res)| group.name())
        .map(|(_, res)| res)
}
