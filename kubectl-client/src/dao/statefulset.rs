use k8s_openapi::{
    api::apps::v1::StatefulSet,
    serde_json::{json, Map, Value},
};
use kube::api::{Api, Patch, PatchParams};
use mlua::{Lua, Result as LuaResult};
use std::collections::HashMap;

use crate::{structs::ImageSpec, with_client};

pub fn set_images(_lua: &Lua, args: (String, String, Vec<ImageSpec>)) -> LuaResult<String> {
    let (statefulset_name, namespace, images) = args;

    with_client(move |client| async move {
        let statefulsets: Api<StatefulSet> = Api::namespaced(client.clone(), &namespace);

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
        let patched = statefulsets
            .patch(&statefulset_name, &pp, &Patch::Merge(&patch_body))
            .await;

        match patched {
            Ok(..) => Ok(format!(
                "Successfully updated images for deployment '{}'",
                statefulset_name
            )),
            Err(err) => {
                Ok(format!("Failed to scale '{}': {:?}", statefulset_name, err).to_string())
            }
        }
    })
}
