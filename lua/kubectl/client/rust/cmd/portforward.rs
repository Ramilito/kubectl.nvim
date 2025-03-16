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

pub struct PFData {
    pub handle: tokio::task::JoinHandle<()>,
    pub cancel: Option<oneshot::Sender<()>>,
    pub pf_type: PFType,
    pub name: String,
    pub namespace: String,
    pub local_port: u16,
    pub remote_port: u16,
}

pub fn portforward_start(
    _lua: &Lua,
    args: (String, String, String, u16, u16),
) -> LuaResult<usize> {
    let (pf_type, name, namespace, local_port, remote_port) = args;

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

    let t_name = name.clone();
    let t_namespace = namespace.clone();

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
                    let t_pf_type = pf_type;
                    let t_remote_port = remote_port;

                    tokio::spawn(async move {
                        match t_pf_type {
                            PFType::Service => {
                                let mut pf = pf_api.portforward(&t_name_inner, &[t_remote_port]).await.unwrap();
                                let remote_stream = pf.take_stream(t_remote_port).unwrap();
                                proxy_conn(local_sock, remote_stream).await;
                            },
                            PFType::Pod => {
                                let mut pf = pf_api.portforward(&t_name_inner, &[t_remote_port]).await.unwrap();
                                let remote_stream = pf.take_stream(t_remote_port).unwrap();
                                proxy_conn(local_sock, remote_stream).await;
                            },
                        };
                    });
                }
            }
        }
    });

    let pf_data = PFData {
        handle: forward_handle,
        cancel: Some(cancel_tx),
        pf_type,
        name,
        namespace,
        local_port,
        remote_port,
    };

    let pf_map = PF_MAP.get().unwrap();
    rt_handle.block_on(async {
        pf_map.lock().await.insert(id, pf_data);
    });
    Ok(id)
}

// pub fn stop_port_forward_async(lua: &Lua, id: usize) -> LuaResult<()> {
//     let rt_option = futures::executor::block_on(RUNTIME.lock()).clone();
//     let rt = rt_option
//         .ok_or_else(|| LuaError::RuntimeError("Runtime not initialized".into()))?;
//
//     rt.block_on(async move {
//         let mut map = PF_MAP.lock().await;
//         if let Some(mut pf_data) = map.remove(&id) {
//             if let Some(tx) = pf_data.cancel.take() {
//                 let _ = tx.send(());
//             }
//             // Optionally, you could await the handle here if you want to ensure it's cleaned up:
//             let _ = pf_data.handle.await;
//         }
//     });
//
//     Ok(())
// }

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
