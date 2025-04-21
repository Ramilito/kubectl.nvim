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

use crate::CLIENT_INSTANCE;
use crate::RUNTIME;

pub async fn restart_async(
    _lua: Lua,
    args: (String, Option<String>, String, String, String),
) -> LuaResult<String> {
    let (kind, group, version, name, ns) = args;

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
        let restart_api: Api<DynamicObject> = Api::namespaced_with(client.clone(), &ns, &ar);

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
            .patch(&name, &PatchParams::default(), &patch)
            .await;

        match restarted {
            Ok(restart) => Ok(format!("{}/{} restarted {:?}", kind, name, restart).to_string()),
            Err(err) => Ok(format!("Failed to scale '{}': {:?}", name, err).to_string()),
        }
    };

    rt.block_on(fut)
}
