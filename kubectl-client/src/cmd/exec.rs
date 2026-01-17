use crate::streaming::BidirectionalSession;
use crate::RUNTIME;
use k8s_openapi::{
    api::core::v1::{EphemeralContainer, Pod},
    serde_json::{self, json},
};
use kube::{
    api::{Api, AttachParams, AttachedProcess, DeleteParams, Patch, PatchParams, PostParams},
    Client, Error as KubeError,
};
use mlua::{prelude::*, UserData, UserDataMethods};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    runtime::Runtime,
    time::{sleep, timeout},
};

type Result<T> = std::result::Result<T, KubeError>;

// ============================================================================
// Configuration Types
// ============================================================================

/// Node shell configuration passed from Lua
#[derive(Clone, Debug)]
pub struct NodeShellConfig {
    pub node: String,
    pub namespace: String,
    pub image: String,
    pub cpu_limit: Option<String>,
    pub mem_limit: Option<String>,
}

impl FromLua for NodeShellConfig {
    fn from_lua(value: LuaValue, _lua: &Lua) -> LuaResult<Self> {
        let table = value
            .as_table()
            .ok_or_else(|| LuaError::FromLuaConversionError {
                from: "value",
                to: "NodeShellConfig".into(),
                message: Some("expected table".into()),
            })?;
        Ok(NodeShellConfig {
            node: table.get("node")?,
            namespace: table
                .get::<Option<String>>("namespace")?
                .unwrap_or_else(|| "default".into()),
            image: table
                .get::<Option<String>>("image")?
                .unwrap_or_else(|| "busybox:latest".into()),
            cpu_limit: table.get("cpu_limit")?,
            mem_limit: table.get("mem_limit")?,
        })
    }
}

// ============================================================================
// Session Trait & Shared Behavior
// ============================================================================

/// Common operations for all interactive sessions
pub trait SessionOps {
    fn session(&self) -> &BidirectionalSession<Vec<u8>, Vec<u8>>;

    fn read_chunk(&self) -> LuaResult<Option<String>> {
        match self.session().try_recv_output() {
            Ok(Some(bytes)) => Ok(Some(String::from_utf8_lossy(&bytes).into_owned())),
            Ok(None) => Ok(None),
            Err(e) => Err(LuaError::RuntimeError(e.to_string())),
        }
    }

    fn write(&self, s: &str) {
        let _ = self.session().send_input(s.as_bytes().to_vec());
    }

    fn is_open(&self) -> bool {
        self.session().is_open()
    }

    fn close(&self) {
        self.session().close();
    }
}

