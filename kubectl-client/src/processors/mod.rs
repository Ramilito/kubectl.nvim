pub mod clusterrolebinding;
pub mod configmap;
pub mod container;
pub mod cronjob;
pub mod customresourcedefinition;
pub mod default;
pub mod deployment;
pub mod fallback;
pub mod horizontalpodautoscaler;
pub mod ingress;
pub mod job;
pub mod namespace;
pub mod node;
pub mod persistentvolume;
pub mod persistentvolumeclaim;
pub mod pod;
pub mod processor;
pub mod replicaset;
pub mod secret;
pub mod service;
pub mod serviceaccount;
pub mod statefulset;
pub mod storageclass;

mod kind;

pub use kind::processor_for;
