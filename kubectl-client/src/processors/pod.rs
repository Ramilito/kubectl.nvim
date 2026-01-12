use std::collections::HashMap;

use crate::{
    events::{color_status, symbols},
    pod_stats,
    utils::{pad_key, time_since_jiff, AccessorMode, FieldValue},
};
use jiff::Timestamp;
use k8s_openapi::{
    api::core::v1::{ContainerStatus, Pod},
    apimachinery::pkg::api::resource::Quantity,
};
use kube::api::DynamicObject;
use mlua::prelude::*;

use super::processor::Processor;

#[derive(Debug, Clone, serde::Serialize)]
pub struct PodProcessed {
    namespace: String,
    name: String,
    ready: FieldValue,
    status: FieldValue,
    restarts: FieldValue,
    ip: FieldValue,
    node: String,
    age: FieldValue,
    cpu: FieldValue,
    mem: FieldValue,
    #[serde(rename = "%cpu/r")]
    cpu_pct_r: FieldValue,
    #[serde(rename = "%cpu/l")]
    cpu_pct_l: FieldValue,
    #[serde(rename = "%mem/r")]
    mem_pct_r: FieldValue,
    #[serde(rename = "%mem/l")]
    mem_pct_l: FieldValue,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PodProcessor;

impl Processor for PodProcessor {
    type Row = PodProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        use k8s_openapi::api::core::v1::Pod;
        use k8s_openapi::serde_json::{from_value, to_value};

        let pod: Pod =
            from_value(to_value(obj).map_err(LuaError::external)?).map_err(LuaError::external)?;

        let now = Timestamp::now();

        let namespace = pod.metadata.namespace.clone().unwrap_or_default();
        let name = pod.metadata.name.clone().unwrap_or_default();

        let (cpu_m, mem_mi) = {
            let guard = match pod_stats().lock() {
                Ok(g) => g,
                Err(_) => return Err(LuaError::RuntimeError("poisoned pod_stats lock".into())),
            };
            guard
                .get(&(namespace.clone(), name.clone()))
                .map(|s| (s.cpu_m, s.mem_mi))
                .unwrap_or((0, 0))
        };

        let (req_cpu_m, req_mem_mi) = sum_requests(&pod);
        let (lim_cpu_m, lim_mem_mi) = sum_limits(&pod);
        let cpu_pct_r_val = (req_cpu_m > 0).then(|| percent(cpu_m, req_cpu_m));
        let cpu_pct_l_val = (lim_cpu_m > 0).then(|| percent(cpu_m, lim_cpu_m));
        let mem_pct_r_val = (req_mem_mi > 0).then(|| percent(mem_mi, req_mem_mi));
        let mem_pct_l_val = (lim_mem_mi > 0).then(|| percent(mem_mi, lim_mem_mi));

        Ok(PodProcessed {
            ready: get_ready(&pod),
            status: get_pod_status(&pod),
            restarts: get_restarts(&pod, &now),
            ip: {
                let raw_ip = pod
                    .status
                    .as_ref()
                    .and_then(|s| s.pod_ip.clone())
                    .unwrap_or_default();
                FieldValue {
                    value: raw_ip.clone(),
                    sort_by: self.ip_to_u32(&raw_ip),
                    ..Default::default()
                }
            },
            node: pod
                .spec
                .as_ref()
                .and_then(|s| s.node_name.clone())
                .unwrap_or_default(),
            age: self.get_age(obj),
            namespace,
            name,
            cpu: FieldValue {
                value: format!("{}", cpu_m),
                sort_by: Some(cpu_m as usize),
                ..Default::default()
            },
            mem: FieldValue {
                value: format!("{}", mem_mi),
                sort_by: Some(mem_mi as usize),
                ..Default::default()
            },
            cpu_pct_r: FieldValue {
                value: cpu_pct_r_val
                    .map(|p| format!("{p}"))
                    .unwrap_or_else(|| "n/a".into()),
                sort_by: cpu_pct_r_val.map(|p| p as usize),
                symbol: cpu_pct_r_val.map(color_usage),
                hint: None,
            },
            cpu_pct_l: FieldValue {
                value: cpu_pct_l_val
                    .map(|p| format!("{p}"))
                    .unwrap_or_else(|| "n/a".into()),
                sort_by: cpu_pct_l_val.map(|p| p as usize),
                symbol: cpu_pct_l_val.map(color_usage),
                hint: None,
            },
            mem_pct_r: FieldValue {
                value: mem_pct_r_val
                    .map(|p| format!("{p}"))
                    .unwrap_or_else(|| "n/a".into()),
                sort_by: mem_pct_r_val.map(|p| p as usize),
                symbol: mem_pct_r_val.map(color_usage),
                hint: None,
            },
            mem_pct_l: FieldValue {
                value: mem_pct_l_val
                    .map(|p| format!("{p}"))
                    .unwrap_or_else(|| "n/a".into()),
                sort_by: mem_pct_l_val.map(|p| p as usize),
                symbol: mem_pct_l_val.map(color_usage),
                hint: None,
            },
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "name", "ready", "status", "ip", "node"]
    }

