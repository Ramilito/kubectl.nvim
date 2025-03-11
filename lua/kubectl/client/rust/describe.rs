use k8s_openapi::chrono::Utc;
use mlua::{Error as LuaError, Lua, Result as LuaResult};
use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};
use std::fmt::{self, Write as FmtWrite};
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

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

// The original code had constants like LEVEL_0..LEVEL_4 for indentation
const LEVEL_0: usize = 0;
const LEVEL_1: usize = 1;
const LEVEL_2: usize = 2;
const LEVEL_3: usize = 3;
const LEVEL_4: usize = 4;

// We'll define a "PrefixWriter" trait, plus a real implementation for it
pub trait PrefixWriter {
    fn write_line(&mut self, line: &str);
    fn write(&mut self, level: usize, text: &str);
    fn flush(&mut self);
}

pub struct SimplePrefixWriter {
    buffer: String,
}

impl SimplePrefixWriter {
    pub fn new() -> Self {
        Self {
            buffer: String::new(),
        }
    }
    pub fn into_string(self) -> String {
        self.buffer
    }
}

fn level_spaces(level: usize) -> &'static str {
    match level {
        0 => "",
        1 => "  ",
        2 => "    ",
        3 => "      ",
        4 => "        ",
        _ => "        ", // clamp
    }
}

impl PrefixWriter for SimplePrefixWriter {
    fn write_line(&mut self, line: &str) {
        let _ = writeln!(self.buffer, "{}", line);
    }
    fn write(&mut self, level: usize, text: &str) {
        let _ = write!(self.buffer, "{}{}", level_spaces(level), text);
    }
    fn flush(&mut self) {
        // no-op
    }
}

fn translate_timestamp_since(ts: &meta_v1::Time) -> String {
    let now = Utc::now();
    let delta = now.signed_duration_since(ts.0);
    format!("{}s", delta.num_seconds())
}

fn print_labels_multiline(w: &mut dyn PrefixWriter, title: &str, labels: &BTreeMap<String, String>) {
    w.write(LEVEL_0, &format!("{}:\t", title));
    if labels.is_empty() {
        w.write_line("<none>");
    } else {
        for (k, v) in labels {
            w.write_line(&format!("{}={}", k, v));
        }
    }
}

fn print_annotations_multiline(w: &mut dyn PrefixWriter, title: &str, annotations: &BTreeMap<String, String>) {
    w.write(LEVEL_0, &format!("{}:\t", title));
    if annotations.is_empty() {
        w.write_line("<none>");
    } else {
        for (k, v) in annotations {
            // Here we use our OnceCell-based skip set (assume skip_annotations() is defined)
            if skip_annotations().contains(k) {
                continue;
            }
            w.write_line(&format!("{}: {}", k, v));
        }
    }
}

pub async fn describe_sync(
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
        } else if group == "apps" && kind == "deployment" {
            let text = describe_deployment(&client, &namespace, &name, show_events).await?;
            return Ok(text);
        } else if group.is_empty() && kind == "service" {
            let text = describe_service(&client, &namespace, &name, show_events).await?;
            return Ok(text);
        }
        // and so on for all 30+ references from the snippet
        Err(LuaError::RuntimeError(format!(
            "No describer implemented for group={}, kind={}",
            group, kind
        )))
    };

    rt.block_on(fut)
}

// The snippet's logic for describing events
// We'll do a function "search_events" that tries to fetch events from the cluster
async fn search_events<T: Resource<Scope = k8s_openapi::NamespaceResourceScope>>(
    client: &Client,
    resource: &T,
    limit: u32,
) -> LuaResult<Vec<core_v1::Event>> {
    // In the snippet, it constructs a fieldSelector for e.g. "involvedObject.kind=<KIND>, involvedObject.name=<NAME>" etc.
    // We'll do a simplified approach: "involvedObject.name={resource.name()}" only
    let name = resource.name_any();
    let ns = resource.namespace().unwrap_or_default();
    let events_api: Api<core_v1::Event> = Api::namespaced(client.clone(), &ns);
    let lp = ListParams::default()
        .fields(&format!("involvedObject.name={}", name))
        .limit(limit);
    let ev_list = events_api
        .list(&lp)
        .await
        .map_err(|e| LuaError::RuntimeError(format!("Error listing events: {}", e)))?;
    Ok(ev_list.items)
}

