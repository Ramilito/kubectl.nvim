use k8s_openapi::{api::apps::v1::Deployment, serde_json::json};
use kube::{
    api::{Api, Patch, PatchParams, ResourceExt},
    Client,
};
use mlua::{Error as LuaError, FromLua, Lua, Result as LuaResult, Value};
use std::collections::HashMap;
use tokio::runtime::Runtime;

use crate::{CLIENT_INSTANCE, RUNTIME};

#[derive(Debug, Clone)]
pub struct ImageSpec {
    pub index: usize,
    pub name: String,
    pub docker_image: String,
    pub init: bool,
}

impl FromLua for ImageSpec {
    fn from_lua(value: Value, lua: &Lua) -> LuaResult<Self> {
        match value {
            Value::Table(t) => {
                let index: usize = t.get("index")?;
                let name: String = t.get("name")?;
                let docker_image: String = t.get("docker_image")?;
                let init: bool = t.get("init")?;
                Ok(ImageSpec {
                    index,
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

// set_deployment_images mimics the Go SetImages method for a Deployment.
pub fn set_images(
    lua: &Lua,
    args: (String, String, String, String, String, Vec<ImageSpec>),
) -> LuaResult<String> {
    // Unpack the tuple:
    // - kind, group, version (for validation)
    // - deploy_name: the name of the Deployment
    // - namespace: the namespace of the Deployment
    // - images: vector of image specs for containers / initContainers.
    let (kind, group, version, deploy_name, namespace, images) = args;

    // Validate that we received a Deployment.
    if kind != "Deployment" || group != "apps" || version != "v1" {
        return Err(LuaError::RuntimeError(
            "Expected kind: Deployment, group: apps, version: v1".to_string(),
        ));
    }

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
        .clone();

    // Build an async future that creates a patch payload and applies it.
    let fut = async move {
        // Create an API handle for Deployments in the provided namespace.
        let deployments: Api<Deployment> = Api::namespaced(client.clone(), &namespace);

        // (Optional) Here you could perform an authorization check if your client supports it.
        // In kube-rs, this is typically done via RBAC and is not exposed as a function.

        // Build maps for container updates.
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
        // Each element is an object with a "name" and "image" field.
        let containers_array: Vec<_> = container_updates
            .into_iter()
            .map(|(cname, img)| json!({ "name": cname, "image": img }))
            .collect();
        let init_array: Vec<_> = init_container_updates
            .into_iter()
            .map(|(cname, img)| json!({ "name": cname, "image": img }))
            .collect();

        // Build the patch payload.
        // For a Deployment, the container definitions are located at
        // spec.template.spec.containers and spec.template.spec.initContainers.
        let patch_body = if !init_array.is_empty() && !containers_array.is_empty() {
            json!({
                "spec": {
                    "template": {
                        "spec": {
                            "containers": containers_array,
                            "initContainers": init_array
                        }
                    }
                }
            })
        } else if !init_array.is_empty() {
            json!({
                "spec": {
                    "template": {
                        "spec": {
                            "initContainers": init_array
                        }
                    }
                }
            })
        } else {
            json!({
                "spec": {
                    "template": {
                        "spec": {
                            "containers": containers_array
                        }
                    }
                }
            })
        };

        // Apply the strategic merge patch to update the Deployment.
        let pp = PatchParams::default();
        let patched = deployments
            .patch(&deploy_name, &pp, &Patch::Merge(&patch_body))
            .await;

        match patched {
            Ok(..) => {
                return Ok(format!(
                    "Successfully updated images for deployment '{}'",
                    deploy_name
                ))
            }
            Err(err) => {
                return Ok(format!("Failed to scale '{}': {:?}", deploy_name, err).to_string());
            }
        }
    };

    // Run the async future and convert any error into a LuaError.
    rt.block_on(fut)
}
