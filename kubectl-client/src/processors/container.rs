use crate::{
    pod_stats,
    utils::{time_since_jiff, AccessorMode},
};
use jiff::Timestamp;
use k8s_metrics::QuantityExt;
use k8s_openapi::{
    api::core::v1::{ContainerPort, ContainerStatus, Pod, ResourceRequirements},
    apimachinery::pkg::api::resource::Quantity,
};
use kube::api::DynamicObject;
use mlua::{prelude::*, Error as LuaError};

use super::processor::{dynamic_to_typed, Processor};

#[derive(Debug, Clone, serde::Serialize)]
pub struct ContainerRow {
    name: String,
    image: String,
    ready: String,
    state: String,
    #[serde(rename = "type")]
    ctype: String,
    restarts: String,
    ports: String,
    cpu: String,
    mem: String,
    #[serde(rename = "cpu/rl")]
    cpu_rl: String,
    #[serde(rename = "mem/rl")]
    mem_rl: String,
    #[serde(rename = "%cpu/r")]
    cpu_pct_r: String,
    #[serde(rename = "%cpu/l")]
    cpu_pct_l: String,
    #[serde(rename = "%mem/r")]
    mem_pct_r: String,
    #[serde(rename = "%mem/l")]
    mem_pct_l: String,
    age: String,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PodContainersProcessed {
    namespace: String,
    pod: String,
    containers: Vec<ContainerRow>,
}

#[derive(Debug, Clone)]
pub struct ContainerProcessor;

impl Processor for ContainerProcessor {
    type Row = PodContainersProcessed;

    fn build_row(&self, obj: &DynamicObject) -> LuaResult<Self::Row> {
        let pod: Pod = dynamic_to_typed(obj)?;

        let ns = pod.metadata.namespace.clone().unwrap_or_default();
        let pod_name = pod.metadata.name.clone().unwrap_or_default();

        let stats_guard = pod_stats()
            .read()
            .map_err(|_| LuaError::RuntimeError("poisoned pod_stats lock".into()))?;

        let pod_stats_entry = stats_guard.get(&(ns.clone(), pod_name.clone()));

        let build_row = |c_name: &str,
                         image: Option<&String>,
                         ports: Option<&Vec<ContainerPort>>,
                         res: Option<&ResourceRequirements>,
                         status: Option<&ContainerStatus>,
                         ctype: &'static str|
         -> ContainerRow {
            let (ready, state, started_at, restarts) = status
                .map(|cs| {
                    let ready = if cs.ready { "true" } else { "false" }.to_owned();
                    let (state, ts) = container_state(cs);
                    let restarts = cs.restart_count.to_string();
                    (ready, state, ts, restarts)
                })
                .unwrap_or_else(|| ("n/a".into(), "Unknown".into(), None, "0".into()));

            let age = started_at
                .as_ref()
                .map(|ts| time_since_jiff(ts))
                .unwrap_or_else(|| "n/a".into());

            let (req_cpu, req_mem) = resource_pair(res, true);
            let (lim_cpu, lim_mem) = resource_pair(res, false);

            let (cpu_m, mem_mi) = pod_stats_entry
                .and_then(|p| p.containers.get(c_name).map(|c| (c.cpu_m, c.mem_mi)))
                .unwrap_or((0, 0));

            ContainerRow {
                name: c_name.to_string(),
                image: image.cloned().unwrap_or_default(),
                ready,
                state,
                ctype: ctype.into(),
                restarts,
                ports: ports_to_string(ports),
                cpu: cpu_m.to_string(),
                mem: mem_mi.to_string(),
                cpu_rl: format!("{}:{}", req_cpu, lim_cpu),
                mem_rl: format!("{}:{}", req_mem, lim_mem),
                cpu_pct_r: pct(cpu_m, req_cpu),
                cpu_pct_l: pct(cpu_m, lim_cpu),
                mem_pct_r: pct(mem_mi, req_mem),
                mem_pct_l: pct(mem_mi, lim_mem),
                age,
            }
        };

        let mut rows: Vec<ContainerRow> = Vec::new();

        if let Some(spec) = &pod.spec {
            /* ordinary containers */
            for c in &spec.containers {
                rows.push(build_row(
                    &c.name,
                    c.image.as_ref(),
                    c.ports.as_ref(),
                    c.resources.as_ref(),
                    find_status(&pod, &c.name),
                    "container",
                ));
            }
            /* init containers */
            if let Some(init) = &spec.init_containers {
                for c in init {
                    rows.push(build_row(
                        &c.name,
                        c.image.as_ref(),
                        c.ports.as_ref(),
                        c.resources.as_ref(),
                        find_status(&pod, &c.name),
                        "initcontainer",
                    ));
                }
            }
            /* debug / ephemeral containers */
            if let Some(eph) = &spec.ephemeral_containers {
                for c in eph {
                    rows.push(build_row(
                        &c.name,
                        c.image.as_ref(),
                        c.ports.as_ref(),
                        c.resources.as_ref(),
                        find_status(&pod, &c.name),
                        "debug",
                    ));
                }
            }
        }

        Ok(PodContainersProcessed {
            namespace: ns,
            pod: pod_name,
            containers: rows,
        })
    }

