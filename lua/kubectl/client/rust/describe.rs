use k8s_openapi::chrono::Utc;
use k8s_openapi::serde_json::json;
use mlua::{Error as LuaError, Lua, Result as LuaResult};
use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};
use std::fmt::{self, Write as FmtWrite};
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tera::{Context, Tera};

use k8s_openapi::{
    api::{
        apps::v1 as apps_v1,
        autoscaling::v1 as autoscaling_v1,
        autoscaling::v2 as autoscaling_v2,
        batch::v1 as batch_v1,
        // batch::v1beta1 as batch_v1beta1,
        // certificates::v1beta1 as cert_v1beta1,
        coordination::v1 as coord_v1,
        core::v1 as core_v1,
        discovery::v1 as discovery_v1,
        // discovery::v1beta1 as discovery_v1beta1,
        // extensions::v1beta1 as ext_v1beta1,
        networking::v1 as net_v1,
        networking::v1beta1 as net_v1beta1,
        policy::v1 as policy_v1,
        // policy::v1beta1 as policy_v1beta1,
        rbac::v1 as rbac_v1,
        scheduling::v1 as sched_v1,
        storage::v1 as storage_v1,
        storage::v1beta1 as storage_v1beta1,
    },
    apimachinery::pkg::{
        apis::meta::v1 as meta_v1,
        // runtime::RawExtension, // if needed
    },
};
use kube::{
    api::{Api, ListParams, Resource, ResourceExt},
    Client,
};

use crate::{CLIENT_INSTANCE, RUNTIME};

static SKIP_ANNOTATIONS: OnceLock<BTreeSet<String>> = OnceLock::new();

fn skip_annotations() -> &'static BTreeSet<String> {
    SKIP_ANNOTATIONS.get_or_init(|| {
        let mut s = BTreeSet::new();
        s.insert("kubectl.kubernetes.io/last-applied-configuration".to_string());
        s
    })
}

pub async fn describe_async(
    lua: Lua,
    args: (String, String, String, String, bool),
) -> LuaResult<String> {
    let (kind, namespace, name, group, show_events) = args;

    let rt_guard = RUNTIME.lock().unwrap();
    let client_guard = CLIENT_INSTANCE.lock().unwrap();
    let rt = rt_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let fut = async {
        let kind = kind.to_lowercase();

        if group.is_empty() && kind == "pod" {
            let text = describe_pod(&client, &namespace, &name, show_events).await?;
            return Ok(text);
            // } else if group == "apps" && kind == "deployment" {
            //     let text = describe_deployment(&client, &namespace, &name, show_events).await?;
            //     return Ok(text);
            // } else if group.is_empty() && kind == "service" {
            //     let text = describe_service(&client, &namespace, &name, show_events).await?;
            //     return Ok(text);
        }
        // and so on for all 30+ references from the snippet
        Err(LuaError::RuntimeError(format!(
            "No describer implemented for group={}, kind={}",
            group, kind
        )))
    };

    rt.block_on(fut)
}

