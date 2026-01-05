use chrono::{DateTime, Utc};
use k8s_openapi::api::apps::v1::{
    DaemonSet, DaemonSetCondition, Deployment, DeploymentCondition, ReplicaSet,
    ReplicaSetCondition, StatefulSet, StatefulSetCondition,
};
use k8s_openapi::api::batch::v1::{CronJob, Job, JobCondition};
use k8s_openapi::api::core::v1::{
    ConfigMap, Container, ContainerState, ContainerStatus, Namespace, Node, PersistentVolume,
    PersistentVolumeClaim, Pod, Secret, Service,
};
use k8s_openapi::api::networking::v1::Ingress;
use k8s_openapi::apimachinery::pkg::apis::meta::v1::OwnerReference;
use k8s_openapi::serde_json::{from_value, to_value};
use kube::api::DynamicObject;

/// Format a resource as markdown for hover display
pub fn format_resource(kind: &str, obj: &DynamicObject) -> String {
    match kind.to_lowercase().as_str() {
        "pod" | "pods" => format_pod(obj),
        "deployment" | "deployments" => format_deployment(obj),
        "statefulset" | "statefulsets" => format_statefulset(obj),
        "daemonset" | "daemonsets" => format_daemonset(obj),
        "replicaset" | "replicasets" => format_replicaset(obj),
        "job" | "jobs" => format_job(obj),
        "cronjob" | "cronjobs" => format_cronjob(obj),
        "service" | "services" => format_service(obj),
        "ingress" | "ingresses" => format_ingress(obj),
        "configmap" | "configmaps" => format_configmap(obj),
        "secret" | "secrets" => format_secret(obj),
        "persistentvolumeclaim" | "persistentvolumeclaims" => format_pvc(obj),
        "persistentvolume" | "persistentvolumes" => format_pv(obj),
        "node" | "nodes" => format_node(obj),
        "namespace" | "namespaces" => format_namespace(obj),
        _ => format_generic(kind, obj),
    }
}

// Helper functions

fn time_since(timestamp: Option<&DateTime<Utc>>) -> String {
    let Some(ts) = timestamp else {
        return "unknown".to_string();
    };
    let duration = Utc::now().signed_duration_since(*ts);
    let secs = duration.num_seconds();
    if secs < 60 {
        format!("{}s", secs)
    } else if secs < 3600 {
        format!("{}m", secs / 60)
    } else if secs < 86400 {
        format!("{}h", secs / 3600)
    } else {
        format!("{}d", secs / 86400)
    }
}

fn format_owner(owners: &Option<Vec<OwnerReference>>) -> Option<String> {
    owners.as_ref().and_then(|o| {
        o.first()
            .map(|owner| format!("`{}/{}`", owner.kind, owner.name))
    })
}

fn format_labels(labels: &Option<std::collections::BTreeMap<String, String>>) -> String {
    let Some(labels) = labels else {
        return "  _none_".to_string();
    };
    if labels.is_empty() {
        return "  _none_".to_string();
    }
    let mut lines: Vec<String> = labels
        .iter()
        .take(8)
        .map(|(k, v)| format!("  `{}={}`", k, v))
        .collect();
    if labels.len() > 8 {
        lines.push(format!("  ... and {} more", labels.len() - 8));
    }
    lines.join("\n")
}

fn format_selector(selector: &std::collections::BTreeMap<String, String>) -> String {
    if selector.is_empty() {
        return "  _none_".to_string();
    }
    selector
        .iter()
        .map(|(k, v)| format!("  `{}={}`", k, v))
        .collect::<Vec<_>>()
        .join("\n")
}

fn format_image(image: &str) -> String {
    // Extract just the image:tag part (last component of path)
    let name = image.rsplit('/').next().unwrap_or(image);
    format!("`{}`", name)
}

