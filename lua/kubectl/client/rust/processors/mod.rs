use crate::processors::processor::Processor;
use std::collections::HashMap;

pub mod clusterrolebinding;
pub mod configmap;
pub mod customresourcedefinition;
pub mod default;
pub mod deployment;
pub mod fallback;
pub mod pod;
pub mod processor;
pub mod persistentvolumeclaim;
pub mod statefulset;
pub mod storageclass;

pub fn get_processors() -> HashMap<&'static str, Box<dyn Processor>> {
    let mut map: HashMap<&str, Box<dyn Processor>> = HashMap::new();
    map.insert("clusterrolebinding", Box::new(clusterrolebinding::ClusterRoleBindingProcessor));
    map.insert("configmap", Box::new(configmap::ConfigmapProcessor));
    map.insert("customresourcedefinition", Box::new(customresourcedefinition::ClusterResourceDefinitionProcessor));
    map.insert("default", Box::new(default::DefaultProcessor));
    map.insert("deployment", Box::new(deployment::DeploymentProcessor));
    map.insert("fallback", Box::new(fallback::FallbackProcessor));
    map.insert("persistentvolumeclaim", Box::new(persistentvolumeclaim::PersistentVolumeClaimProcessor));
    map.insert("pod", Box::new(pod::PodProcessor));
    map.insert("statefulset", Box::new(statefulset::StatefulsetProcessor));
    map.insert("storageclass", Box::new(storageclass::StorageClassProcessor));
    map
}
