// src/processor.rs
use k8s_openapi::chrono::{DateTime, Utc};
use k8s_openapi::serde_json::{self, Value};
use kube::api::DynamicObject;
use serde::Serialize;
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize)]
pub struct PodProcessed {
    namespace: String,
    name: String,
    ready: ProcessedStatus,
    status: ProcessedStatus,
    restarts: ProcessedRestarts,
    ip: String,
    node: String,
    age: String,
}

#[derive(Debug, Clone, Serialize)]
struct ProcessedStatus {
    value: String,
    symbol: String,
}

#[derive(Debug, Clone, Serialize)]
struct ProcessedRestarts {
    symbol: String,
    value: String,
    sort_by: i64,
}

pub fn process_items(items: &[DynamicObject]) -> Vec<PodProcessed> {
    let now = Utc::now();
    let mut data = Vec::new();

    for obj in items {
        // Convert to generic JSON for pointer-based extraction
        let raw_json = serde_json::to_value(obj).unwrap_or(Value::Null);

        let namespace = obj.metadata.namespace.clone().unwrap_or_default();
        let name = obj.metadata.name.clone().unwrap_or_default();

        let ip = raw_json
            .pointer("/status/podIP")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        let node = raw_json
            .pointer("/spec/nodeName")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();

        let creation_ts = obj
            .metadata
            .creation_timestamp
            .as_ref()
            .map(|t| t.0.to_rfc3339())
            .unwrap_or_default();
        let age = if !creation_ts.is_empty() {
            format!("{} ago", time_since(&creation_ts, true))
        } else {
            "".to_string()
        };

        let ready = get_ready(&raw_json);
        let status = get_pod_status(&raw_json);
        let restarts = get_restarts(&raw_json, &now);

        data.push(PodProcessed {
            namespace,
            name,
            ready,
            status,
            restarts,
            ip,
            node,
            age,
        });
    }

    data
}

fn color_status(status: &str) -> String {
    status.to_string()
}

fn symbols_note() -> String {
    "✓".to_string()
}

fn symbols_deprecated() -> String {
    "✗".to_string()
}

fn time_since(ts_str: &str, short: bool) -> String {
    if let Ok(ts) = ts_str.parse::<DateTime<Utc>>() {
        let now = Utc::now();
        let diff = now.signed_duration_since(ts);
        let hrs = diff.num_hours();
        let mins = diff.num_minutes() % 60;
        if short {
            format!("{}h{}m", hrs, mins)
        } else {
            format!("{}h{}m", hrs, mins)
        }
    } else {
        "".to_string()
    }
}

