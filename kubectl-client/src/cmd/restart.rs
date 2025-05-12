use k8s_openapi::chrono::Utc;
use k8s_openapi::serde_json;
use kube::api::ApiResource;
use kube::api::DynamicObject;
use kube::api::GroupVersionKind;
use kube::api::Patch;
use kube::api::PatchParams;
use kube::Api;
use mlua::prelude::*;

use crate::structs::CmdRestartArgs;
use crate::with_client;

pub async fn restart_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdRestartArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    with_client(move |client| async move {
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
    })
}