/// Register standard session methods on a UserData type
macro_rules! impl_session_userdata {
    ($ty:ty) => {
        impl UserData for $ty {
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
    };
}

// ============================================================================
// Exec Session
// ============================================================================

/// Interactive exec session for running commands in a container
pub struct Session {
    inner: BidirectionalSession<Vec<u8>, Vec<u8>>,
}

impl SessionOps for Session {
    fn session(&self) -> &BidirectionalSession<Vec<u8>, Vec<u8>> {
        &self.inner
    }
}

impl_session_userdata!(Session);

impl Session {
    pub fn from_attached(mut proc: AttachedProcess) -> Self {
        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
        let mut inner = BidirectionalSession::new();
        spawn_io_tasks(rt, &mut proc, &mut inner);
        Session { inner }
    }
}

// ============================================================================
// Node Shell Session
// ============================================================================

/// Interactive session for node-level shell access.
/// Cleans up the debug pod when closed.
pub struct NodeShellSession {
    inner: BidirectionalSession<Vec<u8>, Vec<u8>>,
    client: Client,
    namespace: String,
    pod_name: String,
    cleaned_up: AtomicBool,
}

impl SessionOps for NodeShellSession {
    fn session(&self) -> &BidirectionalSession<Vec<u8>, Vec<u8>> {
        &self.inner
    }

    fn close(&self) {
        self.inner.close();
        self.cleanup_pod();
    }
}

impl_session_userdata!(NodeShellSession);

impl NodeShellSession {
    pub fn new(mut proc: AttachedProcess, client: Client, namespace: String, pod_name: String) -> Self {
        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
        let mut inner = BidirectionalSession::new();
        spawn_io_tasks(rt, &mut proc, &mut inner);

        NodeShellSession {
            inner,
            client,
            namespace,
            pod_name,
            cleaned_up: AtomicBool::new(false),
        }
    }

    fn cleanup_pod(&self) {
        // Only cleanup once
        if self.cleaned_up.swap(true, Ordering::SeqCst) {
            return;
        }

        let client = self.client.clone();
        let ns = self.namespace.clone();
        let pod_name = self.pod_name.clone();
        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
        rt.spawn(async move {
            let pods: Api<Pod> = Api::namespaced(client, &ns);
            let _ = pods.delete(&pod_name, &DeleteParams::default()).await;
        });
    }
}

// ============================================================================
// I/O Helpers
// ============================================================================

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
                    Ok(0) | Err(_) => {
                        handle.force_close();
                        break;
                    }
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

/// Wait briefly for exec status to detect immediate failures
pub async fn await_status_or_timeout(mut proc: AttachedProcess) -> Result<AttachedProcess> {
    let Some(fut) = proc.take_status() else {
        return Ok(proc);
    };

    match timeout(Duration::from_millis(200), fut).await {
        Ok(Some(status)) if status.status.as_deref() == Some("Failure") => {
            let kube_status = kube::core::Status::failure(
                &status
                    .message
                    .clone()
                    .unwrap_or_else(|| "exec failed".into()),
                &status.reason.clone().unwrap_or_default(),
            )
            .with_code(status.code.unwrap_or(400) as u16);
            Err(KubeError::Api(Box::new(kube_status)))
        }
        _ => Ok(proc),
    }
}

// ============================================================================
// Pod Builders
// ============================================================================

/// Build a privileged node shell pod spec
fn build_node_shell_pod(config: &NodeShellConfig, pod_name: &str) -> LuaResult<Pod> {
    let mut limits = serde_json::Map::new();
    if let Some(cpu) = &config.cpu_limit {
        limits.insert("cpu".into(), json!(cpu));
    }
    if let Some(mem) = &config.mem_limit {
        limits.insert("memory".into(), json!(mem));
    }

    serde_json::from_value(json!({
        "metadata": {
            "name": pod_name,
            "namespace": config.namespace,
            "labels": { "app": "kubectl-nvim-node-shell", "node": config.node }
        },
        "spec": {
            "nodeName": config.node,
            "hostPID": true,
            "hostNetwork": true,
            "hostIPC": true,
            "restartPolicy": "Never",
            "tolerations": [{ "operator": "Exists" }],
            "volumes": [{
                "name": "host-root",
                "hostPath": { "path": "/", "type": "Directory" }
            }],
            "containers": [{
                "name": "shell",
                "image": config.image,
                "stdin": true,
                "tty": true,
                "securityContext": { "privileged": true },
                "volumeMounts": [{ "name": "host-root", "mountPath": "/host" }],
                "command": ["sh"],
                "resources": if limits.is_empty() { json!(null) } else { json!({ "limits": limits }) }
            }]
        }
    }))
    .map_err(|e| LuaError::external(format!("failed to build pod spec: {e}")))
}

/// Wait for a pod to reach Running state
async fn wait_for_pod_running(pods: &Api<Pod>, pod_name: &str) -> LuaResult<()> {
    loop {
        let p = pods.get(pod_name).await.map_err(LuaError::external)?;
        match p.status.as_ref().and_then(|s| s.phase.as_deref()) {
            Some("Running") => return Ok(()),
            Some(phase @ ("Failed" | "Succeeded")) => {
                let _ = pods.delete(pod_name, &DeleteParams::default()).await;
                return Err(LuaError::RuntimeError(format!(
                    "Node shell pod entered {phase} state"
                )));
            }
            _ => sleep(Duration::from_millis(250)).await,
        }
    }
}

/// Wait for an ephemeral container to be running
async fn wait_for_ephemeral_container(
    pods: &Api<Pod>,
    pod_name: &str,
    container_name: &str,
) -> LuaResult<()> {
    loop {
        let p = pods.get(pod_name).await.map_err(LuaError::external)?;
        if let Some(statuses) = p.status.and_then(|s| s.ephemeral_container_statuses) {
            let ready = statuses.iter().any(|s| {
                s.name == container_name
                    && s.state.as_ref().and_then(|st| st.running.clone()).is_some()
            });
            if ready {
                return Ok(());
            }
        }
        sleep(Duration::from_millis(250)).await;
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Execute a command in a container and return an attached process
#[tracing::instrument(skip(client))]
pub async fn open_exec(
    client: &Client,
    ns: &str,
    pod: &str,
    container: &Option<String>,
    cmd: &[String],
    tty: bool,
) -> Result<AttachedProcess> {
    let pods: Api<Pod> = Api::namespaced(client.clone(), ns);
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

/// Create an ephemeral debug container in a pod and return an attached process
#[tracing::instrument(skip(client))]
pub async fn open_debug(
    client: &Client,
    ns: &str,
    pod: &str,
    image: &str,
    target: Option<&str>,
) -> LuaResult<AttachedProcess> {
    let debug_name = format!("debug-{}", uuid::Uuid::new_v4().simple());

    let mut ectr = EphemeralContainer {
        name: debug_name.clone(),
        image: Some(image.to_owned()),
        stdin: Some(true),
        tty: Some(true),
        ..Default::default()
    };
    if let Some(t) = target {
        ectr.target_container_name = Some(t.to_owned());
    }

    let patch: Pod =
        serde_json::from_value(json!({ "spec": { "ephemeralContainers": [ ectr ] }}))
            .map_err(|e| LuaError::external(format!("failed to build debug patch: {e}")))?;

    let pods: Api<Pod> = Api::namespaced(client.clone(), ns);

    pods.patch_ephemeral_containers(
        pod,
        &PatchParams::apply("kubectl-client-debug"),
        &Patch::Strategic(patch),
    )
    .await
    .map_err(LuaError::external)?;

    wait_for_ephemeral_container(&pods, pod, &debug_name).await?;

    pods.attach(
        pod,
        &AttachParams::default()
            .stdin(true)
            .stdout(true)
            .stderr(false)
            .tty(true)
            .container(debug_name),
    )
    .await
    .map_err(LuaError::external)
}

/// Create a privileged debug pod on a node and attach for shell access.
/// Similar to `kubectl debug node/<name>` - uses host namespaces with root filesystem at /host.
/// Returns the attached process and pod name (for cleanup).
#[tracing::instrument(skip(client))]
pub async fn open_node_shell(
    client: &Client,
    config: &NodeShellConfig,
) -> LuaResult<(AttachedProcess, String)> {
    let pod_name = format!("node-shell-{}", uuid::Uuid::new_v4().simple());
    let pod = build_node_shell_pod(config, &pod_name)?;

    let pods: Api<Pod> = Api::namespaced(client.clone(), &config.namespace);

    pods.create(&PostParams::default(), &pod)
        .await
        .map_err(LuaError::external)?;

    wait_for_pod_running(&pods, &pod_name).await?;

    let attached = pods
        .attach(
            &pod_name,
            &AttachParams::default()
                .stdin(true)
                .stdout(true)
                .stderr(false)
                .tty(true)
                .container("shell"),
        )
        .await
        .map_err(LuaError::external)?;

    Ok((attached, pod_name))
}
