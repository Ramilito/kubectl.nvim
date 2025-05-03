use crate::processors::processor::Processor;
use crate::utils::{filter_dynamic, sort_dynamic, AccessorMode, FieldValue};
use k8s_openapi::api::storage::v1::StorageClass;
use k8s_openapi::serde_json::{self};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

#[derive(Debug, Clone, serde::Serialize)]
pub struct StorageClassProcessed {
    name: String,
    provisioner: String,
    reclaimpolicy: String,
    volumebindingmode: String,
    allowvolumeexpansion: bool,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct StorageClassProcessor;

impl Processor for StorageClassProcessor {
    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
    ) -> LuaResult<mlua::Value> {
        let mut data = Vec::new();
        for obj in items {
            let storageclass: StorageClass = serde_json::from_value(
                serde_json::to_value(obj).expect("Failed to convert DynamicObject to JSON Value"),
            )
            .expect("Failed to convert JSON Value into Statefulset");

            let name = storageclass.metadata.name.clone().unwrap_or_default();
            let provisioner = storageclass.provisioner.clone();
            let reclaimpolicy = storageclass.reclaim_policy.clone().unwrap_or_default();
            let volumebindingmode = storageclass.volume_binding_mode.clone().unwrap_or_default();
            let allowvolumeexpansion = storageclass.allow_volume_expansion.unwrap_or_default();
            let age = self.get_age(obj);

            data.push(StorageClassProcessed {
                name,
                provisioner,
                reclaimpolicy,
                volumebindingmode,
                allowvolumeexpansion,
                age,
            });
        }
        sort_dynamic(
            &mut data,
            sort_by,
            sort_order,
            field_accessor(AccessorMode::Sort),
        );

        let data = if let Some(ref filter_value) = filter {
            filter_dynamic(
                &data,
                filter_value,
                &[
                    "name",
                    "provisioner",
                    "reclaimpolicy",
                    "volumebindingmode",
                    "allowvolumeexpansion",
                ],
                field_accessor(AccessorMode::Filter),
            )
            .into_iter()
            .cloned()
            .collect()
        } else {
            data
        };

        lua.to_value(&data)
    }
}

fn field_accessor(mode: AccessorMode) -> impl Fn(&StorageClassProcessed, &str) -> Option<String> {
    move |resource, field| match field {
        "name" => Some(resource.name.clone()),
        "provisioner" => Some(resource.name.clone()),
        "reclaimpolicy" => Some(resource.name.clone()),
        "volumebindingmode" => Some(resource.name.clone()),
        "allowvolumeexpansion" => Some(resource.name.clone()),
        "age" => match mode {
            AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
            AccessorMode::Filter => Some(resource.age.value.clone()),
        },
        _ => None,
    }
}
