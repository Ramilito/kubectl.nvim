use k8s_openapi::api::core::v1::{Endpoints, Pod, Service};
use kube::{api::ListParams, Api, Client};
use mlua::prelude::*;
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;
use tokio::net::TcpListener;
use tokio::runtime::Runtime;
use tokio::sync::{oneshot, Mutex};
use tokio::{io, time};
use tracing::{debug, error, info, warn};

use crate::{CLIENT_INSTANCE, RUNTIME};

static PF_MAP: OnceLock<Mutex<HashMap<usize, PFData>>> = OnceLock::new();
static PF_COUNTER: AtomicUsize = AtomicUsize::new(1);
static CONN_COUNTER: AtomicUsize = AtomicUsize::new(1);

#[derive(Clone, Copy, Debug)]
pub enum PFType {
    Pod,
    Service,
}

#[allow(dead_code)]
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

#[tracing::instrument]
pub fn portforward_start(
    _lua: &Lua,
    args: (String, String, String, String, u16, u16),
) -> LuaResult<usize> {
    let (pf_type_str, name, namespace, bind_address, local_port, remote_port) = args;

    let (client, rt) = {
        let client = {
            let client_guard = CLIENT_INSTANCE.lock().unwrap();
            client_guard
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".to_string()))?
                .clone()
        };
        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
        (client, rt)
    };

    let forward_type = match pf_type_str.as_str() {
        "Pod" | "pod" => PFType::Pod,
        "Service" | "service" => PFType::Service,
        other => {
            return Err(mlua::Error::RuntimeError(format!(
                "Invalid pf_type string: {} (expected Pod|Service)",
                other
            )))
        }
    };

    let id = PF_COUNTER.fetch_add(1, Ordering::SeqCst);
    let (cancel_tx, cancel_rx) = oneshot::channel::<()>();
    let (ready_tx, ready_rx) = oneshot::channel::<Result<(), String>>();

    // spawn the listener/accept loop
    let handle = rt.spawn(run_port_forward(
        client.clone(),
        forward_type,
        name.clone(),
        namespace.clone(),
        bind_address.clone(),
        local_port,
        remote_port,
        cancel_rx,
        Some(ready_tx),
    ));

    // Wait until the task bound the local port (fast path) before we publish the handle.
    // If binding failed, surface it to the caller.
    match rt.block_on(ready_rx) {
        Ok(Ok(())) => {
            let pf_data = PFData {
                handle,
                cancel: Some(cancel_tx),
                pf_type: forward_type,
                name,
                namespace,
                host: bind_address,
                local_port,
                remote_port,
            };
            let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
            rt.block_on(async {
                pf_map.lock().await.insert(id, pf_data);
            });
            Ok(id)
        }
        Ok(Err(reason)) => {
            // background task failed to bind – ensure it is ended
            let _ = rt.block_on(async { handle.await });
            Err(mlua::Error::RuntimeError(format!(
                "Portforward failed to start: {}",
                reason
            )))
        }
        Err(_canceled) => {
            let _ = rt.block_on(async { handle.await });
            Err(mlua::Error::RuntimeError(
                "Portforward start failed (internal)".to_string(),
            ))
        }
    }
}

