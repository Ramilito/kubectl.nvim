use crate::events::color_status;
use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::api::core::v1::PersistentVolume;
use k8s_openapi::apimachinery::pkg::api::resource::Quantity;
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct PersistentVolumeProcessed {
    name: String,
    capacity: String,
    #[serde(rename = "access modes")]
    access_modes: String,
    #[serde(rename = "reclaim policy")]
    reclaim_policy: String,
    status: FieldValue,
    claim: String,
    #[serde(rename = "storage class")]
    storage_class: String,
    reason: String,
    age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct PersistentVolumeProcessor;

impl Processor for PersistentVolumeProcessor {
    type Row = PersistentVolumeProcessed;
    type Resource = PersistentVolume;

    fn build_row(&self, pv: &Self::Resource, obj: &DynamicObject) -> LuaResult<Self::Row> {

        let name = pv.metadata.name.clone().unwrap_or_default();

        let spec = pv.spec.as_ref();

        let capacity = spec
            .and_then(|s| s.capacity.as_ref())
            .and_then(|q| q.get("storage"))
            .map(|q: &Quantity| q.0.clone())
            .unwrap_or_default();

        let access_modes = spec
            .and_then(|s| s.access_modes.as_ref())
            .map(access_modes)
            .unwrap_or_default();

        let reclaim_policy = spec
            .and_then(|s| s.persistent_volume_reclaim_policy.clone())
            .unwrap_or_default();

        let claim = spec
            .and_then(|s| s.claim_ref.as_ref())
            .map(|c| c.name.clone().unwrap_or_default())
            .unwrap_or_else(|| "<none>".into());

        let storage_class = pv
            .metadata
            .annotations
            .as_ref()
            .and_then(|a| a.get("volume.beta.kubernetes.io/storage-class").cloned())
            .or_else(|| spec.and_then(|s| s.storage_class_name.clone()))
            .unwrap_or_else(|| "<none>".into());

        let mut phase = pv
            .status
            .as_ref()
            .and_then(|st| st.phase.clone())
            .unwrap_or_else(|| "Unknown".into());
        let reason = pv
            .status
            .as_ref()
            .and_then(|st| st.reason.clone())
            .unwrap_or_default();

        if pv.metadata.deletion_timestamp.is_some() {
            phase = "Terminating".into();
        }
        let status = FieldValue {
            value: phase.clone(),
            symbol: Some(color_status(&phase)),
            ..Default::default()
        };

        let age = self.get_age(obj);

        Ok(PersistentVolumeProcessed {
            name,
            capacity,
            access_modes,
            reclaim_policy,
            status,
            claim,
            storage_class,
            reason,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &[
            "name",
            "capacity",
            "access modes",
            "reclaim policy",
            "status",
            "claim",
            "storage class",
            "reason",
        ]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |row, field| match field {
            "name" => Some(row.name.clone()),
            "capacity" => Some(row.capacity.clone()),
            "access modes" => Some(row.access_modes.clone()),
            "reclaim policy" => Some(row.reclaim_policy.clone()),
            "status" => Some(row.status.value.clone()),
            "claim" => Some(row.claim.clone()),
            "storage class" => Some(row.storage_class.clone()),
            "reason" => Some(row.reason.clone()),
            "age" => match mode {
                AccessorMode::Sort => row.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(row.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn access_modes(modes: &Vec<String>) -> String {
    use std::collections::BTreeSet;

    let mut out: BTreeSet<&str> = BTreeSet::new();
    for mode in modes {
        match mode.as_str() {
            "ReadWriteOnce" => {
                out.insert("RWO");
            }
            "ReadOnlyMany" => {
                out.insert("ROX");
            }
            "ReadWriteMany" => {
                out.insert("RWX");
            }
            "ReadWriteOncePod" => {
                out.insert("RWOP");
            }
            _ => {} // unknown value – ignore
        }
    }
    out.into_iter().collect::<Vec<_>>().join(", ")
}
