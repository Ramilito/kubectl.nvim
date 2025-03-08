use kube::{
    api::{ApiResource, DynamicObject, GroupVersionKind},
    discovery::{ApiCapabilities, Scope},
    Api, Client, Discovery, ResourceExt,
};
use mlua::prelude::*;

use crate::{CLIENT_INSTANCE, RUNTIME};

pub async fn edit_async(_lua: Lua, args: Option<String>) -> LuaResult<String> {
    let path = args;

    let (client, rt_handle) = {
        let client = {
            let client_guard = CLIENT_INSTANCE.lock().unwrap();
            client_guard
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".to_string()))?
                .clone()
        };

        let rt_handle = {
            let rt_guard = RUNTIME.lock().unwrap();
            rt_guard
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".to_string()))?
                .handle()
                .clone()
        };

        (client, rt_handle)
    };

    let discovery = rt_handle.block_on(async {
        Discovery::new(client.clone())
            .run()
            .await
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))
    })?;

    let pth = path.clone().expect("apply needs a -f file supplied");
    let yaml_raw =
        std::fs::read_to_string(&pth).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    let yaml: serde_yaml::Value =
        serde_yaml::from_str(&yaml_raw).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

    let obj: DynamicObject =
        serde_yaml::from_value(yaml).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

    let namespace = obj.metadata.namespace.as_deref();

    let gvk = if let Some(tm) = &obj.types {
        GroupVersionKind::try_from(tm).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?
    } else {
        return Err(mlua::Error::RuntimeError(
            "Missing object types".to_string(),
        ));
    };

    let name = obj.name_any();
    if let Some((ar, caps)) = discovery.resolve_gvk(&gvk) {
        let api = dynamic_api(ar.clone(), caps, client.clone(), namespace, false);

        let _r = rt_handle.block_on(async {
            api.replace(&name, &Default::default(), &obj)
                .await
                .map_err(|e| mlua::Error::RuntimeError(e.to_string()))
        })?;

        Ok(format!("{}/{} edited", ar.plural, name))
    } else {
        Err(mlua::Error::RuntimeError(
            "Cannot edit document for unknown resource".to_string(),
        ))
    }
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
