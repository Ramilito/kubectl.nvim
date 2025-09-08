use k8s_openapi::api::core::v1::{Endpoints, Pod, Service};
use kube::{api::ListParams, Api, Client};
use mlua::prelude::*;
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;
use tokio::io::AsyncWriteExt;
use tokio::net::{TcpListener, TcpStream};
use tokio::runtime::Runtime;
use tokio::sync::{oneshot, Mutex};
use tokio::time;
use tracing::{debug, error, info, warn};

use crate::{CLIENT_INSTANCE, RUNTIME};

static PF_MAP: OnceLock<Mutex<HashMap<usize, PFData>>> = OnceLock::new();
static PF_COUNTER: AtomicUsize = AtomicUsize::new(1);

#[derive(Clone, Copy, Debug)]
pub enum PFType {
    Pod,
    Service,
}

pub struct PFData {
    pub handle: tokio::task::JoinHandle<()>,
    pub cancel: Option<oneshot::Sender<()>>,
    pub pf_type: PFType,
    pub name: String,
    pub namespace: String,
    pub host: String,
    pub local_port: u16,
    pub remote_port: u16,
}

type PFResult<T> = Result<T, String>;

#[inline]
fn err<E: std::fmt::Display>(e: E) -> String {
    e.to_string()
}

pub fn portforward_start(
    _lua: &Lua,
    args: (String, String, String, String, u16, u16),
) -> LuaResult<usize> {
    let (pf_type_str, name, namespace, bind_host, local_port, remote_port) = args;

    let (client, rt) = {
        let client = {
            let g = CLIENT_INSTANCE.lock().unwrap();
            g.as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?
                .clone()
        };
        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
        (client, rt)
    };

    let pf_type = match pf_type_str.as_str() {
        "Pod" | "pod" => PFType::Pod,
        "Service" | "service" => PFType::Service,
        other => {
            return Err(mlua::Error::RuntimeError(format!(
                "Invalid pf_type: {other} (expected Pod|Service)"
            )))
        }
    };

    let id = PF_COUNTER.fetch_add(1, Ordering::SeqCst);
    let bind_addr = format!("{bind_host}:{local_port}");

    let listener = match rt.block_on(async { TcpListener::bind(&bind_addr).await }) {
        Ok(l) => {
            info!("pf#{id}: listening on {bind_addr}");
            l
        }
        Err(e) => {
            error!("pf#{id}: bind {bind_addr} failed: {e}");
            return Err(mlua::Error::RuntimeError(format!(
                "bind {bind_addr} failed: {e}"
            )));
        }
    };

    let (cancel_tx, cancel_rx) = oneshot::channel::<()>();

    let handle = rt.spawn(run_forward(
        client.clone(),
        pf_type,
        name.clone(),
        namespace.clone(),
        listener,
        remote_port,
        cancel_rx,
        id,
    ));

    let pf_data = PFData {
        handle,
        cancel: Some(cancel_tx),
        pf_type,
        name,
        namespace,
        host: bind_host,
        local_port,
        remote_port,
    };

    let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
    rt.block_on(async {
        pf_map.lock().await.insert(id, pf_data);
    });

    Ok(id)
}

pub fn portforward_list(lua: &Lua, _: ()) -> LuaResult<LuaTable> {
    let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
    let table = lua.create_table()?;
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    rt.block_on(async {
        let map = pf_map.lock().await;
        for (id, pf) in map.iter() {
            let row = lua.create_table()?;
            row.set("id", *id)?;
            row.set(
                "type",
                match pf.pf_type {
                    PFType::Pod => "pod",
                    PFType::Service => "service",
                },
            )?;
            row.set("name", pf.name.clone())?;
            row.set("namespace", pf.namespace.clone())?;
            row.set("host", pf.host.clone())?;
            row.set("local_port", pf.local_port)?;
            row.set("remote_port", pf.remote_port)?;
            table.set(*id, row)?;
        }
        Ok::<(), mlua::Error>(())
    })?;

    Ok(table)
}

pub fn portforward_stop(_lua: &Lua, id: usize) -> LuaResult<()> {
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    rt.block_on(async {
        let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
        let mut map = pf_map.lock().await;
        if let Some(mut data) = map.remove(&id) {
            if let Some(tx) = data.cancel.take() {
                let _ = tx.send(());
            }
            let _ = data.handle.await;
            Ok(())
        } else {
            Err(mlua::Error::RuntimeError(format!(
                "No port forward found for id {}",
                id
            )))
        }
    })
}

