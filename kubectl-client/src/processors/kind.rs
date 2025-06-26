use std::str::FromStr;

use k8s_openapi::serde_json;
use kube::api::DynamicObject;
use mlua::{Lua, Result as LuaResult};
use tracing::{span, Level};

use super::{
    clusterrolebinding::ClusterRoleBindingProcessor, configmap::ConfigmapProcessor,
    container::ContainerProcessor, cronjob::CronJobProcessor,
    customresourcedefinition::ClusterResourceDefinitionProcessor, default::DefaultProcessor,
    deployment::DeploymentProcessor, fallback::FallbackProcessor,
    horizontalpodautoscaler::HorizontalPodAutoscalerProcessor, ingress::IngressProcessor,
    job::JobProcessor, node::NodeProcessor, persistentvolume::PersistentVolumeProcessor,
    persistentvolumeclaim::PersistentVolumeClaimProcessor, pod::PodProcessor, processor::Processor,
    replicaset::ReplicaSetProcessor, secret::SecretProcessor, service::ServiceProcessor,
    serviceaccount::ServiceAccountProcessor, statefulset::StatefulsetProcessor,
    storageclass::StorageClassProcessor,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProcessorKind {
    ClusterRoleBinding,
    ConfigMap,
    Container,
    CronJob,
    CustomResourceDefinition,
    Default,
    Deployment,
    Fallback,
    HorizontalPodAutoscaler,
    Ingress,
    Job,
    Node,
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

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(match s {
            "clusterrolebinding" => Self::ClusterRoleBinding,
            "configmap" => Self::ConfigMap,
            "container" => Self::Container,
            "cronjob" => Self::CronJob,
            "customresourcedefinition" => Self::CustomResourceDefinition,
            "deployment" => Self::Deployment,
            "horizontalpodautoscaler" => Self::HorizontalPodAutoscaler,
            "ingress" => Self::Ingress,
            "job" => Self::Job,
            "node" => Self::Node,
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
pub fn processor_for(kind: &str) -> ProcessorKind {
    kind.parse().unwrap_or(ProcessorKind::Default)
}

#[tracing::instrument(skip(proc_impl, lua, items))]
fn run<P: Processor>(
    proc_impl: &P,
    lua: &Lua,
    items: &[DynamicObject],
    sort_by: Option<String>,
    sort_order: Option<String>,
    filter: Option<String>,
    filter_label: Option<Vec<String>>,
    filter_key: Option<String>,
) -> LuaResult<String> {
    let rows = proc_impl.process(items, sort_by, sort_order, filter, filter_label, filter_key)?;

    let json_span = span!(Level::INFO, "json_convert").entered();

    let mut buf = Vec::with_capacity(rows.len().saturating_mul(512).max(4 * 1024));
    serde_json::to_writer(&mut buf, &rows).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    let json_str = lua.create_string(&buf)?.to_str()?.to_owned();
    json_span.record("out_bytes", json_str.len() as u64);

    Ok(json_str)
}

impl ProcessorKind {
    pub fn process_fallback(
        &self,
        lua: &Lua,
        name: String,
        ns: Option<String>,
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
        filter_label: Option<Vec<String>>,
        filter_key: Option<String>,
    ) -> LuaResult<mlua::Value> {
        use ProcessorKind::*;
        match self {
            Fallback => FallbackProcessor.process_fallback(
                lua,
                name,
                ns,
                sort_by,
                sort_order,
                filter,
                filter_label,
                filter_key,
            ),
            _ => Err(mlua::Error::external(
                "process_fallback is implemented only for the fallback processor",
            )),
        }
    }
    #[rustfmt::skip]
    pub fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
        filter_label: Option<Vec<String>>,
        filter_key: Option<String>,
    ) -> LuaResult<String> {
        use ProcessorKind::*;
        match self {
            ClusterRoleBinding => run(&ClusterRoleBindingProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            ConfigMap => run(&ConfigmapProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Container => run(&ContainerProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            CronJob => run(&CronJobProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            CustomResourceDefinition => run(&ClusterResourceDefinitionProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Default => run(&DefaultProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Deployment => run(&DeploymentProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Fallback => run(&FallbackProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            HorizontalPodAutoscaler => run(&HorizontalPodAutoscalerProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Ingress => run(&IngressProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Job => run(&JobProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Node => run(&NodeProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            PersistentVolume => run(&PersistentVolumeProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            PersistentVolumeClaim => run(&PersistentVolumeClaimProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Pod => run(&PodProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            ReplicaSet => run(&ReplicaSetProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Secret => run(&SecretProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            Service => run(&ServiceProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            ServiceAccount => run(&ServiceAccountProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            StatefulSet => run(&StatefulsetProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
            StorageClass => run(&StorageClassProcessor, lua, items, sort_by, sort_order, filter, filter_label.clone(), filter_key.clone()),
        }
    }
}
