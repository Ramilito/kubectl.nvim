use k8s_openapi::apiextensions_apiserver::pkg::apis::apiextensions::v1::{
    CustomResourceDefinition, CustomResourceDefinitionVersion,
};
use k8s_openapi::serde_json::{self};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;

use crate::events::color_status;
use crate::processors::processor::Processor;
use crate::utils::{filter_dynamic, sort_dynamic, AccessorMode, FieldValue};

#[derive(Debug, Clone, serde::Serialize)]
pub struct ClusterResourceDefinitionProcessed {
    name: String,
    group: String,
    kind: String,
    versions: FieldValue,
    scope: String,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ClusterResourceDefinitionProcessor;

impl Processor for ClusterResourceDefinitionProcessor {
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
            let map: CustomResourceDefinition = serde_json::from_value(
                serde_json::to_value(obj).expect("Failed to convert DynamicObject to JSON Value"),
            )
            .expect("Failed to convert JSON Value into ClusterRoleBinding");

            let name = map.metadata.name.clone().unwrap_or_default();
            let group = map.spec.group;
            let kind = map.spec.names.kind;
            let versions = get_versions(map.spec.versions);
            let scope = map.spec.scope;
            let age = self.get_age(obj);

            data.push(ClusterResourceDefinitionProcessed {
                name,
                group,
                kind,
                versions,
                scope,
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
                &["name", "group", "kind", "versions", "scope"],
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
) -> impl Fn(&ClusterResourceDefinitionProcessed, &str) -> Option<String> {
    move |resource, field| match field {
        "name" => Some(resource.name.clone()),
        "group" => Some(resource.group.clone().to_string()),
        "kind" => Some(resource.kind.clone().to_string()),
        "versions" => Some(resource.versions.value.clone().to_string()),
        "scope" => Some(resource.scope.clone().to_string()),
        "age" => match mode {
            AccessorMode::Sort => Some(resource.age.sort_by?.to_string()),
            AccessorMode::Filter => Some(resource.age.value.clone()),
        },
        _ => None,
    }
}

fn get_versions(versions: Vec<CustomResourceDefinitionVersion>) -> FieldValue {
    let mut versions_str = String::new();
    let mut has_deprecated = false;

    for version in versions {
        if !versions_str.is_empty() {
            versions_str.push(',');
        }
        versions_str.push_str(&version.name);
        if version.deprecated.unwrap_or(false) {
            has_deprecated = true;
            versions_str.push('!');
        }
    }

    FieldValue {
        value: versions_str,
        symbol: if has_deprecated {
            Some(color_status("Error"))
        } else {
            None
        },
        ..Default::default()
    }
}
