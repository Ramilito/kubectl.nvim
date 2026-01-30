use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::api::core::v1::{PersistentVolumeClaim, VolumeResourceRequirements};
use k8s_openapi::apimachinery::pkg::api::resource::Quantity;
use kube::api::DynamicObject;
use mlua::prelude::*;
use std::collections::BTreeMap;

#[derive(Debug, Clone, serde::Serialize)]
pub struct PersistentVolumeClaimProcessed {
    namespace: String,
    name: String,
    status: FieldValue,
    volume: String,
    capacity: String,
    #[serde(rename = "access modes")]
    access_modes: String,
    #[serde(rename = "storage class")]
    storage_class: String,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct PersistentVolumeClaimProcessor;

impl Processor for PersistentVolumeClaimProcessor {
    type Row = PersistentVolumeClaimProcessed;
    type Resource = PersistentVolumeClaim;

    fn build_row(&self, pvc: &Self::Resource, obj: &DynamicObject) -> LuaResult<Self::Row> {

        let namespace = pvc.metadata.namespace.clone().unwrap_or_default();
        let name = pvc.metadata.name.clone().unwrap_or_default();
        let status = get_phase(&pvc);

        let (volume, capacity, access_modes, storage_class) = pvc.spec.as_ref().map_or_else(
            || (String::new(), String::new(), String::new(), String::new()),
            |spec| {
                let volume = spec.volume_name.clone().unwrap_or_default();
                let capacity = spec
                    .resources
                    .as_ref()
                    .and_then(get_capacity)
                    .unwrap_or_default();
                let access_modes = get_access_modes(spec.access_modes.clone());
                let storage_class = spec.storage_class_name.clone().unwrap_or_default();
                (volume, capacity, access_modes, storage_class)
            },
        );

        let age = self.get_age(obj);

        Ok(PersistentVolumeClaimProcessed {
            namespace,
            name,
            status,
            volume,
            capacity,
            access_modes,
            storage_class,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &[
            "namespace",
            "name",
            "status",
            "volume",
            "capacity",
            "access modes",
            "storage class",
        ]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "name" => Some(row.name.clone()),
            "status" => Some(row.status.value.clone()),
            "volume" => Some(row.volume.clone()),
            "capacity" => Some(row.capacity.clone()),
            "access modes" => Some(row.access_modes.clone()),
            "storage class" => Some(row.storage_class.clone()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn get_capacity(res: &VolumeResourceRequirements) -> Option<String> {
    res.requests
        .as_ref()
        .and_then(|m: &BTreeMap<String, Quantity>| m.get("storage"))
        .map(|q| q.0.clone())
}

fn get_access_modes(modes: Option<Vec<String>>) -> String {
    let mut out = Vec::new();
    if let Some(modes) = modes {
        for mode in modes {
            match mode.as_str() {
                "ReadWriteOnce" => out.push("RWO"),
                "ReadOnlyMany" => out.push("ROX"),
                "ReadWriteMany" => out.push("RWX"),
                "ReadWriteOncePod" => out.push("RWOP"),
                _ => {}
            }
        }
    }
    out.join(", ")
}

fn get_phase(pvc: &PersistentVolumeClaim) -> FieldValue {
    let mut phase = pvc
        .status
        .as_ref()
        .and_then(|s| s.phase.clone())
        .unwrap_or_else(|| "Unknown".into());

    if pvc.metadata.deletion_timestamp.is_some() {
        phase = "Terminating".into();
    }

    let (symbol, sort_by) = match phase.as_str() {
        "Bound" => ("KubectlNote", 4),
        "Pending" => ("KubectlWarning", 2),
        "Terminating" | "Lost" => ("KubectlError", 1),
        _ => ("KubectlNeutral", 0),
    };

    FieldValue {
        symbol: Some(symbol.into()),
        value: phase,
        sort_by: Some(sort_by),
        hint: None,
    }
}
