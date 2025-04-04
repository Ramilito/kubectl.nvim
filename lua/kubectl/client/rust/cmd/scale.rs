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

use crate::CLIENT_INSTANCE;
use crate::RUNTIME;

pub async fn scale_async(
    _lua: Lua,
    args: (String, Option<String>, String, String, String, usize),
) -> LuaResult<String> {
    let (kind, group, version, name, ns, replicas) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        let group_str = group.unwrap_or_default();
        let gvk = GroupVersionKind {
            group: group_str,
            version,
            kind: kind.to_string(),
        };
        let ar = ApiResource::from_gvk(&gvk);

        let scale_api: Api<DynamicObject> = Api::namespaced_with(client.clone(), &ns, &ar);

        let patch_data = json!({ "spec": { "replicas": replicas } });
        let patch = Patch::Merge(&patch_data);

        let scaled = scale_api
            .patch_scale(&name, &PatchParams::default(), &patch)
            .await;

        match scaled {
            Ok(..) => return Ok(format!("{}/{} scaled", kind, name,).to_string()),
            Err(err) => {
                return Ok(format!("Failed to scale '{}': {:?}", name, err).to_string());
            }
        };
    };

    rt.block_on(fut)
}
