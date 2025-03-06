use k8s_openapi::api::core::v1::{ContainerStatus, Pod};
use k8s_openapi::chrono::{DateTime, Utc};
use k8s_openapi::serde_json::{self};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;
use std::collections::HashMap;

use crate::events::{color_status, symbols};
use crate::utils::{
    filter_dynamic, get_age, ip_to_u32, sort_dynamic, time_since, AccessorMode, FieldValue,
};

use super::processor::Processor;

#[derive(Debug, Clone, serde::Serialize)]
pub struct PodProcessed {
    namespace: String,
    name: String,
    ready: FieldValue,
    status: FieldValue,
    restarts: Restarts,
    ip: FieldValue,
    node: String,
    age: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
struct Restarts {
    symbol: String,
    value: String,
    sort_by: i64,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PodProcessor;

impl Processor for PodProcessor {
    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
        filter: Option<String>,
    ) -> LuaResult<mlua::Value> {
        let now = Utc::now();
        let mut data = Vec::new();

        for obj in items {
            let pod: Pod = serde_json::from_str(&serde_json::to_string(obj).unwrap())
                .expect("Failed to deserialize Pod");

            data.push(PodProcessed {
                ready: get_ready(&pod),
                status: get_pod_status(&pod),
                restarts: get_restarts(&pod, &now),
                ip: FieldValue {
                    value: pod
                        .status
                        .as_ref()
                        .and_then(|s| s.pod_ip.clone())
                        .unwrap_or_default(),
                    sort_by: ip_to_u32(
                        &pod.status
                            .as_ref()
                            .and_then(|s| s.pod_ip.clone())
                            .unwrap_or_default(),
                    ),
                    ..Default::default()
                },
                node: pod
                    .spec
                    .as_ref()
                    .and_then(|s| s.node_name.clone())
                    .unwrap_or_default(),
                age: get_age(&obj),
                namespace: pod.metadata.namespace.unwrap_or_default(),
                name: pod.metadata.name.unwrap_or_default(),
            });
        }

        sort_dynamic(
            &mut data,
            sort_by,
            sort_order,
            field_accessor(AccessorMode::Sort),
        );

        let data = if let Some(ref filter_value) = filter {
            filter_dynamic(
                &data,
                filter_value,
                &["namespace", "name", "ready", "status", "ip", "node"],
                field_accessor(AccessorMode::Filter),
            )
            .into_iter()
            .cloned()
            .collect()
        } else {
            data
        };

        lua.to_value(&data)
    }
}

fn field_accessor(mode: AccessorMode) -> impl Fn(&PodProcessed, &str) -> Option<String> {
    move |pod, field| match field {
        "namespace" => Some(pod.namespace.clone()),
        "name" => Some(pod.name.clone()),
        "ready" => Some(pod.ready.value.clone()),
        "status" => Some(pod.status.value.clone()),
        "restarts" => match mode {
            AccessorMode::Sort => Some(pod.restarts.sort_by.to_string()),
            AccessorMode::Filter => Some(pod.restarts.value.clone()),
        },
        "ip" => match mode {
            AccessorMode::Sort => Some(pod.ip.sort_by?.to_string()),
            AccessorMode::Filter => Some(pod.ip.value.clone()),
        },
        // "ip" => Some(pod.ip.clone()),
        "node" => Some(pod.node.clone()),
        "age" => match mode {
            AccessorMode::Sort => Some(pod.age.sort_by?.to_string()),
            AccessorMode::Filter => Some(pod.age.value.clone()),
        },
        _ => None,
    }
}

fn get_restarts(pod: &Pod, _current_time: &DateTime<Utc>) -> Restarts {
    let mut restarts = Restarts {
        symbol: String::new(),
        value: "0".to_string(),
        sort_by: 0,
    };

    if let Some(status) = &pod.status {
        if let Some(container_statuses) = &status.container_statuses {
            // Sum restart counts from all container statuses.
            let total_restarts: i64 = container_statuses
                .iter()
                .map(|cs| cs.restart_count as i64)
                .sum();

            // Find the last finished timestamp among container statuses.
            let last_finished = container_statuses
                .iter()
                .filter_map(|cs| {
                    cs.last_state
                        .as_ref()
                        .and_then(|ls| ls.terminated.as_ref())
                        .and_then(|t| t.finished_at.as_ref())
                })
                .last()
                .map(|time| time_since(&time.0.to_rfc3339()));

            if let Some(lf) = last_finished {
                restarts.value = format!("{} ({} ago)", total_restarts, lf);
                restarts.sort_by = total_restarts;
                if total_restarts > 0 {
                    restarts.symbol = color_status("Yellow");
                }
            } else {
                restarts.value = total_restarts.to_string();
            }
        }
    }

    restarts
}

fn check_init_container_status(
    cs: &ContainerStatus,
    count: i64,
    init_count: i64,
    restartable: bool,
) -> String {
    let ready = cs.ready;
    let started = cs.started.unwrap_or(false);

    if let Some(state) = &cs.state {
        if let Some(term) = &state.terminated {
            let exit_code = term.exit_code as i64;
            let signal = term.signal.unwrap_or(0) as i64;
            let reason = term.reason.as_deref().unwrap_or("");
            if exit_code == 0 {
                return "".to_string();
            }
            if !reason.is_empty() {
                return format!("Init:{}", reason);
            }
            if signal != 0 {
                return format!("Init:Signal:{}", signal);
            }
            return format!("Init:ExitCode:{}", exit_code);
        } else if restartable && started {
            if ready {
                return "".to_string();
            }
        } else if let Some(wait) = &state.waiting {
            let reason = wait.reason.as_deref().unwrap_or("");
            if !reason.is_empty() && reason != "PodInitializing" {
                return format!("Init:{}", reason);
            }
        }
    }

    format!("Init:{}/{}", count, init_count)
}

fn get_init_container_status(pod: &Pod, status: &str) -> (String, bool) {
    let init_containers = pod
        .spec
        .as_ref()
        .and_then(|spec| spec.init_containers.as_ref());
    if init_containers.is_none() {
        return (status.to_string(), false);
    }

    let arr = init_containers.unwrap();
    let count = arr.len() as i64;
    if count == 0 {
        return (status.to_string(), false);
    }

    let mut restart_policies = HashMap::new();
    for c in arr {
        let name = c.name.as_str();
        let pol = c
            .restart_policy
            .as_deref()
            .map(|x| x == "Always")
            .unwrap_or(false);
        restart_policies.insert(name.to_string(), pol);
    }

    if let Some(init_statuses) = pod
        .status
        .as_ref()
        .and_then(|s| s.init_container_statuses.as_ref())
    {
        for (i, cs) in init_statuses.iter().enumerate() {
            let name = cs.name.as_str();
            let s = check_init_container_status(
                cs,
                (i + 1) as i64,
                count,
                *restart_policies.get(name).unwrap_or(&false),
            );
            if !s.is_empty() {
                return (s, true);
            }
        }
    }

    (status.to_string(), false)
}

fn get_container_status(pod_statuses: &[ContainerStatus], default_status: &str) -> (String, bool) {
    let mut final_status = default_status.to_owned();
    let mut running = false;

    for cs in pod_statuses.iter().rev() {
        if let Some(state) = &cs.state {
            if let Some(waiting) = &state.waiting {
                if let Some(reason) = waiting.reason.as_deref() {
                    if !reason.is_empty() {
                        final_status = reason.to_string();
                        continue;
                    }
                }
            } else if let Some(terminated) = &state.terminated {
                if let Some(reason) = terminated.reason.as_deref() {
                    if !reason.is_empty() {
                        final_status = reason.to_string();
                        continue;
                    }
                } else if let Some(signal) = terminated.signal {
                    if signal != 0 {
                        final_status = format!("Signal:{}", signal);
                        continue;
                    }
                }
                final_status = format!("ExitCode:{}", terminated.exit_code);
                continue;
            }

            if cs.ready && state.running.is_some() {
                running = true;
            }
        }
    }

    (final_status, running)
}

fn get_pod_status(pod: &Pod) -> FieldValue {
    // If status is missing, return "Unknown"
    let status = pod.status.as_ref();
    if status.is_none() {
        return FieldValue {
            value: "Unknown".to_string(),
            symbol: Some(color_status("Unknown")),
            ..Default::default()
        };
    }
    let status = status.unwrap();

    // Get pod phase
    let mut phase = status.phase.as_deref().unwrap_or("Unknown");

    // Check for deletion timestamp
    let deletion_ts = pod.metadata.deletion_timestamp.as_ref();

    // Check for reason field
    if let Some(reason) = status.reason.as_deref() {
        if deletion_ts.is_some() && reason == "NodeLost" {
            return FieldValue {
                value: "Unknown".to_string(),
                symbol: Some(color_status("Unknown")),
                ..Default::default()
            };
        }
        phase = reason; // Override phase if a reason is provided
    }

    // Process init container status
    let (status_after_init, init_done) = get_init_container_status(pod, phase);
    if init_done {
        return FieldValue {
            value: status_after_init.clone(),
            symbol: Some(color_status(&status_after_init)),
            ..Default::default()
        };
    }

    // Process regular container statuses
    let mut final_status = status_after_init.clone();
    let mut is_running = false;
    if let Some(container_statuses) = &status.container_statuses {
        let (s, r) = get_container_status(container_statuses, &final_status);
        final_status = s;
        is_running = r;
    }

    // Adjust final status if necessary
    if is_running && final_status == "Completed" {
        final_status = "Running".to_string();
    }

    // If the pod is terminating
    if deletion_ts.is_some() {
        return FieldValue {
            value: "Terminating".to_string(),
            symbol: Some(color_status("Terminating")),
            ..Default::default()
        };
    }

    FieldValue {
        value: final_status.clone(),
        symbol: Some(color_status(&final_status)),
        ..Default::default()
    }
}

fn get_ready(pod: &Pod) -> FieldValue {
    let containers = pod
        .spec
        .as_ref()
        .map(|spec| spec.containers.len()) // Directly access containers field
        .unwrap_or(0);

    let mut ready_count = 0;
    if let Some(status) = &pod.status {
        if let Some(container_statuses) = &status.container_statuses {
            for cs in container_statuses {
                if cs.ready {
                    ready_count += 1;
                }
            }
        }
    }

    let mut symbol = if ready_count == containers {
        &symbols().note
    } else {
        &symbols().deprecated
    };

    let pod_status = get_pod_status(pod);
    if pod_status.value == "Completed" {
        symbol = &symbols().note;
    }

    FieldValue {
        value: format!("{}/{}", ready_count, containers),
        symbol: Some(symbol.to_string()),
        sort_by: Some(ready_count),
    }
}
