use k8s_openapi::chrono::Utc;
use k8s_openapi::serde_json;
use kube::api::ApiResource;
use kube::api::DynamicObject;
use kube::api::GroupVersionKind;
use kube::api::Patch;
use kube::api::PatchParams;
use kube::Api;
use mlua::prelude::*;
use tokio::runtime::Runtime;

use crate::structs::CmdRestartArgs;
use crate::CLIENT_INSTANCE;
use crate::RUNTIME;

pub async fn restart_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdRestartArgs =
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
            kind: args.gvk.k,
        };
        let ar = ApiResource::from_gvk(&gvk);
        let restart_api: Api<DynamicObject> =
            Api::namespaced_with(client.clone(), &args.namespace, &ar);

        let patch_data = serde_json::json!({
          "spec": {
            "template": {
              "metadata": {
                "annotations": {
                  "kube.kubernetes.io/restartedAt": Utc::now().to_rfc3339()
                }
              }
            }
          }
        });

        let patch = Patch::Merge(&patch_data);
        let restarted = restart_api
            .patch(&args.name, &PatchParams::default(), &patch)
            .await;

        match restarted {
            Ok(..) => Ok(format!("{}/{} restarted", gvk.kind, args.name).to_string()),
            Err(err) => Ok(format!("Failed to restart '{}': {:?}", args.name, err).to_string()),
        }
    };

    rt.block_on(fut)
}
