//! Custom metrics types for k8s-openapi 0.27+ compatibility.
//! These replace k8s-metrics crate types which are pinned to older k8s-openapi.

use std::borrow::Cow;

use k8s_openapi::apimachinery::pkg::api::resource::Quantity;
use k8s_openapi::apimachinery::pkg::apis::meta::v1::ObjectMeta;
use kube::Resource;
use serde::{Deserialize, Serialize};

/// Resource usage for a container.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ContainerMetrics {
    pub name: String,
    pub usage: ResourceList,
}

/// Resource quantities (cpu, memory, etc).
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ResourceList {
    #[serde(default)]
    pub cpu: Quantity,
    #[serde(default)]
    pub memory: Quantity,
}

/// NodeMetrics - metrics for a single node
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NodeMetrics {
    pub metadata: ObjectMeta,
    pub timestamp: Option<String>,
    pub window: Option<String>,
    pub usage: ResourceList,
}

impl Resource for NodeMetrics {
    type DynamicType = ();
    type Scope = kube::core::ClusterResourceScope;

    fn kind(_: &Self::DynamicType) -> Cow<'static, str> {
        Cow::Borrowed("NodeMetrics")
    }

    fn group(_: &Self::DynamicType) -> Cow<'static, str> {
        Cow::Borrowed("metrics.k8s.io")
    }

    fn version(_: &Self::DynamicType) -> Cow<'static, str> {
        Cow::Borrowed("v1beta1")
    }

    fn plural(_: &Self::DynamicType) -> Cow<'static, str> {
        Cow::Borrowed("nodes")
    }

    fn meta(&self) -> &ObjectMeta {
        &self.metadata
    }

    fn meta_mut(&mut self) -> &mut ObjectMeta {
        &mut self.metadata
    }
}

/// PodMetrics - metrics for a single pod
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PodMetrics {
    pub metadata: ObjectMeta,
    pub timestamp: Option<String>,
    pub window: Option<String>,
    pub containers: Vec<ContainerMetrics>,
}

impl Resource for PodMetrics {
    type DynamicType = ();
    type Scope = kube::core::NamespaceResourceScope;

    fn kind(_: &Self::DynamicType) -> Cow<'static, str> {
        Cow::Borrowed("PodMetrics")
    }

    fn group(_: &Self::DynamicType) -> Cow<'static, str> {
        Cow::Borrowed("metrics.k8s.io")
    }

    fn version(_: &Self::DynamicType) -> Cow<'static, str> {
        Cow::Borrowed("v1beta1")
    }

    fn plural(_: &Self::DynamicType) -> Cow<'static, str> {
        Cow::Borrowed("pods")
    }

    fn meta(&self) -> &ObjectMeta {
        &self.metadata
    }

    fn meta_mut(&mut self) -> &mut ObjectMeta {
        &mut self.metadata
    }
}

// Quantity parsing helpers

/// Parse Kubernetes CPU quantity string to cores as f64
pub fn parse_cpu_to_cores(s: &str) -> Option<f64> {
    if let Some(n) = s.strip_suffix('m') {
        n.parse::<f64>().ok().map(|v| v / 1000.0)
    } else if let Some(n) = s.strip_suffix('n') {
        n.parse::<f64>().ok().map(|v| v / 1_000_000_000.0)
    } else if let Some(n) = s.strip_suffix('u') {
        n.parse::<f64>().ok().map(|v| v / 1_000_000.0)
    } else {
        s.parse::<f64>().ok()
    }
}

/// Parse Kubernetes memory quantity string to bytes as i64
pub fn parse_memory_to_bytes(s: &str) -> Option<i64> {
    let suffixes: &[(&str, i64)] = &[
        ("Ei", 1024 * 1024 * 1024 * 1024 * 1024 * 1024),
        ("Pi", 1024 * 1024 * 1024 * 1024 * 1024),
        ("Ti", 1024 * 1024 * 1024 * 1024),
        ("Gi", 1024 * 1024 * 1024),
        ("Mi", 1024 * 1024),
        ("Ki", 1024),
        ("E", 1000 * 1000 * 1000 * 1000 * 1000 * 1000),
        ("P", 1000 * 1000 * 1000 * 1000 * 1000),
        ("T", 1000 * 1000 * 1000 * 1000),
        ("G", 1000 * 1000 * 1000),
        ("M", 1000 * 1000),
        ("K", 1000),
        ("k", 1000),
    ];

    for (suffix, multiplier) in suffixes {
        if let Some(n) = s.strip_suffix(suffix) {
            return n.parse::<f64>().ok().map(|v| (v * (*multiplier as f64)).round() as i64);
        }
    }

    s.parse::<i64>().ok()
}
