use k8s_openapi::{
    api::apps::v1::Deployment,
    serde_json::{json, Map, Value},
};
use kube::api::{Api, Patch, PatchParams};
use mlua::{FromLua, Lua, Result as LuaResult, Value as LuaValue};
use std::collections::HashMap;

use crate::with_client;

#[derive(Debug, Clone)]
pub struct ImageSpec {
    pub name: String,
    pub image: String,
    pub init: bool,
}

impl FromLua for ImageSpec {
    fn from_lua(value: LuaValue, _lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(t) => {
                let name: String = t.get("name")?;
                let image: String = t.get("image")?;
                let init: bool = t.get("init")?;
                Ok(ImageSpec { name, image, init })
            }
            _ => Err(mlua::Error::FromLuaConversionError {
                from: value.type_name(),
                to: "ImageSpec".to_string(),
                message: None,
            }),
        }
    }
}

pub fn set_images(_lua: &Lua, args: (String, String, Vec<ImageSpec>)) -> LuaResult<String> {
    let (deploy_name, namespace, images) = args;

    with_client(move |client| async move {
        let deployment: Api<Deployment> = Api::namespaced(client.clone(), &namespace);

        // Build maps for container updates.
        let mut container_updates: HashMap<String, String> = HashMap::new();
        let mut init_container_updates: HashMap<String, String> = HashMap::new();
        for spec in images {
            if spec.init {
                init_container_updates.insert(spec.name.clone(), spec.image);
            } else {
                container_updates.insert(spec.name.clone(), spec.image);
            }
        }

        let containers_array: Vec<_> = container_updates
            .into_iter()
            .map(|(cname, img)| json!({ "name": cname, "image": img }))
            .collect();
        let init_array: Vec<_> = init_container_updates
            .into_iter()
            .map(|(cname, img)| json!({ "name": cname, "image": img }))
            .collect();

        let mut spec_map = Map::new();

        if !containers_array.is_empty() {
            spec_map.insert("containers".to_string(), json!(containers_array));
        }
        if !init_array.is_empty() {
            spec_map.insert("initContainers".to_string(), json!(init_array));
        }

        let patch_body = json!({
            "spec": {
                "template": {
                    "spec": Value::Object(spec_map)
                }
            }
        });

        let pp = PatchParams::default();
        let patched = deployment
            .patch(&deploy_name, &pp, &Patch::Merge(&patch_body))
            .await;

        match patched {
            Ok(..) => Ok(format!(
                "Successfully updated images for deployment '{}'",
                deploy_name
            )),
            Err(err) => Ok(format!("Failed to scale '{}': {:?}", deploy_name, err).to_string()),
        }
    })
}