fn format_resources(container: &Container) -> Option<String> {
    let resources = container.resources.as_ref()?;
    let mut parts = Vec::new();

    let req = resources.requests.as_ref();
    let lim = resources.limits.as_ref();

    let req_cpu = req.and_then(|r| r.get("cpu")).map(|q| q.0.as_str());
    let lim_cpu = lim.and_then(|l| l.get("cpu")).map(|q| q.0.as_str());
    if req_cpu.is_some() || lim_cpu.is_some() {
        parts.push(format!(
            "cpu: {}/{}",
            req_cpu.unwrap_or("-"),
            lim_cpu.unwrap_or("-")
        ));
    }

    let req_mem = req.and_then(|r| r.get("memory")).map(|q| q.0.as_str());
    let lim_mem = lim.and_then(|l| l.get("memory")).map(|q| q.0.as_str());
    if req_mem.is_some() || lim_mem.is_some() {
        parts.push(format!(
            "mem: {}/{}",
            req_mem.unwrap_or("-"),
            lim_mem.unwrap_or("-")
        ));
    }

    if parts.is_empty() {
        None
    } else {
        Some(parts.join(", "))
    }
}

fn format_container_state(state: &Option<ContainerState>) -> (&str, &'static str) {
    let Some(state) = state else {
        return ("unknown", "○");
    };
    if state.running.is_some() {
        ("running", "●")
    } else if let Some(waiting) = &state.waiting {
        (
            waiting.reason.as_deref().unwrap_or("waiting"),
            "◌",
        )
    } else if let Some(terminated) = &state.terminated {
        (
            terminated.reason.as_deref().unwrap_or("terminated"),
            "○",
        )
    } else {
        ("unknown", "○")
    }
}

fn format_containers(containers: &[Container], statuses: &Option<Vec<ContainerStatus>>) -> String {
    let status_map: std::collections::HashMap<&str, &ContainerStatus> = statuses
        .as_ref()
        .map(|s| s.iter().map(|cs| (cs.name.as_str(), cs)).collect())
        .unwrap_or_default();

    let mut lines = Vec::new();

    for c in containers {
        let status = status_map.get(c.name.as_str());
        let ready = status.map(|s| s.ready).unwrap_or(false);
        let restarts = status.map(|s| s.restart_count).unwrap_or(0);

        let (state_str, base_icon) = status
            .map(|s| format_container_state(&s.state))
            .unwrap_or(("unknown", "○"));

        // Adjust icon for running but not ready
        let icon = if state_str == "running" && !ready {
            "◐"
        } else {
            base_icon
        };

        let ready_str = if ready { "ready" } else { "not ready" };
        let restart_str = if restarts > 0 {
            format!(", {} restarts", restarts)
        } else {
            String::new()
        };

        lines.push(format!(
            "  {} `{}` - {} ({}{})",
            icon, c.name, state_str, ready_str, restart_str
        ));

        // Add image
        if let Some(image) = &c.image {
            lines.push(format!("    image: {}", format_image(image)));
        }

        // Add resources if defined
        if let Some(res) = format_resources(c) {
            lines.push(format!("    resources: {}", res));
        }

        // Add debugging info for failures
        if let Some(s) = status {
            // Show waiting message
            if let Some(waiting) = s.state.as_ref().and_then(|st| st.waiting.as_ref()) {
                if let Some(msg) = &waiting.message {
                    let truncated = if msg.len() > 60 { &msg[..60] } else { msg };
                    lines.push(format!("    _→ {}_", truncated));
                }
            }

            // Show terminated exit code
            if let Some(terminated) = s.state.as_ref().and_then(|st| st.terminated.as_ref()) {
                let exit_code = terminated.exit_code;
                if exit_code != 0 {
                    lines.push(format!("    _→ exit code {}_", exit_code));
                }
            }

            // Show last termination reason if restarted
            if restarts > 0 {
                if let Some(last) = s.last_state.as_ref().and_then(|ls| ls.terminated.as_ref()) {
                    let reason = last.reason.as_deref().unwrap_or("Unknown");
                    let exit_str = format!(" (exit {})", last.exit_code);
                    lines.push(format!("    _→ last: {}{}_", reason, exit_str));
                }
            }
        }
    }

    if lines.is_empty() {
        "_none_".to_string()
    } else {
        lines.join("\n")
    }
}

