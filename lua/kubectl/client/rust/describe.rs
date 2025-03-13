use k8s_openapi::apimachinery::pkg::util::intstr::IntOrString;
use k8s_openapi::chrono::Utc;
use kube::{api::Api, Client};
use mlua::{Error as LuaError, Lua, Result as LuaResult};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::OnceLock;
use tera::{from_value, to_value, Context, Error, Tera, Value};

use k8s_openapi::api::core::v1 as core_v1;

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
    _lua: Lua,
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

fn format_line(label: &str, value: &str, indent: usize, label_width: usize) -> String {
    format!(
        "{:indent$}{:<label_width$}{}\n",
        "",
        label,
        value,
        indent = indent,
        label_width = label_width
    )
}

fn pad(args: &HashMap<String, Value>) -> Result<Value, Error> {
    let desired_val = args
        .get("desired")
        .ok_or_else(|| Error::msg("Missing 'desired'"))?;
    let desired: usize = from_value(desired_val.clone()).map_err(|e| Error::msg(e.to_string()))?;

    let subtract_val = args
        .get("subtract")
        .ok_or_else(|| Error::msg("Missing 'subtract'"))?;
    let subtract: String =
        from_value(subtract_val.clone()).map_err(|e| Error::msg(e.to_string()))?;

    let text_val = args
        .get("text")
        .ok_or_else(|| Error::msg("Missing 'text'"))?;
    let text: String = from_value(text_val.clone()).map_err(|e| Error::msg(e.to_string()))?;

    let padding = if desired > subtract.len() {
        desired - subtract.len()
    } else {
        0
    };

    let result = format!("{}{}", " ".repeat(padding), text);
    Ok(to_value(result)?)
}

pub async fn describe_pod(
    client: &Client,
    namespace: &str,
    name: &str,
    _show_events: bool,
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

    let mut tera = match Tera::new("lua/kubectl/client/rust/templates/*.tpl") {
        Ok(t) => t,
        Err(e) => panic!("Template parsing error: {}", e),
    };

    let mut context = Context::new();
    tera.register_function("pad", pad);
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
            context.insert(
                "node_name",
                &format!("{}/{}", node, &pod.status.clone().unwrap().host_ip.unwrap()).to_string(),
            );
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
    }
    // if let Some(spec) = &pod.spec {
    //     describe_resources(spec.resources.as_ref(), &mut context);
    // }

    if let Some(spec) = &pod.spec {
        if let Some(init_containers) = &spec.init_containers {
            let container_statuses = pod
                .status
                .as_ref()
                .and_then(|s| s.init_container_statuses.as_ref())
                .map(|v| v.as_slice())
                .unwrap_or(&[]);

            describe_containers(
                "init_containers",
                init_containers,
                Some(container_statuses),
                &mut context,
            );
        }
    }

    Ok(tera
        .render("pod_description.tpl", &context)
        .unwrap_or_else(|e| format!("Error rendering template: {}", e)))
}

// fn translate_timestamp_since(ts: &meta_v1::Time) -> String {
//     let now = Utc::now();
//     let delta = now.signed_duration_since(ts.0);
//     format!("{}s", delta.num_seconds())
// }

