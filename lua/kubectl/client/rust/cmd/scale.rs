use k8s_openapi::serde_json;
use kube::api::ApiResource;
use kube::api::DynamicObject;
use kube::api::GroupVersionKind;
use kube::api::Patch;
use kube::api::PatchParams;
use kube::Api;
use mlua::prelude::*;
use serde_json::json;

use crate::structs::CmdScaleArgs;
use crate::with_client;

pub async fn scale_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdScaleArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    with_client(move |client| async move {
        let gvk = GroupVersionKind {
            group: args.gvk.g,
            version: args.gvk.v,
            kind: args.gvk.k.to_string(),
        };
        let ar = ApiResource::from_gvk(&gvk);

        let scale_api: Api<DynamicObject> =
            Api::namespaced_with(client.clone(), &args.namespace, &ar);

        let patch_data = json!({ "spec": { "replicas": args.replicas } });
        let patch = Patch::Merge(&patch_data);

        let scaled = scale_api
            .patch_scale(&args.name, &PatchParams::default(), &patch)
            .await;

        match scaled {
            Ok(..) => Ok(format!("{}/{} scaled", gvk.kind, args.name,).to_string()),
            Err(err) => Ok(format!("Failed to scale '{}': {:?}", args.name, err).to_string()),
        }
    })
}
