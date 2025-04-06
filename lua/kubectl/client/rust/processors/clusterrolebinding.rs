use k8s_openapi::api::rbac::v1::{ClusterRoleBinding, Subject};
use k8s_openapi::serde_json::{self};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

use crate::events::{color_status, symbols};
use crate::processors::processor::Processor;
use crate::utils::{filter_dynamic, sort_dynamic, AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct ClusterRoleBindingProcessed {
    name: String,
    role: String,
    #[serde(rename = "subject-kind")]
    subject_kind: FieldValue,
    subjects: FieldValue,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ClusterRoleBindingProcessor;

impl Processor for ClusterRoleBindingProcessor {
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
            let crb: ClusterRoleBinding = serde_json::from_value(
                serde_json::to_value(obj).expect("Failed to convert DynamicObject to JSON Value"),
            )
            .expect("Failed to convert JSON Value into ClusterRoleBinding");

            let name = crb.metadata.name.clone().unwrap_or_default();
            let role = crb.role_ref.name.clone();
            let subject_kind = get_subject_kind(crb.subjects.clone());
            let subjects = get_subjects(crb.subjects);
            let age = self.get_age(obj);

            data.push(ClusterRoleBindingProcessed {
                name,
                role,
                subject_kind,
                subjects,
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
                &["name", "role", "subject_kind", "subjects"],
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

fn field_accessor(
    mode: AccessorMode,
) -> impl Fn(&ClusterRoleBindingProcessed, &str) -> Option<String> {
    move |resource, field| match field {
        "name" => Some(resource.name.clone()),
        "role" => Some(resource.role.clone()),
        "subject_kind" => Some(resource.subject_kind.value.clone()),
        "subjects" => Some(resource.subjects.value.clone()),
        "age" => match mode {
            AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
            AccessorMode::Filter => Some(resource.age.value.clone()),
        },
        _ => None,
    }
}

fn get_subject_kind(subjects: Option<Vec<Subject>>) -> FieldValue {
    let mut kind_field = FieldValue::default();
    if let Some(subjects) = subjects {
        for subject in subjects {
            kind_field.value = subject.kind.clone();
            match kind_field.value.as_str() {
                "ServiceAccount" => {
                    kind_field.symbol = Some(color_status(&symbols().success));
                    kind_field.value = "SvcAcct".to_string();
                }
                "User" => {
                    kind_field.symbol = Some(color_status(&symbols().note));
                }
                "Group" => {
                    kind_field.symbol = Some(color_status(&symbols().debug));
                }
                _ => {}
            }
        }
    }
    kind_field
}

fn get_subjects(subjects: Option<Vec<Subject>>) -> FieldValue {
    let mut field = FieldValue::default();
    if let Some(subjects) = subjects {
        field.value = subjects.iter().map(|s| s.name.as_str()).join(", ");
    }
    field
}
