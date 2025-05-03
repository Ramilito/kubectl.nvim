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
pub mod statefulset;
pub mod storageclass;

pub fn get_processors() -> HashMap<&'static str, Box<dyn Processor>> {
    let mut map: HashMap<&str, Box<dyn Processor>> = HashMap::new();
    map.insert("default", Box::new(default::DefaultProcessor));
    map.insert("pod", Box::new(pod::PodProcessor));
    map.insert("deployment", Box::new(deployment::DeploymentProcessor));
    map.insert("statefulset", Box::new(statefulset::StatefulsetProcessor));
    map.insert("storageclass", Box::new(storageclass::StorageClassProcessor));
    map.insert("clusterrolebinding", Box::new(clusterrolebinding::ClusterRoleBindingProcessor));
    map.insert("customresourcedefinition", Box::new(customresourcedefinition::ClusterResourceDefinitionProcessor));
    map.insert("configmap", Box::new(configmap::ConfigmapProcessor));
    map.insert("fallback", Box::new(fallback::FallbackProcessor));
    map
}