fn describe_containers(
    label: &str,
    containers: &[core_v1::Container],
    container_statuses: Option<&[core_v1::ContainerStatus]>,
    context: &mut Context,
) {
    let mut statuses: HashMap<String, &core_v1::ContainerStatus> = HashMap::new();
    if let Some(statuses_slice) = container_statuses {
        for status in statuses_slice {
            statuses.insert(status.name.to_lowercase(), status);
        }
    }

    let mut container_details = Vec::new();
    for container in containers {
        let mut details: BTreeMap<String, String> = BTreeMap::new();

        details.insert("name".to_string(), container.name.clone());
        if let Some(status) = statuses.get(&container.name) {
            details.insert(
                "container_id".to_string(),
                status.container_id.clone().unwrap_or_default(),
            );
        }

        details.insert(
            "image".to_string(),
            container.image.clone().unwrap_or_default(),
        );
        if let Some(status) = statuses.get(&container.name) {
            details.insert("image_id".to_string(), status.image_id.clone());
        }

        let port_str = describe_container_ports(container.ports.as_ref());
        if port_str.contains(',') {
            details.insert("ports".to_string(), port_str.clone());
        } else {
            details.insert("port".to_string(), string_or_none(&port_str));
        }
        let host_port_str = describe_container_host_ports(container.ports.as_ref());
        if host_port_str.contains(',') {
            details.insert("host_ports".to_string(), host_port_str.clone());
        } else {
            details.insert("host_port".to_string(), string_or_none(&host_port_str));
        }

        if let Some(sec_ctx) = &container.security_context {
            if let Some(seccomp_profile) = &sec_ctx.seccomp_profile {
                context.insert("seccomp_profile", &seccomp_profile.r#type_);
                if seccomp_profile.r#type_ == "Localhost" {
                    if let Some(local_profile) = &seccomp_profile.localhost_profile {
                        context.insert("localhost_profile", local_profile);
                    }
                }
            }
        }

        let command = describe_container_command(container);
        details.insert("command".to_string(), command);

        if let Some(status) = statuses.get(&container.name.to_lowercase()) {
            let state_output = describe_container_state(status);
            details.insert("state".to_string(), state_output);
        }

        if let Some(resources) = container.resources.as_ref() {
            let resources_output = describe_resources(Some(resources));
            context.insert("resources", &resources_output);
        }

        let probes = describe_container_probe(&container, 4, 15);
        details.insert("probes".to_string(), probes);

        let env_from = container_details.push(details);
    }

    context.insert(label, &container_details);
}

fn describe_probe(probe: &core_v1::Probe) -> String {
    // Extract probe attributes with default values if absent.
    let initial_delay = probe.initial_delay_seconds.unwrap_or(0);
    let timeout = probe.timeout_seconds.unwrap_or(0);
    let period = probe.period_seconds.unwrap_or(0);
    let success_threshold = probe.success_threshold.unwrap_or(0);
    let failure_threshold = probe.failure_threshold.unwrap_or(0);

    let attrs = format!(
        "delay={}s timeout={}s period={}s #success={} #failure={}",
        initial_delay, timeout, period, success_threshold, failure_threshold
    );

    // Check for Exec probe.
    if let Some(exec) = &probe.exec {
        // exec.command is Option<Vec<String>>
        let command = if let Some(commands) = &exec.command {
            commands.join(" ")
        } else {
            "<none>".to_string()
        };
        return format!("exec {} {}", command, attrs);
    }

    // Check for HTTPGet probe.
    if let Some(http_get) = &probe.http_get {
        let scheme = http_get
            .scheme
            .clone()
            .unwrap_or_else(|| "http".to_string())
            .to_lowercase();
        let host = http_get.host.clone().unwrap_or_default();
        let port_str = match &http_get.port {
            IntOrString::Int(i) => i.to_string(),
            IntOrString::String(s) => s.clone(),
        };
        let host_port = if !port_str.is_empty() {
            format!("{}:{}", host, port_str)
        } else {
            host
        };
        let path = http_get.path.clone().unwrap_or_default();
        let url = format!("{}://{}{}", scheme, host_port, path);
        return format!("http-get {} {}", url, attrs);
    }

    // Check for TCPSocket probe.
    if let Some(tcp_socket) = &probe.tcp_socket {
        let host = tcp_socket.host.clone().unwrap_or_default();
        let port_str = match &tcp_socket.port {
            IntOrString::Int(i) => i.to_string(),
            IntOrString::String(s) => s.clone(),
        };
        return format!("tcp-socket {}:{} {}", host, port_str, attrs);
    }

    // Check for GRPC probe.
    if let Some(grpc) = &probe.grpc {
        let service = grpc.service.clone().unwrap_or_default();
        return format!("grpc <pod>:{} {} {}", grpc.port, service, attrs);
    }

    // Fallback for unknown probe types.
    format!("unknown {}", attrs)
}

