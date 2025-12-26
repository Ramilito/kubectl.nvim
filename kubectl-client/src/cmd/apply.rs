use k8s_openapi::serde_json;
use kube::{
    api::{DynamicObject, GroupVersionKind, Patch, PatchParams},
    Discovery, ResourceExt,
};
use mlua::prelude::*;
use tokio::runtime::Runtime;

use crate::{CLIENT_INSTANCE, RUNTIME};

use super::utils::{dynamic_api, multidoc_deserialize};

#[tracing::instrument]
pub async fn apply_async(_lua: Lua, args: Option<String>) -> LuaResult<()> {
    let path = args;

    let (client, rt_handle) = {
        let client = {
            let client_guard = CLIENT_INSTANCE
                .lock()
                .map_err(|_| mlua::Error::RuntimeError("poisoned CLIENT_INSTANCE lock".into()))?;
            client_guard
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?
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
            .map_err(mlua::Error::external)
    })?;

    let ssapply = PatchParams::apply("kubectl-light").force();
    let pth = path
        .clone()
        .ok_or_else(|| mlua::Error::RuntimeError("apply requires a file path (-f)".into()))?;
    let yaml = std::fs::read_to_string(&pth).map_err(mlua::Error::external)?;

    for doc in multidoc_deserialize(&yaml)? {
        let obj: DynamicObject =
            serde_yaml::from_value(doc).map_err(mlua::Error::external)?;

        let namespace = obj.metadata.namespace.as_deref();

        let gvk = if let Some(tm) = &obj.types {
            GroupVersionKind::try_from(tm).map_err(mlua::Error::external)?
        } else {
            return Err(mlua::Error::RuntimeError("Missing object types".into()));
        };

        let name = obj.name_any();
        if let Some((ar, caps)) = discovery.resolve_gvk(&gvk) {
            let api = dynamic_api(ar, caps, client.clone(), namespace, false);

            let data: serde_json::Value =
                serde_json::to_value(&obj).map_err(mlua::Error::external)?;

            let _r = rt_handle.block_on(async {
                api.patch(&name, &ssapply, &Patch::Apply(data))
                    .await
                    .map_err(mlua::Error::external)
            });
        } else {
            return Err(mlua::Error::RuntimeError(
                "Cannot apply document for unknown ".into(),
            ));
        }
    }

    Ok(())
}
