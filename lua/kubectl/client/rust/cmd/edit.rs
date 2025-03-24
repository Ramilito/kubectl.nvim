use kube::{
    api::{DynamicObject, GroupVersionKind},
    Discovery, ResourceExt,
};
use mlua::prelude::*;
use tokio::runtime::Runtime;

use crate::{CLIENT_INSTANCE, RUNTIME};

use super::utils::dynamic_api;

pub async fn edit_async(_lua: Lua, args: Option<String>) -> LuaResult<String> {
    let path = args;

    let (client, rt_handle) = {
        let client = {
            let client_guard = CLIENT_INSTANCE.lock().map_err(|_| {
                LuaError::RuntimeError("Failed to acquire lock on client instance".into())
            })?;
            client_guard
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".to_string()))?
                .clone()
        };

        let rt_handle =
            { RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime")) };

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