fn describe_container_probe(
    container: &core_v1::Container,
    indent: usize,
    label_width: usize,
) -> String {
    let mut output = String::new();

    if let Some(liveness) = &container.liveness_probe {
        let probe_str = describe_probe(liveness);
        output.push_str(&format_line("Liveness:", &probe_str, indent, label_width));
    }
    if let Some(readiness) = &container.readiness_probe {
        let probe_str = describe_probe(readiness);
        output.push_str(&format_line("Readiness:", &probe_str, indent, label_width));
    }
    if let Some(startup) = &container.startup_probe {
        let probe_str = describe_probe(startup);
        output.push_str(&format_line("Startup:", &probe_str, indent, label_width));
    }

    output
}

fn describe_resources(resources: Option<&core_v1::ResourceRequirements>) -> String {
    let mut output = String::new();
    // Total padding length between the name and the quantity.
    const TOTAL_PADDING: usize = 5;

    if let Some(resources) = resources {
        // Process Limits
        if let Some(limits) = &resources.limits {
            if !limits.is_empty() {
                output.push_str("Limits:\n");
                let mut names: Vec<&String> = limits.keys().collect();
                names.sort();
                for name in names {
                    let quantity = &limits[name];
                    let pad = if name.len() < TOTAL_PADDING {
                        TOTAL_PADDING - name.len()
                    } else {
                        0
                    };
                    output.push_str(&format!(
                        "      {}:{}\t{}\n",
                        name,
                        " ".repeat(pad),
                        quantity.0.to_string()
                    ));
                }
            }
        }

        // Process Requests
        if let Some(requests) = &resources.requests {
            if !requests.is_empty() {
                output.push_str("Requests:\n");
                let mut names: Vec<&String> = requests.keys().collect();
                names.sort();
                for name in names {
                    let quantity = &requests[name];
                    let pad = if name.len() < TOTAL_PADDING {
                        TOTAL_PADDING - name.len()
                    } else {
                        0
                    };
                    output.push_str(&format!(
                        "      {}:{}\t{}\n",
                        name,
                        " ".repeat(pad),
                        quantity.0.to_string()
                    ));
                }
            }
        }
    }

    output
}

fn describe_container_ports(c_ports: Option<&Vec<core_v1::ContainerPort>>) -> String {
    if let Some(ports_vec) = c_ports {
        let ports: Vec<String> = ports_vec
            .iter()
            .map(|c_port| {
                let protocol = c_port.protocol.as_deref().unwrap_or("TCP");
                format!("{}/{}", c_port.container_port, protocol)
            })
            .collect();
        ports.join(", ")
    } else {
        "".to_string()
    }
}

fn describe_container_host_ports(c_ports: Option<&Vec<core_v1::ContainerPort>>) -> String {
    if let Some(ports_vec) = c_ports {
        let ports: Vec<String> = ports_vec
            .iter()
            .map(|c_port| {
                let protocol = c_port.protocol.as_deref().unwrap_or("TCP");
                let host_port = c_port.host_port.map(|hp| hp).unwrap_or_else(|| 0);
                format!("{}/{}", host_port, protocol)
            })
            .collect();
        ports.join(", ")
    } else {
        "".to_string()
    }
}

fn describe_container_command(container: &core_v1::Container) -> String {
    let mut output = String::new();

    if let Some(commands) = &container.command {
        if !commands.is_empty() {
            output.push_str("Command:\n");
            for cmd in commands {
                for line in cmd.split('\n') {
                    output.push_str("      ");
                    output.push_str(line);
                    output.push('\n');
                }
            }
        }
    }

    if let Some(args) = &container.args {
        if !args.is_empty() {
            output.push_str("\t\tArgs:\n");
            for arg in args {
                for line in arg.split('\n') {
                    output.push_str("      ");
                    output.push_str(line);
                    output.push('\n');
                }
            }
        }
    }

    output
}