// Deployment-specific conditions
fn format_deployment_conditions(conditions: &Option<Vec<DeploymentCondition>>) -> String {
    let Some(conditions) = conditions else {
        return "_none_".to_string();
    };
    if conditions.is_empty() {
        return "_none_".to_string();
    }

    let mut lines = Vec::new();
    for c in conditions {
        let icon = if c.status == "True" { "✓" } else { "✗" };
        lines.push(format!("  {} {}", icon, c.type_));

        if c.status != "True" {
            if let Some(reason) = &c.reason {
                lines.push(format!("    _→ {}_", reason));
            }
            if let Some(msg) = &c.message {
                let truncated = if msg.len() > 80 {
                    format!("{}...", &msg[..80])
                } else {
                    msg.clone()
                };
                lines.push(format!("    _→ {}_", truncated));
            }
        }
    }
    lines.join("\n")
}

// StatefulSet-specific conditions
fn format_statefulset_conditions(conditions: &Option<Vec<StatefulSetCondition>>) -> String {
    let Some(conditions) = conditions else {
        return "_none_".to_string();
    };
    if conditions.is_empty() {
        return "_none_".to_string();
    }

    let mut lines = Vec::new();
    for c in conditions {
        let icon = if c.status == "True" { "✓" } else { "✗" };
        lines.push(format!("  {} {}", icon, c.type_));

        if c.status != "True" {
            if let Some(reason) = &c.reason {
                lines.push(format!("    _→ {}_", reason));
            }
            if let Some(msg) = &c.message {
                let truncated = if msg.len() > 80 {
                    format!("{}...", &msg[..80])
                } else {
                    msg.clone()
                };
                lines.push(format!("    _→ {}_", truncated));
            }
        }
    }
    lines.join("\n")
}

// DaemonSet-specific conditions
fn format_daemonset_conditions(conditions: &Option<Vec<DaemonSetCondition>>) -> String {
    let Some(conditions) = conditions else {
        return "_none_".to_string();
    };
    if conditions.is_empty() {
        return "_none_".to_string();
    }

    let mut lines = Vec::new();
    for c in conditions {
        let icon = if c.status == "True" { "✓" } else { "✗" };
        lines.push(format!("  {} {}", icon, c.type_));

        if c.status != "True" {
            if let Some(reason) = &c.reason {
                lines.push(format!("    _→ {}_", reason));
            }
            if let Some(msg) = &c.message {
                let truncated = if msg.len() > 80 {
                    format!("{}...", &msg[..80])
                } else {
                    msg.clone()
                };
                lines.push(format!("    _→ {}_", truncated));
            }
        }
    }
    lines.join("\n")
}

// ReplicaSet-specific conditions
fn format_replicaset_conditions(conditions: &Option<Vec<ReplicaSetCondition>>) -> String {
    let Some(conditions) = conditions else {
        return "_none_".to_string();
    };
    if conditions.is_empty() {
        return "_none_".to_string();
    }

    let mut lines = Vec::new();
    for c in conditions {
        let icon = if c.status == "True" { "✓" } else { "✗" };
        lines.push(format!("  {} {}", icon, c.type_));

        if c.status != "True" {
            if let Some(reason) = &c.reason {
                lines.push(format!("    _→ {}_", reason));
            }
            if let Some(msg) = &c.message {
                let truncated = if msg.len() > 80 {
                    format!("{}...", &msg[..80])
                } else {
                    msg.clone()
                };
                lines.push(format!("    _→ {}_", truncated));
            }
        }
    }
    lines.join("\n")
}

// Job-specific conditions
fn format_job_conditions(conditions: &Option<Vec<JobCondition>>) -> String {
    let Some(conditions) = conditions else {
        return "_none_".to_string();
    };
    if conditions.is_empty() {
        return "_none_".to_string();
    }

    let mut lines = Vec::new();
    for c in conditions {
        let icon = if c.status == "True" { "✓" } else { "✗" };
        lines.push(format!("  {} {}", icon, c.type_));

        if c.status != "True" {
            if let Some(reason) = &c.reason {
                lines.push(format!("    _→ {}_", reason));
            }
            if let Some(msg) = &c.message {
                let truncated = if msg.len() > 80 {
                    format!("{}...", &msg[..80])
                } else {
                    msg.clone()
                };
                lines.push(format!("    _→ {}_", truncated));
            }
        }
    }
    lines.join("\n")
}

