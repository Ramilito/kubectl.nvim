use crate::{block_on, RUNTIME};
use kube::api::AttachParams;
use kube::{Api, Client, Error as KubeError};
use mlua::{prelude::*, UserData, UserDataMethods};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use tokio::runtime::Runtime;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    sync::mpsc,
};

type Result<T> = std::result::Result<T, KubeError>;

#[tracing::instrument(skip(client))]
pub async fn open_exec(
    client: &Client,
    ns: &str,
    pod: &str,
    cmd: &Vec<String>,
    tty: bool,
) -> Result<kube::api::AttachedProcess> {
    let pods: Api<k8s_openapi::api::core::v1::Pod> = Api::namespaced(client.clone(), ns);

    let attach = AttachParams {
        stdout: true,
        stderr: !tty,
        stdin: true,
        tty: true,
        ..Default::default()
    };

    pods.exec(pod, cmd, &attach).await
}

pub struct Session {
    tx_in: mpsc::UnboundedSender<Vec<u8>>,
    rx_out: Mutex<mpsc::UnboundedReceiver<Vec<u8>>>,
    open: Arc<AtomicBool>,
}

impl Session {
    #[tracing::instrument(skip(client))]
    pub fn new(
        client: Client,
        ns: String,
        pod: String,
        cmd: Vec<String>,
        tty: bool,
    ) -> LuaResult<Self> {
        let mut proc =
            block_on(open_exec(&client, &ns, &pod, &cmd, tty)).map_err(LuaError::external)?;

        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
        /* 2 ▸ Channels between Lua and async tasks */
        let (tx_in, mut rx_in) = mpsc::unbounded_channel::<Vec<u8>>();
        let (tx_out, rx_out) = mpsc::unbounded_channel::<Vec<u8>>();
        let open = Arc::new(AtomicBool::new(true));
        let open_w = open.clone();
        let open_r = open.clone();

        /* 3 ▸ Spawn background writer */
        if let Some(mut stdin) = proc.stdin() {
            rt.spawn(async move {
                while let Some(buf) = rx_in.recv().await {
                    if stdin.write_all(&buf).await.is_err() {
                        break;
                    }
                }
                open_w.store(false, Ordering::Release);
            });
        }

        /* 4 ▸ Spawn background reader */
        if let Some(mut stdout) = proc.stdout() {
            rt.spawn(async move {
                let mut buf = [0u8; 4096];
                loop {
                    match stdout.read(&mut buf).await {
                        Ok(0) | Err(_) => break,
                        Ok(n) => {
                            let _ = tx_out.send(buf[..n].to_vec());
                        }
                    }
                }
                open_r.store(false, Ordering::Release);
            });
        }

        Ok(Self {
            tx_in,
            rx_out: Mutex::new(rx_out),
            open,
        })
    }

    /* ---------- called from Lua ---------- */
    fn read_chunk(&self) -> Option<String> {
        match self.rx_out.lock().unwrap().try_recv() {
            Ok(bytes) => Some(String::from_utf8_lossy(&bytes).into_owned()),
            _ => None,
        }
    }

    fn write(&self, s: &str) {
        let _ = self.tx_in.send(s.as_bytes().to_vec());
    }

    fn is_open(&self) -> bool {
        self.open.load(Ordering::Acquire)
    }

    fn close(&self) {
        self.open.store(false, Ordering::Release);
        // self.tx_in.close_channel();
    }
}

impl UserData for Session {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("read_chunk", |_, this, ()| Ok(this.read_chunk()));
        m.add_method("write", |_, this, data: String| {
            this.write(&data);
            Ok(())
        });
        m.add_method("open", |_, this, ()| Ok(this.is_open()));
        m.add_method("close", |_, this, ()| {
            this.close();
            Ok(())
        });
    }
}
