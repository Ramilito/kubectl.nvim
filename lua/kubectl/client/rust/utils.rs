use kube::api::DynamicObject;

/// Remove the managedFields from the DynamicObject.
pub fn strip_managed_fields(obj: &mut DynamicObject) {
    obj.metadata.managed_fields = None;
}