    fn filterable_fields(&self) -> &'static [&'static str] {
        &["namespace", "pod"]
    }

    fn field_accessor(
        &self,
        _mode: AccessorMode,
    ) -> Box<dyn Fn(&Self::Row, &str) -> Option<String> + '_> {
        Box::new(|row, field| match field {
            "namespace" => Some(row.namespace.clone()),
            "pod" => Some(row.pod.clone()),
            _ => None,
        })
    }
}

fn container_state(cs: &ContainerStatus) -> (String, Option<Timestamp>) {
    if let Some(s) = &cs.state {
        if let Some(r) = &s.running {
            return ("Running".into(), r.started_at.as_ref().map(|t| t.0));
        }
        if let Some(w) = &s.waiting {
            return (w.reason.clone().unwrap_or_else(|| "Waiting".into()), None);
        }
        if let Some(t) = &s.terminated {
            let reason = t
                .reason
                .clone()
                .unwrap_or_else(|| format!("ExitCode:{}", t.exit_code));
            return (reason, t.finished_at.as_ref().map(|t| t.0));
        }
    }
    ("Unknown".into(), None)
}

fn find_status<'a>(pod: &'a Pod, cname: &str) -> Option<&'a ContainerStatus> {
    fn check<'a>(
        list: Option<&'a Vec<ContainerStatus>>,
        cname: &str,
    ) -> Option<&'a ContainerStatus> {
        list.and_then(|v| v.iter().find(|cs| cs.name == cname))
    }

    let status = pod.status.as_ref()?;
    check(status.container_statuses.as_ref(), cname)
        .or_else(|| check(status.init_container_statuses.as_ref(), cname))
        .or_else(|| check(status.ephemeral_container_statuses.as_ref(), cname))
}

fn resource_pair(res: Option<&ResourceRequirements>, requests: bool) -> (u64, u64) {
    let map_opt = res.and_then(|r| {
        if requests {
            r.requests.as_ref()
        } else {
            r.limits.as_ref()
        }
    });

    let mut cpu_m = 0_u64;
    let mut mem_mi = 0_u64;
    if let Some(map) = map_opt {
        if let Some(q) = map.get("cpu") {
            cpu_m = quantity_to_millicpu(q);
        }
        if let Some(q) = map.get("memory") {
            mem_mi = quantity_to_mib(q);
        }
    }
    (cpu_m, mem_mi)
}

fn ports_to_string(ports: Option<&Vec<ContainerPort>>) -> String {
    ports
        .unwrap_or(&vec![])
        .iter()
        .map(|p| p.container_port.to_string())
        .collect::<Vec<_>>()
        .join(",")
}

/* percentage helpers */
#[inline]
fn pct(used: u64, bound: u64) -> String {
    if bound == 0 {
        "n/a".into()
    } else {
        format!("{}", ((used as f64 / bound as f64) * 100.0).round() as u64)
    }
}

#[inline]
fn quantity_to_millicpu(q: &Quantity) -> u64 {
    (q.to_f64().unwrap_or(0.0) * 1000.0).round() as u64
}

#[inline]
fn quantity_to_mib(q: &Quantity) -> u64 {
    if let Ok(bytes) = q.to_memory() {
        (bytes as u64) / (1024 * 1024)
    } else if let Some(num_str) = q.0.strip_suffix('m') {
        num_str
            .parse::<f64>()
            .map(|n| ((n / 1000.0) / (1024.0 * 1024.0)).round() as u64)
            .unwrap_or(0)
    } else {
        0
    }
}