#[tracing::instrument(skip(client, cancel_rx, ready))]
async fn run_port_forward(
    client: Client,
    pf_type: PFType,
    name: String,
    namespace: String,
    bind_address: String,
    local_port: u16,
    remote_port: u16,
    mut cancel_rx: oneshot::Receiver<()>,
    ready: Option<oneshot::Sender<Result<(), String>>>,
) {
    let listener_addr = format!("{}:{}", bind_address, local_port);
    let listener = match TcpListener::bind(&listener_addr).await {
        Ok(l) => {
            if let Some(tx) = ready {
                let _ = tx.send(Ok(()));
            }
            info!("Portforward listening on {}", listener_addr);
            l
        }
        Err(e) => {
            if let Some(tx) = ready {
                let _ = tx.send(Err(format!("bind {} failed: {}", listener_addr, e)));
            }
            error!("Failed to bind to {}: {}", listener_addr, e);
            return;
        }
    };

    // Accept loop: keep running until canceled.
    loop {
        tokio::select! {
            _ = &mut cancel_rx => {
                info!("Portforward {} canceled; closing listener {}", name, listener_addr);
                break;
            }

            accept_res = listener.accept() => {
                match accept_res {
                    Ok((sock, peer)) => {
                        let conn_id = CONN_COUNTER.fetch_add(1, Ordering::SeqCst);
                        debug!(%peer, conn_id, "accepted local connection");

                        // a little QoL: avoid Nagle delays for interactive streams
                        let _ = sock.set_nodelay(true);

                        let c = client.clone();
                        let n = name.clone();
                        let ns = namespace.clone();
                        tokio::spawn(async move {
                            if let Err(e) = handle_single_connection(c, pf_type, ns, n, remote_port, sock, conn_id).await {
                                warn!(conn_id, "connection ended with error: {}", e);
                            }
                        });
                    }
                    Err(e) => {
                        warn!("accept error on {}: {} (will retry)", listener_addr, e);
                        time::sleep(time::Duration::from_millis(200)).await;
                        continue;
                    }
                }
            }
        }
    }

    info!("Portforward {} stopped", name);
}

#[tracing::instrument(skip(client, local_sock))]
async fn handle_single_connection(
    client: Client,
    pf_type: PFType,
    namespace: String,
    name: String,
    remote_port: u16,
    mut local_sock: tokio::net::TcpStream,
    conn_id: usize,
) -> anyhow::Result<()> {
    // Resolve the target pod name for this connection.
    let pod_name = match pf_type {
        PFType::Pod => name.clone(),
        PFType::Service => resolve_pod_for_service(&client, &namespace, &name).await?,
    };

    // Short bounded retry when creating the port-forward (helps with occasional API-server hiccups).
    const MAX_TRIES: usize = 3;
    let mut attempt = 0usize;
    let mut last_err: Option<anyhow::Error> = None;

    let api: Api<Pod> = Api::namespaced(client.clone(), &namespace);

    while attempt < MAX_TRIES {
        attempt += 1;
        match api.portforward(&pod_name, &[remote_port]).await {
            Ok(mut pf) => {
                // Option<Box<dyn AsyncRead + AsyncWrite + Unpin + Send>>
                if let Some(mut remote_stream) = pf.take_stream(remote_port) {
                    debug!(conn_id, %pod_name, "port-forward stream established");
                    proxy_bidirectional(&mut local_sock, &mut remote_stream).await?;
                    debug!(conn_id, "io proxy completed");
                    return Ok(());
                } else {
                    let e = anyhow::anyhow!("no stream for remote port {}", remote_port);
                    last_err = Some(e);
                }
            }
            Err(e) => {
                last_err = Some(anyhow::anyhow!(e));
            }
        }

        if attempt < MAX_TRIES {
            let backoff = 50u64 * (1 << (attempt - 1)); // 50ms, 100ms
            debug!(conn_id, attempt, backoff, "retrying portforward creation");
            time::sleep(time::Duration::from_millis(backoff)).await;
        }
    }

    Err(last_err.unwrap_or_else(|| anyhow::anyhow!("unknown portforward error")))
}

#[tracing::instrument(skip(local, remote))]
async fn proxy_bidirectional(
    local: &mut tokio::net::TcpStream,
    remote: &mut (impl tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin),
) -> io::Result<()> {
    use tokio::io::AsyncWriteExt;

    // Pipe both directions until EOF or error.
    let _bytes = tokio::io::copy_bidirectional(local, remote).await?;

    // Try to close both sides nicely.
    let _ = local.shutdown().await;
    // remote is a generic stream; we cannot always call shutdown() on it
    // (Box<dyn AsyncWrite> doesn't expose it), so we just drop it by returning.

    Ok(())
}