async fn run_forward(
    client: Client,
    pf_type: PFType,
    name: String,
    namespace: String,
    listener: TcpListener,
    remote_port: u16,
    mut cancel_rx: oneshot::Receiver<()>,
    id: usize,
) {
    if let Ok(addr) = listener.local_addr() {
        info!("pf#{id}: accept loop on {}", addr);
    }

    loop {
        tokio::select! {
            _ = &mut cancel_rx => {
                info!("pf#{id}: canceled");
                break;
            }
            accepted = listener.accept() => {
                match accepted {
                    Ok((sock, peer)) => {
                        debug!("pf#{id}: accepted {peer}");
                        let _ = sock.set_nodelay(true);

                        let c = client.clone();
                        let n = name.clone();
                        let ns = namespace.clone();
                        tokio::spawn(async move {
                            if let Err(e) = handle_connection(c, pf_type, ns, n, remote_port, sock).await {
                                warn!("connection closed with error: {e}");
                            }
                        });
                    }
                    Err(e) => {
                        warn!("pf#{id}: accept error: {e} (retrying)");
                        time::sleep(std::time::Duration::from_millis(200)).await;
                    }
                }
            }
        }
    }

    info!("pf#{id}: stopped");
}

async fn handle_connection(
    client: Client,
    pf_type: PFType,
    namespace: String,
    name: String,
    remote_port: u16,
    mut local: TcpStream,
) -> PFResult<()> {
    let pod = match pf_type {
        PFType::Pod => name,
        PFType::Service => resolve_pod_for_service(&client, &namespace, &name).await?,
    };

    let api: Api<Pod> = Api::namespaced(client, &namespace);
    let mut last: Option<String> = None;
    for backoff_ms in [0_u64, 75, 150] {
        if backoff_ms > 0 {
            time::sleep(std::time::Duration::from_millis(backoff_ms)).await;
        }
        match api.portforward(&pod, &[remote_port]).await {
            Ok(mut pf) => {
                if let Some(mut remote) = pf.take_stream(remote_port) {
                    tokio::io::copy_bidirectional(&mut local, &mut remote)
                        .await
                        .map_err(err)?;
                    let _ = local.shutdown().await;
                    let _ = remote.shutdown().await;
                    return Ok(());
                } else {
                    last = Some(format!("no stream for remote port {remote_port}"));
                }
            }
            Err(e) => last = Some(err(e)),
        }
    }
    Err(last.unwrap_or_else(|| "unknown port-forward error".into()))
}

async fn resolve_pod_for_service(client: &Client, ns: &str, svc: &str) -> PFResult<String> {
    if let Ok(eps) = Api::<Endpoints>::namespaced(client.clone(), ns)
        .get(svc)
        .await
    {
        if let Some(pod) = pick_pod_from_endpoints(eps) {
            debug!(service=%svc, pod=%pod, "resolved via Endpoints");
            return Ok(pod);
        }
    }

    let svc_api: Api<Service> = Api::namespaced(client.clone(), ns);
    let svc_obj = svc_api.get(svc).await.map_err(err)?;
    let selector = match svc_obj.spec.as_ref().and_then(|s| s.selector.clone()) {
        Some(m) if !m.is_empty() => m,
        Some(_) => return Err(format!("service {svc} has empty selector")),
        None => return Err(format!("service {svc} has no selector")),
    };

    let selector_str = selector
        .into_iter()
        .map(|(k, v)| format!("{k}={v}"))
        .collect::<Vec<_>>()
        .join(",");

    let pods = Api::<Pod>::namespaced(client.clone(), ns)
        .list(&ListParams::default().labels(&selector_str))
        .await
        .map_err(err)?
        .items;

    let pod = pods
        .into_iter()
        .find(is_pod_ready)
        .and_then(|p| p.metadata.name);

    pod.ok_or_else(|| format!("no Ready pods found for service {svc}"))
}

fn pick_pod_from_endpoints(eps: Endpoints) -> Option<String> {
    eps.subsets?
        .into_iter()
        .filter_map(|ss| ss.addresses)
        .flatten()
        .filter_map(|addr| addr.target_ref)
        .find_map(|tr| (tr.kind.as_deref() == Some("Pod")).then_some(tr.name))
        .flatten()
}

fn is_pod_ready(p: &Pod) -> bool {
    p.status
        .as_ref()
        .and_then(|s| s.conditions.as_ref())
        .and_then(|conds| conds.iter().find(|c| c.type_ == "Ready"))
        .map_or(false, |c| c.status == "True")
}
