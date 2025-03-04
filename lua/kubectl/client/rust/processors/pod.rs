use k8s_openapi::chrono::{DateTime, Utc};
use k8s_openapi::serde_json::{self, Value};
use kube::api::DynamicObject;
use mlua::prelude::*;
use mlua::Lua;
use std::collections::HashMap;

use crate::events::{color_status, symbols};
use crate::utils::time_since;

use super::processor::Processor;

#[derive(Debug, Clone, serde::Serialize)]
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

#[derive(Debug, Clone, serde::Serialize)]
struct ProcessedStatus {
    value: String,
    symbol: String,
}

#[derive(Debug, Clone, serde::Serialize)]
struct ProcessedRestarts {
    symbol: String,
    value: String,
    sort_by: i64,
}

pub struct PodProcessor;

impl Processor for PodProcessor {
    fn process(
        &self,
        lua: &Lua,
        items: &[DynamicObject],
        sort_by: Option<String>,
        sort_order: Option<String>,
    ) -> LuaResult<mlua::Value> {
        let now = Utc::now();
        let mut data = Vec::new();

        for obj in items {
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
                format!("{}", time_since(&creation_ts))
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

        let sort_field = sort_by
            .as_ref()
            .filter(|s| !s.trim().is_empty())
            .map(|s| s.to_lowercase())
            .unwrap_or_else(|| "namespace".to_owned());

        let order = sort_order
            .as_ref()
            .filter(|s| !s.trim().is_empty())
            .map(|s| s.to_lowercase())
            .unwrap_or_else(|| "asc".to_owned());

        if !data.is_empty() && get_field_value(&data[0], &sort_field).is_some() {
            data.sort_by(|a, b| {
                let a_val = get_field_value(a, &sort_field).unwrap_or_default();
                let b_val = get_field_value(b, &sort_field).unwrap_or_default();
                if order == "desc" {
                    b_val.cmp(&a_val)
                } else {
                    a_val.cmp(&b_val)
                }
            });
        }

        lua.to_value(&data)
            .map_err(|_| mlua::Error::FromLuaConversionError {
                from: "PodProcessed",
                to: "LuaValue".to_string(),
                message: None,
            })
    }
}

fn get_field_value(pod: &PodProcessed, field: &str) -> Option<String> {
    match field {
        "namespace" => Some(pod.namespace.clone()),
        "name" => Some(pod.name.clone()),
        "ready" => Some(pod.ready.value.clone()),
        "status" => Some(pod.status.value.clone()),
        "restarts" => Some(pod.restarts.sort_by.to_string()),
        "ip" => Some(pod.ip.clone()),
        "node" => Some(pod.node.clone()),
        "age" => Some(pod.age.clone()),
        _ => None,
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
                last_finished = Some(time_since(ts));
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
    let mut s = status.to_string();
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
                    s = reason.to_string();
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
                    s = reason.to_string();
                } else if signal != 0 {
                    s = format!("Signal:{}", signal).to_string();
                } else {
                    s = format!("ExitCode:{}", exit_code).to_string();
                }
            } else if cs_ready && cs_running {
                running = true;
            }
        }
    }
    (s.to_string(), running)
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
            if cs
                .pointer("/ready")
                .and_then(Value::as_bool)
                .unwrap_or(false)
            {
                ready_count += 1;
            }
        }
    }

    // For "full" readiness we display a note symbol, else "deprecated"
    let mut symbol = if ready_count == containers {
        &symbols().note
    } else {
        &symbols().deprecated
    };

    let pod_status = get_pod_status(pod_val);
    if pod_status.value == "Completed" {
        symbol = &symbols().note;
    }

    ProcessedStatus {
        value: format!("{}/{}", ready_count, containers),
        symbol: symbol.to_string(),
    }
}
