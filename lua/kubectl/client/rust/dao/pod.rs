use std::collections::HashMap;

use k8s_openapi::{api::core::v1::Pod, serde_json::json};
use kube::{
    api::{Patch, PatchParams},
    Api,
};
use mlua::prelude::*;
use tokio::runtime::Runtime;

use crate::{CLIENT_INSTANCE, RUNTIME};

use mlua::{FromLua, Lua, Result as LuaResult, Value};

#[derive(Debug, Clone)]
pub struct ImageSpec {
    pub name: String,
    pub docker_image: String,
    pub init: bool,
}

impl FromLua for ImageSpec {
    fn from_lua(value: Value, _lua: &Lua) -> LuaResult<Self> {
        match value {
            Value::Table(t) => {
                let name: String = t.get("name")?;
                let docker_image: String = t.get("docker_image")?;
                let init: bool = t.get("init")?;
                Ok(ImageSpec {
                    name,
                    docker_image,
                    init,
                })
            }
            _ => Err(mlua::Error::FromLuaConversionError {
                from: value.type_name(),
                to: "ImageSpec".to_string(),
                message: None,
            }),
        }
    }
}

pub fn set_images(
    _lua: &Lua,
    args: (String, String, String, String, String, Vec<ImageSpec>),
) -> LuaResult<String> {
    // Unpack the tuple; the first three values (kind, group, version) are currently unused,
    // but they can be used later for validation.
    let (_kind, _group, _version, pod_name, namespace, images) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
        .clone();

    let fut = async move {
        // Create an API handle for Pods in the provided namespace.
        let pods: Api<Pod> = Api::namespaced(client.clone(), &namespace);

        // Fetch the existing Pod to verify it is not managed by a controller.
        // let existing = pods.get(&pod_name).await?;
        let existing = match pods.get(&pod_name).await {
            Ok(pod) => pod,
            Err(e) => {
                return Ok(format!(
                    "No pod named {} in {} found: {}",
                    pod_name, namespace, e
                ))
            }
        };
        // if let Some(owner_refs) = existing.owner_references() {
        //     if !owner_refs.is_empty() {
        //         let controller_kind = &owner_refs[0].kind;
        //         return Err(kube::Error::RequestValidation(format!(
        //             "Cannot set image: this Pod is managed by {}. Please update the controller's pod template instead.",
        //             controller_kind
        //         )));
        //     }
        // }

        // Build maps for container updates. Separate initContainers and regular containers.
        let mut container_updates: HashMap<String, String> = HashMap::new();
        let mut init_container_updates: HashMap<String, String> = HashMap::new();
        for spec in images {
            if spec.init {
                init_container_updates.insert(spec.name.clone(), spec.docker_image);
            } else {
                container_updates.insert(spec.name.clone(), spec.docker_image);
            }
        }

        // Convert these maps into arrays for a strategic merge patch.
        let containers_array: Vec<_> = container_updates
            .into_iter()
            .map(|(cname, img)| json!({ "name": cname, "image": img }))
            .collect();
        let init_array: Vec<_> = init_container_updates
            .into_iter()
            .map(|(cname, img)| json!({ "name": cname, "image": img }))
            .collect();

        // Build the patch payload.
        let patch_body = if !init_array.is_empty() && !containers_array.is_empty() {
            json!({
                "spec": {
                    "containers": containers_array,
                    "initContainers": init_array
                }
            })
        } else if !init_array.is_empty() {
            json!({
                "spec": {
                    "initContainers": init_array
                }
            })
        } else {
            json!({
                "spec": {
                    "containers": containers_array
                }
            })
        };

        // Apply the strategic merge patch to update the Pod.
        let pp = PatchParams::default();
        let patched = pods
            .patch(&pod_name, &pp, &Patch::Strategic(&patch_body))
            .await;

        match patched {
            Ok(..) => {
                Ok(format!(
                    "Successfully updated images for pod '{}'",
                    pod_name,
                ))
            }
            Err(err) => {
                Ok(format!("Failed to scale '{}': {:?}", pod_name, err).to_string())
            }
        }
    };

    rt.block_on(fut)
    // Run the async future and map any error into a LuaError.
    // rt.block_on(fut).map_err(|e| LuaError::RuntimeError(e.to_string()))
}
