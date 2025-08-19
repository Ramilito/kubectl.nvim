use k8s_openapi::api::rbac::v1::ClusterRole;
use kube::api::DynamicObject;
use mlua::prelude::*;

use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct ClusterRoleProcessed {
    name: String,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ClusterRoleProcessor;

impl Processor for ClusterRoleProcessor {
    type Row = ClusterRoleProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        use k8s_openapi::serde_json::{from_value, to_value};

        let cr: ClusterRole =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;

        Ok(ClusterRoleProcessed {
            name: cr.metadata.name.clone().unwrap_or_default(),
            age: self.get_age(obj),
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["name"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |resource, field| match field {
            "name" => Some(resource.name.clone()),
            "age" => match mode {
                AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
                AccessorMode::Filter => Some(resource.age.value.clone()),
            },
            _ => None,
        })
    }
}