/// Pick a Ready Pod behind a Service.
/// Prefer Endpoints (ready addresses) and fall back to selector-based pods.
#[tracing::instrument(skip(client))]
async fn resolve_pod_for_service(client: &Client, namespace: &str, svc_name: &str) -> anyhow::Result<String> {
    // 1) Try Endpoints: this gives us actual, *ready* backends with targetRef to pods.
    let eps_api: Api<Endpoints> = Api::namespaced(client.clone(), namespace);
    if let Ok(eps) = eps_api.get(svc_name).await {
        if let Some(subsets) = eps.subsets {
            for ss in subsets {
                if let Some(addresses) = ss.addresses {
                    for addr in addresses {
                        if let Some(tref) = addr.target_ref {
                            if tref.kind.as_deref() == Some("Pod") {
                                if let Some(pod_name) = tref.name {
                                    debug!(%svc_name, %pod_name, "resolved via Endpoints");
                                    return Ok(pod_name);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 2) Fall back to selector-based listing and pick a Ready pod.
    let svc_api: Api<Service> = Api::namespaced(client.clone(), namespace);
    let service = svc_api
        .get(svc_name)
        .await
        .map_err(|e| anyhow::anyhow!("get service {} failed: {}", svc_name, e))?;

    let selector = service
        .spec
        .as_ref()
        .and_then(|spec| spec.selector.clone())
        .ok_or_else(|| anyhow::anyhow!("service {} has no selector", svc_name))?;

    if selector.is_empty() {
        return Err(anyhow::anyhow!("service {} has empty selector", svc_name));
    }

    let selector_str = selector
        .into_iter()
        .map(|(k, v)| format!("{}={}", k, v))
        .collect::<Vec<_>>()
        .join(",");

    let pod_api: Api<Pod> = Api::namespaced(client.clone(), namespace);
    let pods = pod_api
        .list(&ListParams::default().labels(&selector_str))
        .await
        .map_err(|e| anyhow::anyhow!("list pods for service {} failed: {}", svc_name, e))?
        .items;

    let mut ready_pod_name = None::<String>;
    for p in &pods {
        if is_pod_ready(p) {
            if let Some(n) = p.metadata.name.clone() {
                ready_pod_name = Some(n);
                break;
            }
        }
    }

    if let Some(n) = ready_pod_name {
        debug!(%svc_name, pod=%n, "resolved via selector");
        Ok(n)
    } else {
        Err(anyhow::anyhow!(
            "no Ready pods found for service {} ({} pods matched)",
            svc_name,
            pods.len()
        ))
    }
}

fn is_pod_ready(p: &Pod) -> bool {
    p.status
        .as_ref()
        .and_then(|s| s.conditions.as_ref())
        .and_then(|conds| {
            conds.iter().find(|c| c.type_ == "Ready").map(|c| c.status.as_str() == "True")
        })
        .unwrap_or(false)
}

pub fn portforward_list(lua: &Lua, _: ()) -> LuaResult<LuaTable> {
    let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
    let table = lua.create_table()?;
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    rt.block_on(async {
        let map = pf_map.lock().await;
        for (id, pf) in map.iter() {
            let entry = lua.create_table()?;
            entry.set("id", *id)?;
            entry.set(
                "type",
                match pf.pf_type {
                    PFType::Pod => "pod",
                    PFType::Service => "service",
                },
            )?;
            entry.set("name", pf.name.clone())?;
            entry.set("namespace", pf.namespace.clone())?;
            entry.set("host", pf.host.clone())?;
            entry.set("local_port", pf.local_port)?;
            entry.set("remote_port", pf.remote_port)?;
            table.set(*id, entry)?;
        }
        Ok::<(), mlua::Error>(())
    })?;

    Ok(table)
}

#[tracing::instrument]
pub fn portforward_stop(_lua: &Lua, id: usize) -> LuaResult<()> {
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    rt.block_on(async {
        let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
        let mut map = pf_map.lock().await;
        if let Some(mut data) = map.remove(&id) {
            if let Some(tx) = data.cancel.take() {
                let _ = tx.send(());
            }
            // The main accept loop will exit; individual connection tasks will finish naturally
            // as their sockets close. We don't track/abort them individually by design.
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
