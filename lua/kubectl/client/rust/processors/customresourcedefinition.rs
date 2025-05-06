use crate::processors::processor::Processor;
use crate::utils::{AccessorMode, FieldValue};
use k8s_openapi::{
    apiextensions_apiserver::pkg::apis::apiextensions::v1::{
        CustomResourceDefinition, CustomResourceDefinitionVersion,
    },
    serde_json::{self, from_value, to_value},
};
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct ClusterResourceDefinitionProcessed {
    pub name: String,
    pub group: String,
    pub kind: String,
    pub versions: FieldValue,
    pub scope: String,
    pub age: FieldValue,
}

#[derive(Debug, Clone)]
pub struct ClusterResourceDefinitionProcessor;

impl Processor for ClusterResourceDefinitionProcessor {
    type Row = ClusterResourceDefinitionProcessed;

    fn build_row(&self, _lua: &Lua, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let crd: CustomResourceDefinition =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;

        let name = crd.metadata.name.unwrap_or_default();
        let group = crd.spec.group.clone();
        let kind = crd.spec.names.kind.clone();
        let versions = get_versions(crd.spec.versions);
        let scope = crd.spec.scope.clone();
        let age = self.get_age(obj);

        Ok(ClusterResourceDefinitionProcessed {
            name,
            group,
            kind,
            versions,
            scope,
            age,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["name", "group", "kind", "versions", "scope"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |res, field| match field {
            "name" => Some(res.name.clone()),
            "group" => Some(res.group.clone()),
            "kind" => Some(res.kind.clone()),
            "versions" => Some(res.versions.value.clone()),
            "scope" => Some(res.scope.clone()),
            "age" => match mode {
                AccessorMode::Sort => res.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(res.age.value.clone()),
            },
            _ => None,
        })
    }
}

fn get_versions(versions: Vec<CustomResourceDefinitionVersion>) -> FieldValue {
    let mut s = String::new();
    let mut has_deprecated = false;

    for v in versions {
        if !s.is_empty() {
            s.push(',');
        }
        s.push_str(&v.name);
        if v.deprecated.unwrap_or(false) {
            has_deprecated = true;
            s.push('!');
        }
    }

    FieldValue {
        value: s,
        symbol: if has_deprecated {
            Some(crate::events::color_status("Error"))
        } else {
            None
        },
        ..Default::default()
    }
}
