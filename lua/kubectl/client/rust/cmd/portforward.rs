use k8s_openapi::api::core::v1::Pod;
use kube::Api;
use mlua::prelude::*;
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;
use tokio::net::TcpListener;
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
    pub local_port: u16,
    pub remote_port: u16,
}

pub fn portforward_start(_lua: &Lua, args: (String, String, String, u16, u16)) -> LuaResult<usize> {
    let (pf_type_str, name, namespace, local_port, remote_port) = args;

    let (client, rt_handle) = {
        let client = {
            let client_guard = CLIENT_INSTANCE.lock().unwrap();
            client_guard
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".to_string()))?
                .clone()
        };

        let rt_handle = {
            let rt_guard = RUNTIME.lock().unwrap();
            rt_guard
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".to_string()))?
                .handle()
                .clone()
        };

        (client, rt_handle)
    };

    let id = PF_COUNTER.fetch_add(1, Ordering::SeqCst);
    let (cancel_tx, cancel_rx) = oneshot::channel::<()>();

    // Clone for use inside the async task
    let t_name = name.clone();
    let t_namespace = namespace.clone();
    let t_pf_type_str = pf_type_str.clone();

    let forward_handle = rt_handle.spawn(async move {
        let pods: Api<Pod> = Api::namespaced(client.clone(), &t_namespace);
        let listener_addr = format!("127.0.0.1:{}", local_port);
        let listener = match TcpListener::bind(&listener_addr).await {
            Ok(l) => l,
            Err(e) => {
                eprintln!("Failed to bind to {}: {}", listener_addr, e);
                return;
            }
        };

        // Pin the cancel receiver for use with tokio::select!
        tokio::pin!(cancel_rx);

        loop {
            tokio::select! {
                _ = &mut cancel_rx => {
                    break;
                },
                accept_result = listener.accept() => {
                    let (local_sock, _) = match accept_result {
                        Ok(ok) => ok,
                        Err(e) => {
                            eprintln!("Accept error: {}", e);
                            break;
                        }
                    };
                    let pf_api = pods.clone();
                    let t_name_inner = t_name.clone();
                    let t_pf_type = t_pf_type_str.clone();
                    tokio::spawn(async move {
                        match t_pf_type.as_str() {
                            "service" => {
                                let mut pf = pf_api.portforward(&t_name_inner, &[remote_port]).await.unwrap();
                                let remote_stream = pf.take_stream(remote_port).unwrap();
                                proxy_conn(local_sock, remote_stream).await;
                            },
                            "pod" => {
                                let mut pf = pf_api.portforward(&t_name_inner, &[remote_port]).await.unwrap();
                                let remote_stream = pf.take_stream(remote_port).unwrap();
                                proxy_conn(local_sock, remote_stream).await;
                            },
                            other => {
                                eprintln!("Unknown port forward type: {}", other);
                            }
                        }
                    });
                }
            }
        }
    });

    let pf_type_enum = match pf_type_str.as_str() {
        "service" => PFType::Service,
        "pod" => PFType::Pod,
        _ => {
            return Err(mlua::Error::RuntimeError(
                "Invalid pf_type string".to_string(),
            ))
        }
    };
    let pf_data = PFData {
        handle: forward_handle,
        cancel: Some(cancel_tx),
        pf_type: pf_type_enum,
        name,
        namespace,
        local_port,
        remote_port,
    };

    let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
    rt_handle.block_on(async {
        pf_map.lock().await.insert(id, pf_data);
    });
    Ok(id)
}

async fn proxy_conn<S>(local_sock: tokio::net::TcpStream, remote_stream: S)
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let (mut remote_reader, mut remote_writer) = tokio::io::split(remote_stream);
    let (mut local_reader, mut local_writer) = tokio::io::split(local_sock);

    let forward_in = tokio::spawn(async move {
        let _ = tokio::io::copy(&mut local_reader, &mut remote_writer).await;
    });
    let forward_out = tokio::spawn(async move {
        let _ = tokio::io::copy(&mut remote_reader, &mut local_writer).await;
    });

    let _ = tokio::join!(forward_in, forward_out);
}

pub fn portforward_list(lua: &Lua, _: ()) -> LuaResult<LuaTable> {
    let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
    let table = lua.create_table()?;

    let rt_handle = {
        let rt_guard = RUNTIME.lock().unwrap();
        rt_guard
            .as_ref()
            .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".to_string()))?
            .handle()
            .clone()
    };

    rt_handle.block_on(async {
        let map = pf_map.lock().await;
        for (id, pf_data) in map.iter() {
            let entry = lua.create_table()?;
            entry.set("id", *id)?;
            entry.set(
                "type",
                match pf_data.pf_type {
                    PFType::Pod => "pod",
                    PFType::Service => "service",
                },
            )?;
            entry.set("name", pf_data.name.clone())?;
            entry.set("namespace", pf_data.namespace.clone())?;
            entry.set("local_port", pf_data.local_port)?;
            entry.set("remote_port", pf_data.remote_port)?;
            table.set(*id, entry)?;
        }

        Ok::<(), mlua::Error>(())
    })?;

    Ok(table)
}

pub fn portforward_stop(_lua: &Lua, args: usize) -> LuaResult<()> {
    let id = args;
    let rt_handle = {
        let rt_guard = RUNTIME.lock().unwrap();
        rt_guard
            .as_ref()
            .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".to_string()))?
            .handle()
            .clone()
    };

    rt_handle.block_on(async move {
        let pf_map = PF_MAP.get_or_init(|| Mutex::new(HashMap::new()));
        let mut map = pf_map.lock().await;
        if let Some(mut pf_data) = map.remove(&id) {
            if let Some(cancel_tx) = pf_data.cancel.take() {
                let _ = cancel_tx.send(());
            }
            let _ = pf_data.handle.await;
            Ok::<(), mlua::Error>(())
        } else {
            Err(mlua::Error::RuntimeError(format!(
                "No port forward found for id {}",
                id
            )))
        }
    })
}