// Pod-specific conditions (different type)
fn format_pod_conditions(
    conditions: &Option<Vec<k8s_openapi::api::core::v1::PodCondition>>,
) -> String {
    let Some(conditions) = conditions else {
        return "_none_".to_string();
    };
    if conditions.is_empty() {
        return "_none_".to_string();
    }

    let mut lines = Vec::new();
    for c in conditions {
        let icon = if c.status == "True" { "✓" } else { "✗" };
        lines.push(format!("  {} {}", icon, c.type_));

        if c.status != "True" {
            if let Some(reason) = &c.reason {
                lines.push(format!("    _→ {}_", reason));
            }
            if let Some(msg) = &c.message {
                let truncated = if msg.len() > 80 {
                    format!("{}...", &msg[..80])
                } else {
                    msg.clone()
                };
                lines.push(format!("    _→ {}_", truncated));
            }
        }
    }
    lines.join("\n")
}

// Resource formatters

fn format_pod(obj: &DynamicObject) -> String {
    let Ok(pod) = from_value::<Pod>(to_value(obj).unwrap_or_default()) else {
        return format_generic("Pod", obj);
    };

    let meta = pod.metadata;
    let spec = pod.spec.unwrap_or_default();
    let status = pod.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));
    let phase = status.phase.as_deref().unwrap_or("Unknown");
    let node = spec.node_name.as_deref().unwrap_or("_unscheduled_");
    let ip = status.pod_ip.as_deref().unwrap_or("_none_");
    let qos = status.qos_class.as_deref().unwrap_or("BestEffort");
    let sa = spec.service_account_name.as_deref();
    let owner = format_owner(&meta.owner_references);

    let mut lines = vec![
        format!("## Pod: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!("**Status:** {}", phase),
        format!("**Node:** {}", node),
        format!("**IP:** {}", ip),
        format!("**QoS:** {}", qos),
        format!("**Age:** {}", age),
    ];

    if let Some(o) = owner {
        lines.push(format!("**Controlled By:** {}", o));
    }
    if let Some(s) = sa {
        lines.push(format!("**Service Account:** `{}`", s));
    }

    lines.push(String::new());
    lines.push("### Containers".to_string());
    lines.push(format_containers(
        &spec.containers,
        &status.container_statuses,
    ));

    lines.push(String::new());
    lines.push("### Conditions".to_string());
    lines.push(format_pod_conditions(&status.conditions));

    lines.join("\n")
}

fn format_deployment(obj: &DynamicObject) -> String {
    let Ok(deploy) = from_value::<Deployment>(to_value(obj).unwrap_or_default()) else {
        return format_generic("Deployment", obj);
    };

    let meta = deploy.metadata;
    let spec = deploy.spec.unwrap_or_default();
    let status = deploy.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let replicas = status.replicas.unwrap_or(0);
    let ready = status.ready_replicas.unwrap_or(0);
    let available = status.available_replicas.unwrap_or(0);
    let updated = status.updated_replicas.unwrap_or(0);

    let strategy = spec
        .strategy
        .and_then(|s| s.type_)
        .unwrap_or_else(|| "RollingUpdate".to_string());

    // Get images from template
    let images: Vec<String> = spec
        .template
        .spec
        .map(|s| {
            s.containers
                .iter()
                .filter_map(|c| c.image.as_ref())
                .map(|i| format_image(i))
                .collect()
        })
        .unwrap_or_default();

    // Get selector
    let selector = spec.selector.match_labels.unwrap_or_default();

    let mut lines = vec![
        format!("## Deployment: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!(
            "**Replicas:** {}/{} ready, {} available, {} updated",
            ready, replicas, available, updated
        ),
        format!("**Strategy:** {}", strategy),
        format!("**Age:** {}", age),
    ];

    if !images.is_empty() {
        lines.push(format!("**Images:** {}", images.join(", ")));
    }

    lines.push(String::new());
    lines.push("### Selector".to_string());
    lines.push(format_selector(&selector));

    lines.push(String::new());
    lines.push("### Conditions".to_string());
    lines.push(format_deployment_conditions(&status.conditions));

    lines.join("\n")
}

