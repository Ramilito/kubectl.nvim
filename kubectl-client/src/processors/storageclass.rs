use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::api::storage::v1::StorageClass;
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct StorageClassProcessed {
    name: String,
    provisioner: String,
    reclaimpolicy: String,
    volumebindingmode: String,
    allowvolumeexpansion: bool,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct StorageClassProcessor;

impl Processor for StorageClassProcessor {
    type Row = StorageClassProcessed;
    type Resource = StorageClass;

    fn build_row(&self, sc: &Self::Resource, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let name = sc.metadata.name.clone().unwrap_or_default();
        let provisioner = sc.provisioner.clone();
        let reclaimpolicy = sc.reclaim_policy.clone().unwrap_or_default();
        let volumebindingmode = sc.volume_binding_mode.clone().unwrap_or_default();
        let allowvolumeexpansion = sc.allow_volume_expansion.unwrap_or_default();
        let age = self.get_age(obj);
        Ok(StorageClassProcessed {
            name,
            provisioner,
            reclaimpolicy,
            volumebindingmode,
            allowvolumeexpansion,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &[
            "name",
            "provisioner",
            "reclaimpolicy",
            "volumebindingmode",
            "allowvolumeexpansion",
        ]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |r, field| match field {
            "name" => Some(r.name.clone()),
            "provisioner" => Some(r.provisioner.clone()),
            "reclaimpolicy" => Some(r.reclaimpolicy.clone()),
            "volumebindingmode" => Some(r.volumebindingmode.clone()),
            "allowvolumeexpansion" => Some(r.allowvolumeexpansion.to_string()),
            "age" => match mode {
                AccessorMode::Sort => r.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(r.age.value.clone()),
            },
            _ => None,
        })
    }
}
