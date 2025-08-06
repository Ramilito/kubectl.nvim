use k8s_openapi::api::core::v1::{Pod, Service};
use kube::{api::ListParams, Api, Client};
use mlua::prelude::*;
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;
use tokio::net::TcpListener;
use tokio::runtime::Runtime;
use tokio::sync::{oneshot, Mutex};

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
        "Pod" => PFType::Pod,
        "Service" => PFType::Service,
        _ => {
            return Err(mlua::Error::RuntimeError(
                "Invalid pf_type string".to_owned(),
            ))
        }
    };

    let id = PF_COUNTER.fetch_add(1, Ordering::SeqCst);
    let (cancel_tx, cancel_rx) = oneshot::channel::<()>();

    let spawn_handle = rt.spawn(run_port_forward(
        client.clone(),
        forward_type,
        name.clone(),
        namespace.clone(),
        bind_address.clone(),
        local_port,
        remote_port,
        cancel_rx,
    ));

    let pf_data = PFData {
        handle: spawn_handle,
        cancel: Some(cancel_tx),
        pf_type: forward_type,
        name,
        namespace,
        host: bind_address.clone(),
        local_port,
        remote_port,
    };

    let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
    rt.block_on(async {
        pf_map.lock().await.insert(id, pf_data);
    });
    Ok(id)
}

#[tracing::instrument(skip(client))]
async fn run_port_forward(
    client: Client,
    pf_type: PFType,
    name: String,
    namespace: String,
    bind_address: String,
    local_port: u16,
    remote_port: u16,
    mut cancel_rx: oneshot::Receiver<()>,
) {
    let listener_addr = format!("{}:{}", bind_address, local_port);
    let listener = match TcpListener::bind(&listener_addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("Failed to bind to {}: {}", listener_addr, e);
            return;
        }
    };

    loop {
        tokio::select! {
            _ = &mut cancel_rx => {
                break;
            },
            incoming = listener.accept() => {
                let (sock, _) = match incoming {
                    Ok(v) => v,
                    Err(e) => {
                        eprintln!("Accept error: {}", e);
                        break;
                    }
                };
                let c = client.clone();
                let n = name.clone();
                let ns = namespace.clone();
                tokio::spawn(async move {
                    match pf_type {
                        PFType::Pod => forward_pod(c, ns, n, remote_port, sock).await,
                        PFType::Service => forward_service(c, ns, n, remote_port, sock).await,
                    }
                });
            }
        }
    }
}

#[tracing::instrument(skip(client))]
async fn forward_pod(
    client: Client,
    namespace: String,
    pod_name: String,
    remote_port: u16,
    local_sock: tokio::net::TcpStream,
) {
    let api: Api<Pod> = Api::namespaced(client, &namespace);
    match api.portforward(&pod_name, &[remote_port]).await {
        Ok(mut pf) => {
            if let Some(stream) = pf.take_stream(remote_port) {
                proxy_conn(local_sock, stream).await;
            }
        }
        Err(e) => {
            eprintln!("Pod portforward error for {}: {}", pod_name, e);
        }
    }
}

#[tracing::instrument(skip(client))]
async fn forward_service(
    client: Client,
    namespace: String,
    svc_name: String,
    remote_port: u16,
    local_sock: tokio::net::TcpStream,
) {
    let svc_api: Api<Service> = Api::namespaced(client.clone(), &namespace);
    let service = match svc_api.get(&svc_name).await {
        Ok(svc) => svc,
        Err(e) => {
            eprintln!("Failed to get service {}: {}", svc_name, e);
            return;
        }
    };
    let selector = match service.spec.and_then(|spec| spec.selector) {
        Some(sel) if !sel.is_empty() => sel,
        _ => {
            eprintln!("Service {} has no valid selector", svc_name);
            return;
        }
    };
    let selector_str = selector
        .into_iter()
        .map(|(k, v)| format!("{}={}", k, v))
        .collect::<Vec<_>>()
        .join(",");
    let pod_api: Api<Pod> = Api::namespaced(client, &namespace);
    let pods = match pod_api
        .list(&ListParams::default().labels(&selector_str))
        .await
    {
        Ok(list) => list.items,
        Err(e) => {
            eprintln!("Failed to list pods for service {}: {}", svc_name, e);
            return;
        }
    };
    let pod = match pods.first() {
        Some(p) => p,
        None => {
            eprintln!("No pods found for service {}", svc_name);
            return;
        }
    };
    let pod_name = match &pod.metadata.name {
        Some(n) => n.clone(),
        None => {
            eprintln!("Pod with no name in service {}", svc_name);
            return;
        }
    };
    forward_pod(
        pod_api.into_client(),
        namespace,
        pod_name,
        remote_port,
        local_sock,
    )
    .await;
}

async fn proxy_conn<S>(local_sock: tokio::net::TcpStream, remote_stream: S)
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let (mut r_read, mut r_write) = tokio::io::split(remote_stream);
    let (mut l_read, mut l_write) = tokio::io::split(local_sock);

    let in_task = tokio::spawn(async move {
        let _ = tokio::io::copy(&mut l_read, &mut r_write).await;
    });
    let out_task = tokio::spawn(async move {
        let _ = tokio::io::copy(&mut r_read, &mut l_write).await;
    });
    let _ = tokio::join!(in_task, out_task);
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
