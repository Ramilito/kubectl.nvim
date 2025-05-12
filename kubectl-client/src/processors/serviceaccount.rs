use k8s_openapi::api::core::v1::ServiceAccount;
use k8s_openapi::serde_json::{from_value, to_value};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct ServiceAccountProcessed {
    namespace: String,
    name: String,
    secret: usize,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ServiceAccountProcessor;

impl Processor for ServiceAccountProcessor {
    type Row = ServiceAccountProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let sa: ServiceAccount =
            from_value(to_value(obj).expect("Failed to convert DynamicObject to JSON Value"))
                .expect("Failed to convert JSON Value into ServiceAccount");
        Ok(ServiceAccountProcessed {
            namespace: sa.metadata.namespace.clone().unwrap_or_default(),
            name: sa.metadata.name.clone().unwrap_or_default(),
            secret: sa.secrets.unwrap_or_default().len(),
            age: self.get_age(obj),
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "secret"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |resource, field| match field {
            "namespace" => Some(resource.namespace.clone()),
            "name" => Some(resource.name.clone()),
            "secret" => Some(resource.secret.clone().to_string()),
            "age" => match mode {
                AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
                AccessorMode::Filter => Some(resource.age.value.clone()),
            },
            _ => None,
        })
    }
}
