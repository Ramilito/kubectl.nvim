use k8s_openapi::api::core::v1::Secret;
use kube::api::DynamicObject;
use mlua::prelude::*;

use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct SecretProcessed {
    namespace: String,
    name: String,
    #[serde(rename = "type")]
    secret_type: String,
    data: usize,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct SecretProcessor;

impl Processor for SecretProcessor {
    type Row = SecretProcessed;
    type Resource = Secret;

    fn build_row(&self, secret: &Self::Resource, obj: &DynamicObject) -> LuaResult<Self::Row> {
        Ok(SecretProcessed {
            namespace: secret.metadata.namespace.clone().unwrap_or_default(),
            name: secret.metadata.name.clone().unwrap_or_default(),
            secret_type: secret.type_.clone().unwrap_or_default(),
            data: secret.data.clone().unwrap_or_default().len(),
            age: self.get_age(obj),
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "type", "data"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |resource, field| match field {
            "namespace" => Some(resource.namespace.clone()),
            "name" => Some(resource.name.clone()),
            "type" => Some(resource.secret_type.clone().to_string()),
            "data" => Some(resource.data.clone().to_string()),
            "age" => match mode {
                AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
                AccessorMode::Filter => Some(resource.age.value.clone()),
            },
            _ => None,
        })
    }
}