    fn field_accessor(
        &self,
        mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(move |pod, field| match field {
            "namespace" => Some(pod.namespace.clone()),
            "name" => Some(pod.name.clone()),
            "ready" => Some(pod.ready.value.clone()),
            "status" => Some(pod.status.value.clone()),
            "restarts" => match mode {
                AccessorMode::Sort => pod.restarts.sort_by.map(pad_key),
                AccessorMode::Filter => Some(pod.restarts.value.clone()),
            },
            "ip" => match mode {
                AccessorMode::Sort => pod.ip.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(pod.ip.value.clone()),
            },
            "node" => Some(pod.node.clone()),
            "age" => match mode {
                AccessorMode::Sort => pod.age.sort_by.map(|v| v.to_string()),
                AccessorMode::Filter => Some(pod.age.value.clone()),
            },
            "cpu" => match mode {
                AccessorMode::Sort => pod.cpu.sort_by.map(pad_key),
                AccessorMode::Filter => Some(pod.cpu.value.clone()),
            },
            "mem" => match mode {
                AccessorMode::Sort => pod.mem.sort_by.map(pad_key),
                AccessorMode::Filter => Some(pod.mem.value.clone()),
            },
            "%cpu/r" => match mode {
                AccessorMode::Sort => pod.cpu_pct_r.sort_by.map(pad_key),
                AccessorMode::Filter => Some(pod.cpu_pct_r.value.clone()),
            },
            "%cpu/l" => match mode {
                AccessorMode::Sort => pod.cpu_pct_l.sort_by.map(pad_key),
                AccessorMode::Filter => Some(pod.cpu_pct_l.value.clone()),
            },
            "%mem/r" => match mode {
                AccessorMode::Sort => pod.mem_pct_r.sort_by.map(pad_key),
                AccessorMode::Filter => Some(pod.mem_pct_r.value.clone()),
            },
            "%mem/l" => match mode {
                AccessorMode::Sort => pod.mem_pct_l.sort_by.map(pad_key),
                AccessorMode::Filter => Some(pod.mem_pct_l.value.clone()),
            },
            _ => None,
        })
    }
}

fn sum_requests(pod: &Pod) -> (u64, u64) {
    let mut cpu_m = 0_u64;
    let mut mem_mi = 0_u64;

    if let Some(spec) = &pod.spec {
        for c in &spec.containers {
            if let Some(reqs) = c.resources.as_ref().and_then(|r| r.requests.as_ref()) {
                if let Some(q) = reqs.get("cpu") {
                    cpu_m += quantity_to_millicpu(q);
                }
                if let Some(q) = reqs.get("memory") {
                    mem_mi += quantity_to_mib(q);
                }
            }
        }
    }
    (cpu_m, mem_mi)
}

fn sum_limits(pod: &Pod) -> (u64, u64) {
    /* returns (cpu_m, mem_mi) */
    let mut cpu_m = 0_u64;
    let mut mem_mi = 0_u64;

    if let Some(spec) = &pod.spec {
        for c in &spec.containers {
            if let Some(limits) = c.resources.as_ref().and_then(|r| r.limits.as_ref()) {
                if let Some(q) = limits.get("cpu") {
                    cpu_m += quantity_to_millicpu(q);
                }
                if let Some(q) = limits.get("memory") {
                    mem_mi += quantity_to_mib(q);
                }
            }
        }
    }
    (cpu_m, mem_mi)
}

fn quantity_to_millicpu(q: &Quantity) -> u64 {
    parse_cpu_to_millicores(&q.0).unwrap_or(0)
}

fn quantity_to_mib(q: &Quantity) -> u64 {
    parse_memory_to_bytes(&q.0)
        .map(|bytes| bytes / (1024 * 1024))
        .unwrap_or(0)
}

/// Parse Kubernetes CPU quantity string to millicores
fn parse_cpu_to_millicores(s: &str) -> Option<u64> {
    if let Some(n) = s.strip_suffix('m') {
        n.parse::<f64>().ok().map(|v| v.round() as u64)
    } else if let Some(n) = s.strip_suffix('n') {
        n.parse::<f64>().ok().map(|v| (v / 1_000_000.0).round() as u64)
    } else if let Some(n) = s.strip_suffix('u') {
        n.parse::<f64>().ok().map(|v| (v / 1_000.0).round() as u64)
    } else {
        s.parse::<f64>().ok().map(|v| (v * 1000.0).round() as u64)
    }
}

/// Parse Kubernetes memory quantity string to bytes
fn parse_memory_to_bytes(s: &str) -> Option<u64> {
    let suffixes: &[(&str, u64)] = &[
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
            return n.parse::<f64>().ok().map(|v| (v * (*multiplier as f64)).round() as u64);
        }
    }

