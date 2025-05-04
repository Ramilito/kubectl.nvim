use k8s_openapi::serde_json;
use kube::api::ApiResource;
use kube::api::DynamicObject;
use kube::api::GroupVersionKind;
use kube::api::Patch;
use kube::api::PatchParams;
use kube::Api;
use mlua::prelude::*;
use serde_json::json;
use tokio::runtime::Runtime;

use crate::structs::CmdScaleArgs;
use crate::CLIENT_INSTANCE;
use crate::RUNTIME;

pub async fn scale_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdScaleArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
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
    };

    rt.block_on(fut)
}
