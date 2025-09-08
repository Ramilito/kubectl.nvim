use k8s_openapi::api::core::v1::{Endpoints, Pod, Service};
use kube::{api::ListParams, Api, Client};
use mlua::prelude::*;
use std::collections::HashMap;
use std::fmt;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;
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

#[derive(Debug)]
enum PFError {
    Io(std::io::Error),
    Kube(kube::Error),
    Msg(String),
}

impl fmt::Display for PFError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PFError::Io(e) => write!(f, "io error: {}", e),
            PFError::Kube(e) => write!(f, "kube error: {}", e),
            PFError::Msg(s) => write!(f, "{}", s),
        }
    }
}

impl From<std::io::Error> for PFError {
    fn from(e: std::io::Error) -> Self {
        PFError::Io(e)
    }
}
impl From<kube::Error> for PFError {
    fn from(e: kube::Error) -> Self {
        PFError::Kube(e)
    }
}

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

    let pf_type = match pf_type_str.as_str() {
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
    let addr = format!("{}:{}", bind_address, local_port);

    let listener = match rt.block_on(async { TcpListener::bind(&addr).await }) {
        Ok(l) => {
            info!("Portforward listening on {}", addr);
            l
        }
        Err(e) => {
            error!("Failed to bind to {}: {}", addr, e);
            return Err(mlua::Error::RuntimeError(format!(
                "bind {} failed: {}",
                addr, e
            )));
        }
    };

    let (cancel_tx, cancel_rx) = oneshot::channel::<()>();

    let handle = rt.spawn(run_port_forward(
        client.clone(),
        pf_type,
        name.clone(),
        namespace.clone(),
        listener, // <-- already bound
        remote_port,
        cancel_rx,
    ));

    let pf_data = PFData {
        handle,
        cancel: Some(cancel_tx),
        pf_type,
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

async fn run_port_forward(
    client: Client,
    pf_type: PFType,
    name: String,
    namespace: String,
    listener: TcpListener,
    remote_port: u16,
    mut cancel_rx: oneshot::Receiver<()>,
) {
    let listener_addr = listener.local_addr().ok();
    if let Some(addr) = listener_addr {
        info!("Portforward {}: accept loop on {}", name, addr);
    }

    loop {
        tokio::select! {
            _ = &mut cancel_rx => {
                info!("Portforward {} canceled; closing listener", name);
                break;
            }
            accept_res = listener.accept() => {
                match accept_res {
                    Ok((sock, peer)) => {
                        debug!(%peer, "accepted local connection");
                        let _ = sock.set_nodelay(true);

                        let c = client.clone();
                        let n = name.clone();
                        let ns = namespace.clone();
                        tokio::spawn(async move {
                            if let Err(e) = handle_single_connection(c, pf_type, ns, n, remote_port, sock).await {
                                warn!("connection ended with error: {}", e);
                            }
                        });
                    }
                    Err(e) => {
                        warn!("accept error: {} (will retry)", e);
                        time::sleep(std::time::Duration::from_millis(200)).await;
                    }
                }
            }
        }
    }

    info!("Portforward {} stopped", name);
}

async fn handle_single_connection(
    client: Client,
    pf_type: PFType,
    namespace: String,
    name: String,
    remote_port: u16,
    mut local_sock: TcpStream,
) -> Result<(), PFError> {
    let pod_name = match pf_type {
        PFType::Pod => name.clone(),
        PFType::Service => resolve_pod_for_service(&client, &namespace, &name).await?,
    };

    const MAX_TRIES: usize = 3;
    let api: Api<Pod> = Api::namespaced(client.clone(), &namespace);
    let mut attempt = 0usize;
    let mut last_err: Option<PFError> = None;

    while attempt < MAX_TRIES {
        attempt += 1;
        match api.portforward(&pod_name, &[remote_port]).await {
            Ok(mut pf) => {
                if let Some(mut remote_stream) = pf.take_stream(remote_port) {
                    debug!(pod=%pod_name, "port-forward stream established");
                    proxy_bidirectional(&mut local_sock, &mut remote_stream).await?;
                    debug!("io proxy completed");
                    return Ok(());
                } else {
                    last_err = Some(PFError::Msg(format!(
                        "no stream for remote port {}",
                        remote_port
                    )));
                }
            }
            Err(e) => {
                last_err = Some(PFError::from(e));
            }
        }

        if attempt < MAX_TRIES {
            let backoff = 50u64 * (1 << (attempt - 1)); // 50ms, 100ms
            debug!(attempt, backoff, "retrying portforward creation");
            time::sleep(std::time::Duration::from_millis(backoff)).await;
        }
    }

    Err(last_err.unwrap_or_else(|| PFError::Msg("unknown portforward error".to_string())))
}

async fn proxy_bidirectional(
    local: &mut TcpStream,
    remote: &mut (impl tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin),
) -> Result<(), PFError> {
    use tokio::io::AsyncWriteExt;

    tokio::io::copy_bidirectional(local, remote)
        .await
        .map_err(PFError::from)?;
    let _ = local.shutdown().await;
    let _ = remote.shutdown().await;
    Ok(())
}

async fn resolve_pod_for_service(
    client: &Client,
    namespace: &str,
    svc_name: &str,
) -> Result<String, PFError> {
    let eps_api: Api<Endpoints> = Api::namespaced(client.clone(), namespace);
    if let Ok(eps) = eps_api.get(svc_name).await {
        if let Some(subsets) = eps.subsets {
            for ss in subsets {
                if let Some(addresses) = ss.addresses {
                    for addr in addresses {
                        if let Some(tref) = addr.target_ref {
                            if tref.kind.as_deref() == Some("Pod") {
                                if let Some(pod_name) = tref.name {
                                    debug!(service=%svc_name, pod=%pod_name, "resolved via Endpoints");
                                    return Ok(pod_name);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    let svc_api: Api<Service> = Api::namespaced(client.clone(), namespace);
    let service = svc_api.get(svc_name).await.map_err(PFError::from)?;

    let selector = service
        .spec
        .as_ref()
        .and_then(|spec| spec.selector.clone())
        .ok_or_else(|| PFError::Msg(format!("service {} has no selector", svc_name)))?;

    if selector.is_empty() {
        return Err(PFError::Msg(format!(
            "service {} has empty selector",
            svc_name
        )));
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
        .map_err(PFError::from)?
        .items;

    for p in &pods {
        if is_pod_ready(p) {
            if let Some(n) = p.metadata.name.clone() {
                debug!(service=%svc_name, pod=%n, "resolved via selector (Ready)");
                return Ok(n);
            }
        }
    }

    Err(PFError::Msg(format!(
        "no Ready pods found for service {} ({} pods matched)",
        svc_name,
        pods.len()
    )))
}

fn is_pod_ready(p: &Pod) -> bool {
    p.status
        .as_ref()
        .and_then(|s| s.conditions.as_ref())
        .and_then(|conds| {
            conds
                .iter()
                .find(|c| c.type_ == "Ready")
                .map(|c| c.status.as_str() == "True")
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