fn format_statefulset(obj: &DynamicObject) -> String {
    let Ok(sts) = from_value::<StatefulSet>(to_value(obj).unwrap_or_default()) else {
        return format_generic("StatefulSet", obj);
    };

    let meta = sts.metadata;
    let spec = sts.spec.unwrap_or_default();
    let status = sts.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let replicas = status.replicas;
    let ready = status.ready_replicas.unwrap_or(0);
    let current = status.current_replicas.unwrap_or(0);
    let service = spec.service_name.as_deref().unwrap_or("_none_");

    let mut lines = vec![
        format!("## StatefulSet: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!(
            "**Replicas:** {}/{} ready, {} current",
            ready, replicas, current
        ),
        format!("**Service:** {}", service),
        format!("**Age:** {}", age),
    ];

    lines.push(String::new());
    lines.push("### Conditions".to_string());
    lines.push(format_statefulset_conditions(&status.conditions));

    lines.join("\n")
}

fn format_daemonset(obj: &DynamicObject) -> String {
    let Ok(ds) = from_value::<DaemonSet>(to_value(obj).unwrap_or_default()) else {
        return format_generic("DaemonSet", obj);
    };

    let meta = ds.metadata;
    let status = ds.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let desired = status.desired_number_scheduled;
    let current = status.current_number_scheduled;
    let ready = status.number_ready;
    let available = status.number_available.unwrap_or(0);

    let mut lines = vec![
        format!("## DaemonSet: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!("**Desired:** {}", desired),
        format!("**Current:** {}", current),
        format!("**Ready:** {}", ready),
        format!("**Available:** {}", available),
        format!("**Age:** {}", age),
    ];

    lines.push(String::new());
    lines.push("### Conditions".to_string());
    lines.push(format_daemonset_conditions(&status.conditions));

    lines.join("\n")
}

fn format_replicaset(obj: &DynamicObject) -> String {
    let Ok(rs) = from_value::<ReplicaSet>(to_value(obj).unwrap_or_default()) else {
        return format_generic("ReplicaSet", obj);
    };

    let meta = rs.metadata;
    let spec = rs.spec.unwrap_or_default();
    let status = rs.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let replicas = spec.replicas.unwrap_or(0);
    let ready = status.ready_replicas.unwrap_or(0);
    let available = status.available_replicas.unwrap_or(0);
    let owner = format_owner(&meta.owner_references);

    let mut lines = vec![
        format!("## ReplicaSet: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!(
            "**Replicas:** {}/{} ready, {} available",
            ready, replicas, available
        ),
    ];

    if let Some(o) = owner {
        lines.push(format!("**Owner:** {}", o));
    }
    lines.push(format!("**Age:** {}", age));

    lines.push(String::new());
    lines.push("### Conditions".to_string());
    lines.push(format_replicaset_conditions(&status.conditions));

    lines.join("\n")
}

fn format_job(obj: &DynamicObject) -> String {
    let Ok(job) = from_value::<Job>(to_value(obj).unwrap_or_default()) else {
        return format_generic("Job", obj);
    };

    let meta = job.metadata;
    let spec = job.spec.unwrap_or_default();
    let status = job.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let completions = spec.completions.unwrap_or(1);
    let succeeded = status.succeeded.unwrap_or(0);
    let failed = status.failed.unwrap_or(0);
    let active = status.active.unwrap_or(0);

    let duration = if status.completion_time.is_some() && status.start_time.is_some() {
        time_since(status.start_time.as_ref().map(|t| &t.0))
    } else {
        "_running_".to_string()
    };

    let mut lines = vec![
        format!("## Job: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!("**Completions:** {}/{}", succeeded, completions),
        format!("**Active:** {}", active),
        format!("**Failed:** {}", failed),
        format!("**Duration:** {}", duration),
        format!("**Age:** {}", age),
    ];

    lines.push(String::new());
    lines.push("### Conditions".to_string());
    lines.push(format_job_conditions(&status.conditions));

    lines.join("\n")
}

fn format_cronjob(obj: &DynamicObject) -> String {
    let Ok(cj) = from_value::<CronJob>(to_value(obj).unwrap_or_default()) else {
        return format_generic("CronJob", obj);
    };

    let meta = cj.metadata;
    let spec = cj.spec.unwrap_or_default();
    let status = cj.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let schedule = spec.schedule;
    let suspend = spec.suspend.unwrap_or(false);
    let active_count = status.active.map(|a| a.len()).unwrap_or(0);
    let last_schedule = status
        .last_schedule_time
        .as_ref()
        .map(|t| format!("{} ago", time_since(Some(&t.0))))
        .unwrap_or_else(|| "_never_".to_string());

    vec![
        format!("## CronJob: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!("**Schedule:** `{}`", schedule),
        format!("**Suspend:** {}", if suspend { "yes" } else { "no" }),
        format!("**Active Jobs:** {}", active_count),
        format!("**Last Schedule:** {}", last_schedule),
        format!("**Age:** {}", age),
    ]
    .join("\n")
}

fn format_service(obj: &DynamicObject) -> String {
    let Ok(svc) = from_value::<Service>(to_value(obj).unwrap_or_default()) else {
        return format_generic("Service", obj);
    };

    let meta = svc.metadata;
    let spec = svc.spec.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let svc_type = spec.type_.as_deref().unwrap_or("ClusterIP");
    let cluster_ip = spec.cluster_ip.as_deref().unwrap_or("_none_");

    let ports: Vec<String> = spec
        .ports
        .unwrap_or_default()
        .iter()
        .map(|p| {
            let target = p.target_port.as_ref().map(|tp| match tp {
                k8s_openapi::apimachinery::pkg::util::intstr::IntOrString::Int(i) => i.to_string(),
                k8s_openapi::apimachinery::pkg::util::intstr::IntOrString::String(s) => s.clone(),
            });
            let port_str = target
                .map(|t| format!("{}→{}", p.port, t))
                .unwrap_or_else(|| p.port.to_string());
            format!("`{}/{}`", port_str, p.protocol.as_deref().unwrap_or("TCP"))
        })
        .collect();

    let selector = spec.selector.unwrap_or_default();

    let mut lines = vec![
        format!("## Service: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!("**Type:** {}", svc_type),
        format!("**ClusterIP:** {}", cluster_ip),
        format!(
            "**Ports:** {}",
            if ports.is_empty() {
                "_none_".to_string()
            } else {
                ports.join(", ")
            }
        ),
        format!("**Age:** {}", age),
    ];

    lines.push(String::new());
    lines.push("### Selector".to_string());
    lines.push(format_selector(&selector));

    lines.join("\n")
}

fn format_ingress(obj: &DynamicObject) -> String {
    let Ok(ing) = from_value::<Ingress>(to_value(obj).unwrap_or_default()) else {
        return format_generic("Ingress", obj);
    };

    let meta = ing.metadata;
    let spec = ing.spec.unwrap_or_default();
    let status = ing.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let class = spec.ingress_class_name.as_deref().unwrap_or("_default_");

    let hosts: Vec<String> = spec
        .rules
        .unwrap_or_default()
        .iter()
        .filter_map(|r| r.host.as_ref())
        .map(|h| format!("`{}`", h))
        .collect();

    let addresses: Vec<String> = status
        .load_balancer
        .and_then(|lb| lb.ingress)
        .unwrap_or_default()
        .iter()
        .map(|i| {
            i.ip.clone()
                .or_else(|| i.hostname.clone())
                .unwrap_or_else(|| "pending".to_string())
        })
        .collect();

    vec![
        format!("## Ingress: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!("**Class:** {}", class),
        format!(
            "**Hosts:** {}",
            if hosts.is_empty() {
                "_none_".to_string()
            } else {
                hosts.join(", ")
            }
        ),
        format!(
            "**Address:** {}",
            if addresses.is_empty() {
                "_pending_".to_string()
            } else {
                addresses.join(", ")
            }
        ),
        format!("**Age:** {}", age),
    ]
    .join("\n")
}

fn format_configmap(obj: &DynamicObject) -> String {
    let Ok(cm) = from_value::<ConfigMap>(to_value(obj).unwrap_or_default()) else {
        return format_generic("ConfigMap", obj);
    };

    let meta = cm.metadata;
    let data_keys: Vec<String> = cm
        .data
        .map(|d| d.keys().cloned().collect())
        .unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let mut lines = vec![
        format!("## ConfigMap: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!("**Keys:** {}", data_keys.len()),
        format!("**Age:** {}", age),
        String::new(),
        "### Data Keys".to_string(),
    ];

    if data_keys.is_empty() {
        lines.push("  _empty_".to_string());
    } else {
        for (i, key) in data_keys.iter().enumerate() {
            if i >= 10 {
                lines.push(format!("  ... and {} more", data_keys.len() - 10));
                break;
            }
            lines.push(format!("  - `{}`", key));
        }
    }

    lines.join("\n")
}

fn format_secret(obj: &DynamicObject) -> String {
    let Ok(secret) = from_value::<Secret>(to_value(obj).unwrap_or_default()) else {
        return format_generic("Secret", obj);
    };

    let meta = secret.metadata;
    let data_keys: Vec<String> = secret
        .data
        .map(|d| d.keys().cloned().collect())
        .unwrap_or_default();
    let secret_type = secret.type_.as_deref().unwrap_or("Opaque");

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let mut lines = vec![
        format!("## Secret: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!("**Type:** {}", secret_type),
        format!("**Keys:** {}", data_keys.len()),
        format!("**Age:** {}", age),
        String::new(),
        "### Data Keys".to_string(),
    ];

    if data_keys.is_empty() {
        lines.push("  _empty_".to_string());
    } else {
        for (i, key) in data_keys.iter().enumerate() {
            if i >= 10 {
                lines.push(format!("  ... and {} more", data_keys.len() - 10));
                break;
            }
            lines.push(format!("  - `{}`", key));
        }
    }

    lines.join("\n")
}

fn format_pvc(obj: &DynamicObject) -> String {
    let Ok(pvc) = from_value::<PersistentVolumeClaim>(to_value(obj).unwrap_or_default()) else {
        return format_generic("PersistentVolumeClaim", obj);
    };

    let meta = pvc.metadata;
    let spec = pvc.spec.unwrap_or_default();
    let status = pvc.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref().unwrap_or("default");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let phase = status.phase.as_deref().unwrap_or("Unknown");
    let volume = spec.volume_name.as_deref().unwrap_or("_pending_");
    let capacity = status
        .capacity
        .and_then(|c| c.get("storage").map(|q| q.0.clone()))
        .unwrap_or_else(|| "_unknown_".to_string());
    let access_modes = spec
        .access_modes
        .map(|m| m.join(", "))
        .unwrap_or_else(|| "_none_".to_string());
    let storage_class = spec.storage_class_name.as_deref().unwrap_or("_default_");

    vec![
        format!("## PersistentVolumeClaim: {}", name),
        String::new(),
        format!("**Namespace:** {}", namespace),
        format!("**Status:** {}", phase),
        format!("**Volume:** {}", volume),
        format!("**Capacity:** {}", capacity),
        format!("**Access Modes:** {}", access_modes),
        format!("**Storage Class:** {}", storage_class),
        format!("**Age:** {}", age),
    ]
    .join("\n")
}

fn format_pv(obj: &DynamicObject) -> String {
    let Ok(pv) = from_value::<PersistentVolume>(to_value(obj).unwrap_or_default()) else {
        return format_generic("PersistentVolume", obj);
    };

    let meta = pv.metadata;
    let spec = pv.spec.unwrap_or_default();
    let status = pv.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));

    let phase = status.phase.as_deref().unwrap_or("Unknown");
    let claim = spec
        .claim_ref
        .as_ref()
        .map(|c| {
            format!(
                "`{}/{}`",
                c.namespace.as_deref().unwrap_or(""),
                c.name.as_deref().unwrap_or("")
            )
        })
        .unwrap_or_else(|| "_none_".to_string());
    let capacity = spec
        .capacity
        .and_then(|c| c.get("storage").map(|q| q.0.clone()))
        .unwrap_or_else(|| "_unknown_".to_string());
    let access_modes = spec
        .access_modes
        .map(|m| m.join(", "))
        .unwrap_or_else(|| "_none_".to_string());
    let reclaim = spec
        .persistent_volume_reclaim_policy
        .as_deref()
        .unwrap_or("_unknown_");
    let storage_class = spec.storage_class_name.as_deref().unwrap_or("_none_");

    vec![
        format!("## PersistentVolume: {}", name),
        String::new(),
        format!("**Status:** {}", phase),
        format!("**Claim:** {}", claim),
        format!("**Capacity:** {}", capacity),
        format!("**Access Modes:** {}", access_modes),
        format!("**Reclaim Policy:** {}", reclaim),
        format!("**Storage Class:** {}", storage_class),
        format!("**Age:** {}", age),
    ]
    .join("\n")
}

fn format_node(obj: &DynamicObject) -> String {
    let Ok(node) = from_value::<Node>(to_value(obj).unwrap_or_default()) else {
        return format_generic("Node", obj);
    };

    let meta = node.metadata;
    let spec = node.spec.unwrap_or_default();
    let status = node.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));
    let unschedulable = spec.unschedulable.unwrap_or(false);

    let addresses: Vec<String> = status
        .addresses
        .unwrap_or_default()
        .iter()
        .filter(|a| a.type_ == "InternalIP" || a.type_ == "ExternalIP")
        .map(|a| format!("{}: {}", a.type_, a.address))
        .collect();

    // Node conditions are a different type
    let conditions = status.conditions.unwrap_or_default();
    let mut cond_lines = Vec::new();
    for c in conditions {
        let icon = if c.status == "True" { "✓" } else { "✗" };
        cond_lines.push(format!("  {} {}", icon, c.type_));
        if c.status != "True" {
            if let Some(reason) = &c.reason {
                cond_lines.push(format!("    _→ {}_", reason));
            }
        }
    }

    let mut lines = vec![
        format!("## Node: {}", name),
        String::new(),
        format!(
            "**Unschedulable:** {}",
            if unschedulable { "yes" } else { "no" }
        ),
        format!("**Age:** {}", age),
        String::new(),
        "### Addresses".to_string(),
    ];

    if addresses.is_empty() {
        lines.push("  _none_".to_string());
    } else {
        for addr in addresses {
            lines.push(format!("  - {}", addr));
        }
    }

    lines.push(String::new());
    lines.push("### Conditions".to_string());
    if cond_lines.is_empty() {
        lines.push("  _none_".to_string());
    } else {
        lines.extend(cond_lines);
    }

    lines.join("\n")
}

fn format_namespace(obj: &DynamicObject) -> String {
    let Ok(ns) = from_value::<Namespace>(to_value(obj).unwrap_or_default()) else {
        return format_generic("Namespace", obj);
    };

    let meta = ns.metadata;
    let status = ns.status.unwrap_or_default();

    let name = meta.name.as_deref().unwrap_or("unknown");
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));
    let phase = status.phase.as_deref().unwrap_or("Unknown");

    vec![
        format!("## Namespace: {}", name),
        String::new(),
        format!("**Status:** {}", phase),
        format!("**Age:** {}", age),
        String::new(),
        "### Labels".to_string(),
        format_labels(&meta.labels),
    ]
    .join("\n")
}

fn format_generic(kind: &str, obj: &DynamicObject) -> String {
    let meta = &obj.metadata;
    let name = meta.name.as_deref().unwrap_or("unknown");
    let namespace = meta.namespace.as_deref();
    let age = time_since(meta.creation_timestamp.as_ref().map(|t| &t.0));
    let owner = format_owner(&meta.owner_references);

    let mut lines = vec![format!("## {}: {}", kind, name), String::new()];

    if let Some(ns) = namespace {
        lines.push(format!("**Namespace:** {}", ns));
    }
    lines.push(format!("**Age:** {}", age));

    if let Some(o) = owner {
        lines.push(format!("**Owner:** {}", o));
    }

    lines.push(String::new());
    lines.push("### Labels".to_string());
    lines.push(format_labels(&meta.labels));

    lines.join("\n")
}
