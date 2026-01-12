use k8s_openapi::serde_json;
use kube::{
    api::{DynamicObject, GroupVersionKind, Patch, PatchParams},
    ResourceExt,
};
use mlua::prelude::*;

use crate::with_client;

use super::utils::{dynamic_api, multidoc_deserialize};

#[tracing::instrument]
pub async fn apply_async(_lua: Lua, args: Option<String>) -> LuaResult<()> {
    let pth = args
        .ok_or_else(|| mlua::Error::RuntimeError("apply requires a file path (-f)".into()))?;
    let yaml = std::fs::read_to_string(&pth).map_err(mlua::Error::external)?;

    let ssapply = PatchParams::apply("kubectl-light").force();

    for doc in multidoc_deserialize(&yaml)? {
        let obj: DynamicObject = serde_yaml::from_value(doc).map_err(mlua::Error::external)?;

        let gvk = obj
            .types
            .as_ref()
            .map(GroupVersionKind::try_from)
            .transpose()
            .map_err(mlua::Error::external)?
            .ok_or_else(|| mlua::Error::RuntimeError("Missing object types".into()))?;

        let namespace = obj.metadata.namespace.clone();
        let name = obj.name_any();
        let data: serde_json::Value =
            serde_json::to_value(&obj).map_err(mlua::Error::external)?;

        let ssapply = ssapply.clone();
        with_client(move |client| async move {
            let (ar, caps) = kube::discovery::pinned_kind(&client, &gvk)
                .await
                .map_err(mlua::Error::external)?;

            let api = dynamic_api(ar, caps, client, namespace.as_deref(), false);

            api.patch(&name, &ssapply, &Patch::Apply(data))
                .await
                .map_err(mlua::Error::external)?;

            Ok(())
        })?;
    }

    Ok(())
}