/// Print a list of events
fn describe_events(events: &[core_v1::Event], w: &mut dyn PrefixWriter) {
    if events.is_empty() {
        w.write(LEVEL_0, "Events:\t<none>\n");
        return;
    }
    w.write_line("Events:");
    w.write_line("  Type\tReason\tAge\tMessage");
    for e in events {
        let etype = e.type_.clone().unwrap_or_default();
        let reason = e.reason.clone().unwrap_or_default();
        let msg = e.message.clone().unwrap_or_default();

        let age = if let Some(ts) = e.last_timestamp.as_ref() {
            let now = Utc::now();
            let delta = now.signed_duration_since(&ts.0);
            format!("{}s", delta.num_seconds())
        } else {
            "<unknown>".into()
        };

        w.write_line(&format!("  {}\t{}\t{}\t{}", etype, reason, age, msg));
    }
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

    // gather events if needed
    let events = if show_events {
        let e = search_events(client, &pod, 50).await?;
        Some(e)
    } else {
        None
    };

    // Now replicate the snippet's logic:
    let mut w = SimplePrefixWriter::new();
    w.write_line(&format!("Name:\t{}", pod.name_any()));
    w.write_line(&format!("Namespace:\t{}", namespace));

    // Priority, runtimeClassName, etc. We do partial for demonstration
    if let Some(spec) = &pod.spec {
        if let Some(p) = spec.priority {
            w.write_line(&format!("Priority:\t{}", p));
        }
        if let Some(rc) = &spec.runtime_class_name {
            w.write_line(&format!("RuntimeClassName:\t{}", rc));
        }
    }
    // Labels
    if let Some(labels) = &pod.metadata.labels {
        if labels.is_empty() {
            w.write_line("Labels:\t<none>");
        } else {
            w.write_line("Labels:");
            for (k, v) in labels {
                w.write_line(&format!("  {}={}", k, v));
            }
        }
    }

    if let Some(ann) = &pod.metadata.annotations {
        if ann.is_empty() {
            w.write_line("Annotations:\t<none>");
        } else {
            w.write_line("Annotations:");
            for (k, v) in ann {
                if skip_annotations().contains(k) {
                    continue;
                }
                w.write_line(&format!("  {}={}", k, v));
            }
        }
    }
    if let Some(status) = &pod.status {
        w.write_line(&format!(
            "Phase:\t{}",
            status.phase.clone().unwrap_or_default()
        ));
        if let Some(m) = &status.message {
            if !m.is_empty() {
                w.write_line(&format!("Message:\t{}", m));
            }
        }
        if let Some(r) = &status.reason {
            if !r.is_empty() {
                w.write_line(&format!("Reason:\t{}", r));
            }
        }
    }

    if let Some(spec) = &pod.spec {
        if !spec.containers.is_empty() {
            w.write_line("Containers:");
            for c in &spec.containers {
                w.write_line(&format!("  {}", c.name));
            }
        } else {
            w.write_line("Containers:\t<none>");
        }
    }

    if let Some(ev) = events {
        w.write_line("");
        describe_events(&ev, &mut w);
    }

    Ok(w.into_string())
}

