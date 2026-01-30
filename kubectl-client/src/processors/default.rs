use crate::processors::processor::Processor;
use crate::utils::AccessorMode;
use kube::api::DynamicObject;
use mlua::prelude::*;

#[derive(Debug, Clone, serde::Serialize)]
pub struct DefaultProcessor;

impl Processor for DefaultProcessor {
    /// Each row is the original Kubernetes object.
    type Row = DynamicObject;
    type Resource = DynamicObject;

    /// Simply clone the object into the output vector.
    fn build_row(&self, _resource: &Self::Resource, obj: &DynamicObject) -> LuaResult<Self::Row> {
        Ok(obj.clone())
    }

    /// No text-filterable fields for this processor.
    fn filterable_fields(&self) -> &'static [&'static str] {
        &[]
    }

    /// Nothing to extract for sorting or filtering; always returns `None`.
    fn field_accessor(
        &self,
        _mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(|_, _| None)
    }
}
