use k8s_openapi::serde_json;
use kube::{
    api::{DynamicObject, GroupVersionKind, Patch, PatchParams},
    Discovery, ResourceExt,
};
use mlua::prelude::*;

use crate::{CLIENT_INSTANCE, RUNTIME};

use super::utils::{dynamic_api, multidoc_deserialize};

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
        let obj: DynamicObject =
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