    s.parse::<u64>().ok()
}

fn color_usage(p: u64) -> String {
    if p >= 90 {
        color_status("Red")
    } else if p >= 80 {
        color_status("Yellow")
    } else {
        color_status("Green")
    }
}

pub fn percent(used: u64, limit: u64) -> u64 {
    ((used as f64 / limit as f64) * 100.0).round() as u64
}

fn get_restarts(pod: &Pod, _current_time: &Timestamp) -> FieldValue {
    let total_restarts: usize = pod
        .status
        .as_ref()
        .and_then(|s| s.container_statuses.as_ref())
        .map(|statuses| statuses.iter().map(|cs| cs.restart_count as usize).sum())
        .unwrap_or(0);

    let last_finished: Option<Timestamp> = pod
        .status
        .as_ref()
        .and_then(|s| s.container_statuses.as_ref())
        .and_then(|statuses| {
            statuses
                .iter()
                .filter_map(|cs| {
                    cs.last_state
                        .as_ref()
                        .and_then(|ls| ls.terminated.as_ref())
                        .and_then(|t| t.finished_at.as_ref())
                        .map(|t| t.0)
                })
                .max()
        });

    let mut restarts = FieldValue {
        value: total_restarts.to_string(),
        sort_by: Some(total_restarts),
        ..Default::default()
    };

    if let Some(ts) = last_finished {
        restarts.value = format!("{} ({} ago)", total_restarts, time_since_jiff(&ts));
    }

    if total_restarts > 0 {
        restarts.symbol = Some(color_status("Yellow"));
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

/// Container status result with status string, running flag, and optional hint message
struct ContainerStatusResult {
    status: String,
    running: bool,
    hint: Option<String>,
}

fn get_container_status(pod_statuses: &[ContainerStatus], default_status: &str) -> ContainerStatusResult {
    let mut result = ContainerStatusResult {
        status: default_status.to_owned(),
        running: false,
        hint: None,
    };

    for cs in pod_statuses.iter().rev() {
        if let Some(state) = &cs.state {
            if let Some(waiting) = &state.waiting {
                if let Some(reason) = waiting.reason.as_deref() {
                    if !reason.is_empty() {
                        result.status = reason.to_string();
                        // Capture the detailed message as hint
                        result.hint = waiting.message.clone();
                        continue;
                    }
                }
            } else if let Some(terminated) = &state.terminated {
                if let Some(reason) = terminated.reason.as_deref() {
                    if !reason.is_empty() {
                        result.status = reason.to_string();
                        result.hint = terminated.message.clone();
                        continue;
                    }
                } else if let Some(signal) = terminated.signal {
                    if signal != 0 {
                        result.status = format!("Signal:{}", signal);
                        result.hint = terminated.message.clone();
                        continue;
                    }
                }
                result.status = format!("ExitCode:{}", terminated.exit_code);
                result.hint = terminated.message.clone();
                continue;
            }

            if cs.ready && state.running.is_some() {
                result.running = true;
            }
        }
    }

    result
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
    let mut hint: Option<String> = None;
    if let Some(container_statuses) = &status.container_statuses {
        let result = get_container_status(container_statuses, &final_status);
        final_status = result.status;
        is_running = result.running;
        hint = result.hint;
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
        hint,
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
        hint: None,
    }
}
