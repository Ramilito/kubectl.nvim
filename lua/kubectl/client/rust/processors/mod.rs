use crate::processors::processor::Processor;
use std::collections::HashMap;
use std::sync::OnceLock;

pub mod clusterrolebinding;
// pub mod configmap;
// pub mod customresourcedefinition;
// pub mod default;
// pub mod deployment;
pub mod fallback;
// pub mod persistentvolumeclaim;
pub mod pod;
pub mod processor;
// pub mod service;
// pub mod statefulset;
// pub mod storageclass;

use crate::processors::{
    clusterrolebinding::ClusterRoleBindingProcessor,
    // configmap::ConfigmapProcessor,
    // customresourcedefinition::ClusterResourceDefinitionProcessor,
    // default::DefaultProcessor,
    // deployment::DeploymentProcessor,
    fallback::FallbackProcessor,
    // persistentvolumeclaim::PersistentVolumeClaimProcessor,
    pod::PodProcessor,
    processor::DynProcessor, // the object-safe wrapper trait
    // service::ServiceProcessor,
    // statefulset::StatefulsetProcessor,
    // storageclass::StorageClassProcessor,
};

type ProcessorMap = HashMap<&'static str, Box<dyn DynProcessor>>;

/// One global, lazily-initialised map.
/// `OnceLock` guarantees that initialisation is thread-safe and happens only once.
static PROCESSORS: OnceLock<ProcessorMap> = OnceLock::new();

/// Build the map exactly once and return a reference to it.
fn processors() -> &'static ProcessorMap {
    PROCESSORS.get_or_init(|| {
        let mut m: ProcessorMap = HashMap::new();
        m.insert("clusterrolebinding", Box::new(ClusterRoleBindingProcessor));
        // m.insert("configmap", Box::new(ConfigmapProcessor));
        // m.insert(
        //     "customresourcedefinition",
        //     Box::new(ClusterResourceDefinitionProcessor),
        // );
        // m.insert("default", Box::new(DefaultProcessor));
        // m.insert("deployment", Box::new(DeploymentProcessor));
        m.insert("fallback", Box::new(FallbackProcessor));
        // m.insert(
        //     "persistentvolumeclaim",
        //     Box::new(PersistentVolumeClaimProcessor),
        // );
        m.insert("pod", Box::new(PodProcessor));
        // m.insert("service", Box::new(ServiceProcessor));
        // m.insert("statefulset", Box::new(StatefulsetProcessor));
        // m.insert("storageclass", Box::new(StorageClassProcessor));
        m
    })
}

/// Handy accessor that falls back to `"default"` if the requested kind is missing.
pub fn processor(kind: &str) -> &'static dyn DynProcessor {
    processors()
        .get(kind)
        .map(|b| &**b) // `Box<T>` → `&T`
        .unwrap_or_else(|| &*processors()["default"])
}