pub async fn describe_pod(
    client: &Client,
    namespace: &str,
    name: &str,
    show_events: bool,
) -> LuaResult<String> {
    let pods: Api<core_v1::Pod> = Api::namespaced(client.clone(), namespace);

    let pod = match pods.get(&name).await {
        Ok(pod) => pod,
        Err(e) => {
            return Ok(format!(
                "No pod named {} in {} found: {}",
                name, namespace, e
            ))
        }
    };

    let tera = match Tera::new("lua/kubectl/client/rust/templates/*.tpl") {
        Ok(t) => t,
        Err(e) => panic!("Template parsing error: {}", e),
    };

    let mut context = Context::new();

    context.insert("name", &pod.metadata.name);
    context.insert(
        "namespace",
        &pod.metadata.namespace.as_deref().unwrap_or("<none>"),
    );
    if let Some(spec) = &pod.spec {
        if let Some(priority) = spec.priority {
            context.insert("priority", &priority);
        }
        if let Some(runtime) = &spec.runtime_class_name {
            context.insert("runtime_class_name", runtime);
        }
        if let Some(sa) = &spec.service_account_name {
            context.insert("service_account_name", sa);
        }
        if let Some(node) = &spec.node_name {
            context.insert("node_name", node);
        } else {
            context.insert("node_name", "<none>");
        }
    }
    if let Some(status) = &pod.status {
        if let Some(msg) = &status.message {
            context.insert("message", msg);
        }
        if let Some(reason) = &status.reason {
            context.insert("reason", reason);
        }
        if let Some(start_time) = &status.start_time {
            context.insert("start_time", &start_time.0.to_rfc2822());
        }

        let mut status_value = status.phase.clone().unwrap_or("Unknown".to_string());
        if let Some(ts) = &pod.metadata.deletion_timestamp {
            if status_value != "Failed" && status_value != "Succeeded" {
                let seconds = Utc::now().signed_duration_since(ts.0).num_seconds();
                status_value = if let Some(grace) = pod.metadata.deletion_grace_period_seconds {
                    format!(
                        "Terminating (lasts {}s)\nTermination Grace Period:\t{}s",
                        seconds, grace
                    )
                } else {
                    format!("Terminating (lasts {}s)", seconds)
                };
            }
        }

        context.insert("status", &status_value);
        if let Some(reason) = &status.reason {
            context.insert("reason", &reason);
        }

        if let Some(message) = &status.message {
            context.insert("reason", &message);
        }
    }

    let labels: BTreeMap<String, String> = pod.metadata.labels.clone().unwrap_or_default();
    context.insert("labels", &labels);
    let annotations: BTreeMap<String, String> =
        pod.metadata.annotations.clone().unwrap_or_default();
    context.insert("annotations", &annotations);

    if let Some(spec) = &pod.spec {
        if let Some(security_context) = &spec.security_context {
            if let Some(seccomp_profile) = &security_context.seccomp_profile {
                if let Some(seccomp_type) = Some(&seccomp_profile.r#type_) {
                    context.insert("seccomp_profile", seccomp_type);
                    if seccomp_type == "Localhost" {
                        if let Some(localhost_profile) = &seccomp_profile.localhost_profile {
                            context.insert("localhost_profile", localhost_profile);
                        }
                    }
                }
            }
        }
    }

    if let Some(status) = &pod.status {
        if let Some(pod_ip) = &status.pod_ip {
            context.insert("ip", pod_ip);
        }
        let pod_ips: Vec<String> = status
            .pod_ips
            .as_ref()
            .map(|ips| ips.iter().map(|ip_info| ip_info.ip.clone()).collect())
            .unwrap_or_default();
        context.insert("pod_ips", &pod_ips);

        if let Some(owner_refs) = &pod.metadata.owner_references {
            if let Some(controller_ref) = owner_refs.iter().find(|r| r.controller.unwrap_or(false))
            {
                context.insert(
                    "controlled_by",
                    &format!("{}/{}", controller_ref.kind, controller_ref.name),
                );
            }
        }

        if let Some(nominated_node_name) = &status.nominated_node_name {
            context.insert("nominated_node_name", nominated_node_name)
        }

        if let Some(spec) = &pod.spec {
            if let Some(container) = spec.containers.first() {
                describe_resources(container.resources.as_ref(), &mut context);
            }
        }
    }

    Ok(tera
        .render("pod_description.tpl", &context)
        .unwrap_or_else(|e| format!("Error rendering template: {}", e)))
}

fn translate_timestamp_since(ts: &meta_v1::Time) -> String {
    let now = Utc::now();
    let delta = now.signed_duration_since(ts.0);
    format!("{}s", delta.num_seconds())
}

fn describe_resources(resources: Option<&core_v1::ResourceRequirements>, context: &mut Context) {
    if let Some(resources) = resources {
        if let Some(limits) = &resources.limits {
            let limits_map: BTreeMap<String, String> = limits
                .iter()
                .map(|(name, quantity)| (name.clone(), quantity.0.to_string()))
                .collect();
            context.insert("limits", &limits_map);
        }
        if let Some(requests) = &resources.requests {
            let requests_map: BTreeMap<String, String> = requests
                .iter()
                .map(|(name, quantity)| (name.clone(), quantity.0.to_string()))
                .collect();
            context.insert("requests", &requests_map);
        }
    }
}