pub async fn describe_deployment(
    client: &Client,
    namespace: &str,
    name: &str,
    show_events: bool,
) -> LuaResult<String> {
    let deployments: Api<apps_v1::Deployment> = Api::namespaced(client.clone(), namespace);
    let depl = deployments
        .get(name)
        .await
        .map_err(|e| LuaError::RuntimeError(format!("Error retrieving Deployment: {}", e)))?;

    let events = if show_events {
        Some(search_events(client, &depl, 50).await?)
    } else {
        None
    };

    let mut w = SimplePrefixWriter::new();
    w.write_line(&format!("Name:\t{}", depl.name_any()));
    w.write_line(&format!("Namespace:\t{}", namespace));

    // Labels
    if let Some(labels) = &depl.metadata.labels {
        if labels.is_empty() {
            w.write_line("Labels:\t<none>");
        } else {
            w.write_line("Labels:");
            for (k, v) in labels {
                w.write_line(&format!("  {}={}", k, v));
            }
        }
    }
    // Annotations
    if let Some(ann) = &depl.metadata.annotations {
        if ann.is_empty() {
            w.write_line("Annotations:\t<none>");
        } else {
            w.write_line("Annotations:");
            for (k, v) in ann {
                if skip_annotations().contains(k) {
                    continue;
                }
                w.write_line(&format!("  {}={}", k, v));
            }
        }
    }

    // Replicas
    if let Some(spec) = &depl.spec {
        if let Some(num) = spec.replicas {
            w.write_line(&format!("Replicas (desired):\t{}", num));
        }
    }
    if let Some(st) = &depl.status {
        w.write_line(&format!("Replicas (current):\t{:?}", st.replicas));
        w.write_line(&format!("Updated:\t{:?}", st.updated_replicas));
        w.write_line(&format!("Available:\t{:?}", st.available_replicas));
        w.write_line(&format!("Unavailable:\t{:?}", st.unavailable_replicas));
    }

    // Possibly show conditions
    if let Some(st) = &depl.status {
        if let Some(conds) = &st.conditions {
            if !conds.is_empty() {
                w.write_line("Conditions:");
                w.write_line("  Type\tStatus\tReason");
                for c in conds {
                    let t = c.type_.clone();
                    let s = c.status.clone();
                    let reason = c.reason.clone().unwrap_or_default();
                    w.write_line(&format!("  {}\t{}\t{}", t, s, reason));
                }
            }
        }
    }

    // events
    if let Some(ev) = events {
        w.write_line("");
        describe_events(&ev, &mut w);
    }
    Ok(w.into_string())
}

////////////////////////////////////////////////////////////////////////////////
// Then replicate "ServiceDescriber" from snippet
////////////////////////////////////////////////////////////////////////////////

pub async fn describe_service(
    client: &Client,
    namespace: &str,
    name: &str,
    show_events: bool,
) -> LuaResult<String> {
    let services: Api<core_v1::Service> = Api::namespaced(client.clone(), namespace);
    let svc = services
        .get(name)
        .await
        .map_err(|e| LuaError::RuntimeError(format!("Error retrieving Service: {}", e)))?;

    let events = if show_events {
        Some(search_events(client, &svc, 50).await?)
    } else {
        None
    };

    let mut w = SimplePrefixWriter::new();
    w.write_line(&format!("Name:\t{}", svc.name_any()));
    w.write_line(&format!("Namespace:\t{}", namespace));

    // Labels
    if let Some(labels) = &svc.metadata.labels {
        if labels.is_empty() {
            w.write_line("Labels:\t<none>");
        } else {
            w.write_line("Labels:");
            for (k, v) in labels {
                w.write_line(&format!("  {}={}", k, v));
            }
        }
    }
    // Annotations
    if let Some(ann) = &svc.metadata.annotations {
        if ann.is_empty() {
            w.write_line("Annotations:\t<none>");
        } else {
            w.write_line("Annotations:");
            for (k, v) in ann {
                if skip_annotations().contains(k) {
                    continue;
                }
                w.write_line(&format!("  {}={}", k, v));
            }
        }
    }
    // Spec
    if let Some(sp) = &svc.spec {
        let t = sp.type_.clone().unwrap_or_default();
        w.write_line(&format!("Type:\t{}", t));
        let ip = sp.cluster_ip.clone().unwrap_or_default();
        w.write_line(&format!("IP:\t{}", ip));

        if let Some(ports) = &sp.ports {
            for p in ports {
                let name = p.name.clone().unwrap_or_else(|| "<unset>".into());
                let proto = p.protocol.clone().unwrap_or_else(|| "TCP".into());
                w.write_line(&format!("Port:\t{} {}/{}", name, p.port, proto));
            }
        }
    }

    // events
    if let Some(ev) = events {
        w.write_line("");
        describe_events(&ev, &mut w);
    }
    Ok(w.into_string())
}
