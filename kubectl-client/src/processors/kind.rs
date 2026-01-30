use std::str::FromStr;
use std::sync::Arc;

use k8s_openapi::serde_json;
use kube::api::DynamicObject;
use mlua::{Lua, Result as LuaResult};
use tracing::{span, Level};

use crate::structs::Gvk;

use super::{
    clusterrole::ClusterRoleProcessor, clusterrolebinding::ClusterRoleBindingProcessor,
    configmap::ConfigmapProcessor, container::ContainerProcessor, cronjob::CronJobProcessor,
    customresourcedefinition::ClusterResourceDefinitionProcessor, daemonset::DaemonsetProcessor,
    default::DefaultProcessor, deployment::DeploymentProcessor, event::EventProcessor,
    fallback::FallbackProcessor, horizontalpodautoscaler::HorizontalPodAutoscalerProcessor,
    ingress::IngressProcessor, job::JobProcessor, namespace::NamespaceProcessor,
    node::NodeProcessor, persistentvolume::PersistentVolumeProcessor,
    persistentvolumeclaim::PersistentVolumeClaimProcessor, pod::PodProcessor,
    processor::{FilterParams, Processor},
    replicaset::ReplicaSetProcessor, secret::SecretProcessor, service::ServiceProcessor,
    serviceaccount::ServiceAccountProcessor, statefulset::StatefulsetProcessor,
    storageclass::StorageClassProcessor,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProcessorKind {
    ClusterRoleBinding,
    ClusterRole,
    ConfigMap,
    Container,
    Event,
    CronJob,
    CustomResourceDefinition,
    DaemonSet,
    Default,
    Deployment,
    Fallback,
    HorizontalPodAutoscaler,
    Ingress,
    Job,
    Node,
    Namespace,
    PersistentVolume,
    PersistentVolumeClaim,
    Pod,
    ReplicaSet,
    Secret,
    Service,
    ServiceAccount,
    StatefulSet,
    StorageClass,
}

impl FromStr for ProcessorKind {
    type Err = ();

    #[tracing::instrument]
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(match s {
            "clusterrole" => Self::ClusterRole,
            "event" => Self::Event,
            "clusterrolebinding" => Self::ClusterRoleBinding,
            "configmap" => Self::ConfigMap,
            "container" => Self::Container,
            "cronjob" => Self::CronJob,
            "customresourcedefinition" => Self::CustomResourceDefinition,
            "daemonset" => Self::DaemonSet,
            "deployment" => Self::Deployment,
            "horizontalpodautoscaler" => Self::HorizontalPodAutoscaler,
            "ingress" => Self::Ingress,
            "job" => Self::Job,
            "node" => Self::Node,
            "namespace" => Self::Namespace,
            "persistentvolume" => Self::PersistentVolume,
            "persistentvolumeclaim" => Self::PersistentVolumeClaim,
            "pod" => Self::Pod,
            "replicaset" => Self::ReplicaSet,
            "secret" => Self::Secret,
            "service" => Self::Service,
            "serviceaccount" => Self::ServiceAccount,
            "statefulset" => Self::StatefulSet,
            "storageclass" => Self::StorageClass,
            "fallback" => Self::Fallback,
            _ => Self::Default, // unknown → default
        })
    }
}

#[inline]
#[tracing::instrument]
pub fn processor_for(kind: &str) -> ProcessorKind {
    kind.parse().unwrap_or(ProcessorKind::Default)
}

#[tracing::instrument(skip(proc_impl, items))]
fn run<P: Processor>(
    proc_impl: &P,
    items: &[Arc<DynamicObject>],
    params: &FilterParams,
) -> LuaResult<String> {
    let rows = proc_impl.process(items, params)?;

    let _json_span = span!(Level::INFO, "json_convert").entered();

    serde_json::to_string(&rows).map_err(|e| mlua::Error::RuntimeError(e.to_string()))
}

impl ProcessorKind {
    #[tracing::instrument]
    pub fn process_fallback(
        &self,
        lua: &Lua,
        gvk: Gvk,
        ns: Option<String>,
        params: &FilterParams,
    ) -> LuaResult<mlua::Value> {
        match self {
            ProcessorKind::Fallback => {
                FallbackProcessor.process_fallback(lua, gvk, ns, params)
            }
            _ => Err(mlua::Error::external(
                "process_fallback is implemented only for the fallback processor",
            )),
        }
    }

    pub fn process(
        &self,
        items: &[Arc<DynamicObject>],
        params: &FilterParams,
    ) -> LuaResult<String> {
        use ProcessorKind::*;
        match self {
            ClusterRole => run(&ClusterRoleProcessor, items, params),
            ClusterRoleBinding => run(&ClusterRoleBindingProcessor, items, params),
            ConfigMap => run(&ConfigmapProcessor, items, params),
            Container => run(&ContainerProcessor, items, params),
            CronJob => run(&CronJobProcessor, items, params),
            CustomResourceDefinition => run(&ClusterResourceDefinitionProcessor, items, params),
            DaemonSet => run(&DaemonsetProcessor, items, params),
            Default => run(&DefaultProcessor, items, params),
            Deployment => run(&DeploymentProcessor, items, params),
            Event => run(&EventProcessor, items, params),
            Fallback => run(&FallbackProcessor, items, params),
            HorizontalPodAutoscaler => run(&HorizontalPodAutoscalerProcessor, items, params),
            Ingress => run(&IngressProcessor, items, params),
            Job => run(&JobProcessor, items, params),
            Namespace => run(&NamespaceProcessor, items, params),
            Node => run(&NodeProcessor, items, params),
            PersistentVolume => run(&PersistentVolumeProcessor, items, params),
            PersistentVolumeClaim => run(&PersistentVolumeClaimProcessor, items, params),
            Pod => run(&PodProcessor, items, params),
            ReplicaSet => run(&ReplicaSetProcessor, items, params),
            Secret => run(&SecretProcessor, items, params),
            Service => run(&ServiceProcessor, items, params),
            ServiceAccount => run(&ServiceAccountProcessor, items, params),
            StatefulSet => run(&StatefulsetProcessor, items, params),
            StorageClass => run(&StorageClassProcessor, items, params),
        }
    }
}
