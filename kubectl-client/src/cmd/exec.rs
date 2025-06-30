use crate::{block_on, RUNTIME};
use kube::{
    api::{Api, AttachParams, AttachedProcess},
    Client, Error as KubeError,
};
use mlua::{prelude::*, UserData, UserDataMethods};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    runtime::{Handle, Runtime},
    sync::mpsc,
};

type Result<T> = std::result::Result<T, KubeError>;

#[tracing::instrument(skip(client))]
pub async fn open_exec(
    client: &Client,
    ns: &str,
    pod: &str,
    container: &Option<String>,
    cmd: &[String],
    tty: bool,
) -> Result<AttachedProcess> {
    let pods: Api<k8s_openapi::api::core::v1::Pod> = Api::namespaced(client.clone(), ns);
    let attach = AttachParams {
        stdout: true,
        stderr: !tty,
        stdin: true,
        tty,
        container: container.clone(),
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
        container: Option<String>,
        cmd: Vec<String>,
        tty: bool,
    ) -> LuaResult<Self> {
        let mut proc = block_on(open_exec(&client, &ns, &pod, &container, &cmd, tty))
            .map_err(LuaError::external)?;

        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
        // ---- wire channels ----------------------------------------------------
        let (tx_in, mut rx_in) = mpsc::unbounded_channel::<Vec<u8>>();
        let (tx_out, rx_out) = mpsc::unbounded_channel::<Vec<u8>>();
        let open = Arc::new(AtomicBool::new(true));

        // writer
        if let Some(mut stdin) = proc.stdin() {
            let flag = open.clone();
            rt.spawn(async move {
                while let Some(buf) = rx_in.recv().await {
                    if stdin.write_all(&buf).await.is_err() {
                        break;
                    }
                }
                flag.store(false, Ordering::Release);
            });
        }

        // single reader (stdout + merged‑stderr)
        if let Some(mut stdout) = proc.stdout() {
            let flag = open.clone();
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
                flag.store(false, Ordering::Release);
            });
        }

        Ok(Self {
            tx_in,
            rx_out: Mutex::new(rx_out),
            open,
        })
    }

    // ---------- Lua‑visible helpers ------------------------------------------
    fn read_chunk(&self) -> Option<String> {
        self.rx_out
            .lock()
            .unwrap()
            .try_recv()
            .ok()
            .map(|v| String::from_utf8_lossy(&v).into_owned())
    }

    fn write(&self, s: &str) {
        let _ = self.tx_in.send(s.as_bytes().to_vec());
    }
    fn is_open(&self) -> bool {
        self.open.load(Ordering::Acquire)
    }
    fn close(&self) {
        self.open.store(false, Ordering::Release);
    }
}

impl UserData for Session {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("read_chunk", |_, this, ()| Ok(this.read_chunk()));
        m.add_method("write", |_, this, s: String| {
            this.write(&s);
            Ok(())
        });
        m.add_method("open", |_, this, ()| Ok(this.is_open()));
        m.add_method("close", |_, this, ()| {
            this.close();
            Ok(())
        });
    }
}
