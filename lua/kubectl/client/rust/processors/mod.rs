use std::collections::HashMap;
use std::sync::OnceLock;

pub mod clusterrolebinding;
pub mod configmap;
pub mod cronjob;
pub mod customresourcedefinition;
pub mod default;
pub mod deployment;
pub mod fallback;
pub mod horizontalpodautoscaler;
pub mod ingress;
pub mod job;
pub mod node;
pub mod persistentvolumeclaim;
pub mod pod;
pub mod processor;
pub mod replicaset;
pub mod service;
pub mod statefulset;
pub mod storageclass;

use node::NodeProcessor;

use crate::processors::{
    clusterrolebinding::ClusterRoleBindingProcessor, configmap::ConfigmapProcessor,
    cronjob::CronJobProcessor, customresourcedefinition::ClusterResourceDefinitionProcessor,
    default::DefaultProcessor, deployment::DeploymentProcessor, fallback::FallbackProcessor,
    horizontalpodautoscaler::HorizontalPodAutoscalerProcessor, ingress::IngressProcessor,
    job::JobProcessor, persistentvolumeclaim::PersistentVolumeClaimProcessor, pod::PodProcessor,
    processor::DynProcessor, replicaset::ReplicaSetProcessor, service::ServiceProcessor,
    statefulset::StatefulsetProcessor, storageclass::StorageClassProcessor,
};

type ProcessorMap = HashMap<&'static str, Box<dyn DynProcessor>>;

static PROCESSORS: OnceLock<ProcessorMap> = OnceLock::new();

fn processors() -> &'static ProcessorMap {
    PROCESSORS.get_or_init(|| {
        let mut m: ProcessorMap = HashMap::new();
        m.insert("clusterrolebinding", Box::new(ClusterRoleBindingProcessor));
        m.insert("configmap", Box::new(ConfigmapProcessor));
        m.insert("job", Box::new(JobProcessor));
        m.insert("cronjob", Box::new(CronJobProcessor));
        m.insert(
            "customresourcedefinition",
            Box::new(ClusterResourceDefinitionProcessor),
        );
        m.insert("default", Box::new(DefaultProcessor));
        m.insert("deployment", Box::new(DeploymentProcessor));
        m.insert(
            "horizontalpodautoscaler",
            Box::new(HorizontalPodAutoscalerProcessor),
        );
        m.insert("ingress", Box::new(IngressProcessor));
        m.insert("node", Box::new(NodeProcessor));
        m.insert("fallback", Box::new(FallbackProcessor));
        m.insert(
            "persistentvolumeclaim",
            Box::new(PersistentVolumeClaimProcessor),
        );
        m.insert("pod", Box::new(PodProcessor));
        m.insert("replicaset", Box::new(ReplicaSetProcessor));
        m.insert("service", Box::new(ServiceProcessor));
        m.insert("statefulset", Box::new(StatefulsetProcessor));
        m.insert("storageclass", Box::new(StorageClassProcessor));
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