fn get_restarts(pod_val: &Value, _current_time: &DateTime<Utc>) -> ProcessedRestarts {
    let mut restarts = ProcessedRestarts {
        symbol: "".to_string(),
        value: "0".to_string(),
        sort_by: 0,
    };

    let container_statuses = pod_val.pointer("/status/containerStatuses");
    if let Some(Value::Array(statuses)) = container_statuses {
        let mut total_restarts = 0;
        let mut last_finished = None;
        for st in statuses {
            let rc = st
                .pointer("/restartCount")
                .and_then(Value::as_i64)
                .unwrap_or(0);
            total_restarts += rc;

            if let Some(ts) = st
                .pointer("/lastState/terminated/finishedAt")
                .and_then(Value::as_str)
            {
                last_finished = Some(time_since(ts, false));
            }
        }
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

    restarts
}

fn check_init_container_status(
    cs: &Value,
    count: i64,
    init_count: i64,
    restartable: bool,
) -> String {
    let state_terminated = cs.pointer("/state/terminated");
    let state_waiting = cs.pointer("/state/waiting");
    let ready = cs
        .pointer("/ready")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let started = cs
        .pointer("/started")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    if let Some(term) = state_terminated {
        let exit_code = term
            .pointer("/exitCode")
            .and_then(Value::as_i64)
            .unwrap_or(0);
        let signal = term.pointer("/signal").and_then(Value::as_i64).unwrap_or(0);
        let reason = term
            .pointer("/reason")
            .and_then(Value::as_str)
            .unwrap_or("");
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
    } else if let Some(wait) = state_waiting {
        let reason = wait
            .pointer("/reason")
            .and_then(Value::as_str)
            .unwrap_or("");
        if !reason.is_empty() && reason != "PodInitializing" {
            return format!("Init:{}", reason);
        }
    }

    format!("Init:{}/{}", count, init_count)
}

fn get_init_container_status(pod_val: &Value, status: &str) -> (String, bool) {
    let init_containers = pod_val.pointer("/spec/initContainers");
    if !matches!(init_containers, Some(Value::Array(_))) {
        return (status.to_string(), false);
    }
    let arr = init_containers.unwrap().as_array().unwrap();
    let count = arr.len() as i64;
    if count == 0 {
        return (status.to_string(), false);
    }

    let mut restart_policies = HashMap::new();
    for c in arr {
        let name = c.pointer("/name").and_then(Value::as_str).unwrap_or("");
        let pol = c
            .pointer("/restartPolicy")
            .and_then(Value::as_str)
            .map(|x| x == "Always")
            .unwrap_or(false);
        restart_policies.insert(name.to_string(), pol);
    }

    let statuses_val = pod_val.pointer("/status/initContainerStatuses");
    if let Some(Value::Array(sts)) = statuses_val {
        for (i, cs) in sts.iter().enumerate() {
            let name = cs.pointer("/name").and_then(Value::as_str).unwrap_or("");
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

fn get_container_status(pod_val: &Value, status: &str) -> (String, bool) {
    let mut running = false;
    let mut status = status;
    let cont_statuses = pod_val.pointer("/containerStatuses");

    if let Some(Value::Array(sts)) = cont_statuses {
        for cs in sts.iter().rev() {
            let state_waiting = cs.pointer("/state/waiting");
            let state_terminated = cs.pointer("/state/terminated");
            let cs_ready = cs
                .pointer("/ready")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let cs_running = cs.pointer("/state/running").is_some();

            if let Some(wait) = state_waiting {
                let reason = wait
                    .pointer("/reason")
                    .and_then(Value::as_str)
                    .unwrap_or("");
                if !reason.is_empty() {
                    status = reason;
                }
            } else if let Some(term) = state_terminated {
                let reason = term
                    .pointer("/reason")
                    .and_then(Value::as_str)
                    .unwrap_or("");
                let signal = term.pointer("/signal").and_then(Value::as_i64).unwrap_or(0);
                let exit_code = term
                    .pointer("/exitCode")
                    .and_then(Value::as_i64)
                    .unwrap_or(0);
                if !reason.is_empty() {
                    status = reason;
                } else if signal != 0 {
                    // status = &format!("Signal:{}", signal);
                } else {
                    // status = &format!("ExitCode:{}", exit_code);
                }
            } else if cs_ready && cs_running {
                running = true;
            }
        }
    }
    (status.to_string(), running)
}

fn get_pod_status(pod_val: &Value) -> ProcessedStatus {
    if pod_val.pointer("/status").is_none() {
        return ProcessedStatus {
            value: "Unknown".to_string(),
            symbol: color_status("Unknown"),
        };
    }

    let mut status = pod_val
        .pointer("/status/phase")
        .and_then(Value::as_str)
        .unwrap_or("Unknown");

    let deletion_ts = pod_val
        .pointer("/metadata/deletionTimestamp")
        .and_then(Value::as_str);
    if let Some(reason) = pod_val.pointer("/status/reason").and_then(Value::as_str) {
        if deletion_ts.is_some() && reason == "NodeLost" {
            return ProcessedStatus {
                value: "Unknown".to_string(),
                symbol: color_status("Unknown"),
            };
        }
        status = reason;
    }

    let (status_after_init, init_done) = get_init_container_status(pod_val, status);
    if init_done {
        return ProcessedStatus {
            value: status_after_init.clone(),
            symbol: color_status(&status_after_init),
        };
    }

    let pod_status = pod_val.pointer("/status");
    let mut final_status = status_after_init.clone();
    let mut is_running = false;
    if let Some(ps) = pod_status {
        let (s, r) = get_container_status(ps, &final_status);
        final_status = s;
        is_running = r;
    }

    if is_running && final_status == "Completed" {
        final_status = "Running".to_string();
    }

    if deletion_ts.is_some() {
        return ProcessedStatus {
            value: "Terminating".to_string(),
            symbol: color_status("Terminating"),
        };
    }

    ProcessedStatus {
        value: final_status.clone(),
        symbol: color_status(&final_status),
    }
}

fn get_ready(pod_val: &Value) -> ProcessedStatus {
    let mut containers = 0;
    if let Some(Value::Array(spec_cs)) = pod_val.pointer("/spec/containers") {
        containers = spec_cs.len();
    }
    let mut ready_count = 0;
    if let Some(Value::Array(sts)) = pod_val.pointer("/status/containerStatuses") {
        for cs in sts {
            let r = cs
                .pointer("/ready")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            if r {
                ready_count += 1;
            }
        }
    }

    let mut symbol = if ready_count == containers {
        symbols_note()
    } else {
        symbols_deprecated()
    };

    let pod_status = get_pod_status(pod_val);
    if pod_status.value == "Completed" {
        symbol = symbols_note();
    }

    ProcessedStatus {
        value: format!("{}/{}", ready_count, containers),
        symbol,
    }
}