fn describe_container_state(status: &core_v1::ContainerStatus) -> String {
    let mut output = String::new();
    let indent = 8;
    let label_width = 15;

    if let Some(state) = &status.state {
        if let Some(running) = &state.running {
            output.push_str(&format_line("State:", "Running", 4, label_width));
            if let Some(started_at) = &running.started_at {
                output.push_str(&format_line(
                    "Started:",
                    &started_at.0.to_rfc2822(),
                    indent,
                    label_width,
                ));
            }
        } else if let Some(waiting) = &state.waiting {
            output.push_str(&format_line("State:", "Waiting", 4, label_width));
            if let Some(reason) = &waiting.reason {
                output.push_str(&format_line("Reason:", reason, indent, label_width));
            }
        } else if let Some(terminated) = &state.terminated {
            output.push_str(&format_line("State:", "Terminated", 4, label_width));
            if let Some(reason) = &terminated.reason {
                output.push_str(&format_line("Reason:", reason, indent, label_width));
            }
            if let Some(message) = &terminated.message {
                output.push_str(&format_line("Message:", message, indent, label_width));
            }
            output.push_str(&format_line(
                "Exit Code:",
                &terminated.exit_code.to_string(),
                indent,
                label_width,
            ));
            if let Some(signal) = terminated.signal {
                output.push_str(&format_line(
                    "Signal:",
                    &signal.to_string(),
                    indent,
                    label_width,
                ));
            }
            if let Some(started_at) = &terminated.started_at {
                output.push_str(&format_line(
                    "Started:",
                    &started_at.0.to_rfc2822(),
                    indent,
                    label_width,
                ));
            }
            if let Some(finished_at) = &terminated.finished_at {
                output.push_str(&format_line(
                    "Finished:",
                    &finished_at.0.to_rfc2822(),
                    indent,
                    label_width,
                ));
            }
        } else {
            output.push_str(&format_line("State:", "Waiting", 4, label_width));
        }
    }

    // Describe last state if available
    if let Some(last_state) = &status.last_state {
        if let Some(terminated) = &last_state.terminated {
            output.push_str(&format_line(
                "Last State:",
                "Terminated",
                indent,
                label_width,
            ));
            if let Some(reason) = &terminated.reason {
                output.push_str(&format_line("Last Reason:", reason, indent, label_width));
            }
            if let Some(message) = &terminated.message {
                output.push_str(&format_line("Last Message:", message, indent, label_width));
            }
            output.push_str(&format_line(
                "Last Exit Code:",
                &terminated.exit_code.to_string(),
                indent,
                label_width,
            ));
            if let Some(signal) = terminated.signal {
                output.push_str(&format_line(
                    "Last Signal:",
                    &signal.to_string(),
                    indent,
                    label_width,
                ));
            }
            if let Some(started_at) = &terminated.started_at {
                output.push_str(&format_line(
                    "Last Started:",
                    &started_at.0.to_rfc2822(),
                    indent,
                    label_width,
                ));
            }
            if let Some(finished_at) = &terminated.finished_at {
                output.push_str(&format_line(
                    "Last Finished:",
                    &finished_at.0.to_rfc2822(),
                    indent,
                    label_width,
                ));
            }
        } else if let Some(running) = &last_state.running {
            output.push_str(&format_line("Last State:", "Running", indent, label_width));
            if let Some(started_at) = &running.started_at {
                output.push_str(&format_line(
                    "Last Started:",
                    &started_at.0.to_rfc2822(),
                    indent,
                    label_width,
                ));
            }
        } else if let Some(waiting) = &last_state.waiting {
            output.push_str(&format_line("Last State:", "Waiting", indent, label_width));
            if let Some(reason) = &waiting.reason {
                output.push_str(&format_line("Last Reason:", reason, indent, label_width));
            }
        }
    }

    // Append Ready and Restart Count details
    output.push_str(&format_line(
        "Ready:",
        &status.ready.to_string(),
        4,
        label_width,
    ));
    output.push_str(&format_line(
        "Restart Count:",
        &status.restart_count.to_string(),
        4,
        label_width,
    ));

    output
}

fn string_or_none(s: &str) -> String {
    if s.is_empty() {
        "<none>".to_string()
    } else {
        s.to_string()
    }
}
