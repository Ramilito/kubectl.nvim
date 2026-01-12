use crate::streaming::BidirectionalSession;
use crate::{block_on, RUNTIME};
use k8s_openapi::{
    api::core::v1::{EphemeralContainer, Pod},
    serde_json::{self, json},
};
use kube::{
    api::{Api, AttachParams, AttachedProcess, Patch, PatchParams},
    Client, Error as KubeError,
};
use mlua::{prelude::*, UserData, UserDataMethods};
use std::time::Duration;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    runtime::Runtime,
    time::{sleep, timeout},
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

#[tracing::instrument(skip(client))]
pub fn open_debug(
    client: Client,
    ns: String,
    pod: String,
    image: String,
    target: Option<String>,
) -> LuaResult<Session> {
    let debug_name = format!("debug-{}", uuid::Uuid::new_v4().simple());

    let mut ectr = EphemeralContainer {
        name: debug_name.clone(),
        image: Some(image),
        stdin: Some(true),
        tty: Some(true),
        ..Default::default()
    };
    if let Some(t) = target.clone() {
        ectr.target_container_name = Some(t);
    }
    let patch: Pod =
        serde_json::from_value(json!({ "spec": { "ephemeralContainers": [ ectr ] }}))
            .map_err(|e| LuaError::external(format!("failed to build debug patch: {e}")))?;
    block_on(async {
        let pods: Api<Pod> = Api::namespaced(client.clone(), &ns);

        pods.patch_ephemeral_containers(
            &pod,
            &PatchParams::apply("kubectl-client-debug"),
            &Patch::Strategic(patch),
        )
        .await
        .map_err(LuaError::external)?;

        loop {
            let p = pods.get(&pod).await.map_err(LuaError::external)?;
            if let Some(statuses) = &p.status.and_then(|s| s.ephemeral_container_statuses) {
                let ready = statuses.iter().any(|s| {
                    s.name == debug_name
                        && s.state.as_ref().and_then(|st| st.running.clone()).is_some()
                });
                if ready {
                    break;
                }
            }
            sleep(Duration::from_millis(250)).await;
        }

        let attached = pods
            .attach(
                &pod,
                &AttachParams::default()
                    .stdin(true)
                    .stdout(true)
                    .stderr(false)
                    .tty(true)
                    .container(debug_name.clone()),
            )
            .await
            .map_err(LuaError::external)?;

        Ok(Session::from_attached(attached))
    })
}

async fn await_status_or_timeout(mut proc: AttachedProcess) -> Result<AttachedProcess> {
    if let Some(fut) = proc.take_status() {
        match timeout(Duration::from_millis(200), fut).await {
            Ok(Some(status)) if status.status.as_deref() == Some("Failure") => {
                // convert k8s_openapi::Status -> kube::core::Status -> kube::Error::Api
                let kube_status = kube::core::Status::failure(
                    &status.message.clone().unwrap_or_else(|| "exec failed".into()),
                    &status.reason.clone().unwrap_or_default(),
                )
                .with_code(status.code.unwrap_or(400) as u16);
                Err(KubeError::Api(Box::new(kube_status)))
            }
            _ => Ok(proc),
        }
    } else {
        Ok(proc)
    }
}

pub struct Session {
    session: BidirectionalSession<Vec<u8>, Vec<u8>>,
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
        let mut proc = block_on(async {
            let p = open_exec(&client, &ns, &pod, &container, &cmd, tty).await?;
            await_status_or_timeout(p).await
        })
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
        let mut session = BidirectionalSession::new();

        spawn_io_tasks(rt, &mut proc, &mut session);

        Ok(Self { session })
    }

    pub fn from_attached(mut proc: AttachedProcess) -> Self {
        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
        let mut session = BidirectionalSession::new();

        spawn_io_tasks(rt, &mut proc, &mut session);

        Session { session }
    }

    fn read_chunk(&self) -> LuaResult<Option<String>> {
        match self.session.try_recv_output() {
            Ok(Some(bytes)) => Ok(Some(String::from_utf8_lossy(&bytes).into_owned())),
            Ok(None) => Ok(None),
            Err(e) => Err(LuaError::RuntimeError(e.to_string())),
        }
    }

    fn write(&self, s: &str) {
        let _ = self.session.send_input(s.as_bytes().to_vec());
    }

    fn is_open(&self) -> bool {
        self.session.is_open()
    }

    fn close(&self) {
        self.session.close();
    }
}

/// Spawn stdin writer and stdout reader tasks for an attached process.
fn spawn_io_tasks(
    rt: &Runtime,
    proc: &mut AttachedProcess,
    session: &mut BidirectionalSession<Vec<u8>, Vec<u8>>,
) {
    let task_handle = session.task_handle();

    // stdin writer task
    if let Some(mut stdin) = proc.stdin() {
        if let Some(mut input_receiver) = session.take_input_receiver() {
            let handle = task_handle.clone();
            let _guard = handle.guard();
            rt.spawn(async move {
                let _guard = _guard;
                while let Some(buf) = input_receiver.recv().await {
                    if stdin.write_all(&buf).await.is_err() {
                        break;
                    }
                }
            });
        }
    }

    // stdout reader task
    if let Some(mut stdout) = proc.stdout() {
        let output_sender = session.output_sender();
        let handle = task_handle.clone();
        let _guard = handle.guard();
        rt.spawn(async move {
            let _guard = _guard;
            let mut buf = [0u8; 4096];
            loop {
                match stdout.read(&mut buf).await {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if output_sender.send(buf[..n].to_vec()).is_err() {
                            break;
                        }
                    }
                }
            }
        });
    }
}

impl UserData for Session {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("read_chunk", |_, this, ()| this.read_chunk());
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
