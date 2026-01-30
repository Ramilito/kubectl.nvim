use k8s_openapi::api::rbac::v1::{ClusterRoleBinding, Subject};
use kube::api::DynamicObject;
use mlua::prelude::*;

use crate::events::{color_status, symbols};
use crate::processors::processor::{dynamic_to_typed, Processor};
use crate::utils::{AccessorMode, FieldValue};

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
    type Row = ClusterRoleBindingProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let crb: ClusterRoleBinding = dynamic_to_typed(obj)?;

        Ok(ClusterRoleBindingProcessed {
            name: crb.metadata.name.clone().unwrap_or_default(),
            role: crb.role_ref.name.clone(),
            subject_kind: get_subject_kind(crb.subjects.clone()),
            subjects: get_subjects(crb.subjects),
            age: self.get_age(obj),
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["name", "role", "subject_kind", "subjects"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |resource, field| match field {
            "name" => Some(resource.name.clone()),
            "role" => Some(resource.role.clone()),
            "subject_kind" => Some(resource.subject_kind.value.clone()),
            "subjects" => Some(resource.subjects.value.clone()),
            "age" => match mode {
                AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
                AccessorMode::Filter => Some(resource.age.value.clone()),
            },
            _ => None,
        })
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
        field.value = subjects
            .iter()
            .map(|s| s.name.as_str())
            .collect::<Vec<&str>>()
            .join(", ");
    }
    field
}
