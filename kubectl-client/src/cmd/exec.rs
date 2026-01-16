use crate::streaming::BidirectionalSession;
use crate::{block_on, RUNTIME};
use k8s_openapi::{
    api::core::v1::{
        Container, EphemeralContainer, HostPathVolumeSource, Pod, PodSpec, ResourceRequirements,
        SecurityContext, Toleration, Volume, VolumeMount,
    },
    apimachinery::pkg::api::resource::Quantity,
    serde_json::{self, json},
};
use kube::{
    api::{Api, AttachParams, AttachedProcess, DeleteParams, ObjectMeta, Patch, PatchParams, PostParams},
    Client, Error as KubeError,
};
use std::collections::BTreeMap;
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
            namespace: table.get::<Option<String>>("namespace")?.unwrap_or_else(|| "default".into()),
            image: table.get::<Option<String>>("image")?.unwrap_or_else(|| "busybox:latest".into()),
            cpu_limit: table.get("cpu_limit")?,
            mem_limit: table.get("mem_limit")?,
        })
    }
}

/// Creates a privileged debug pod on a node and attaches to it for shell access.
/// The pod runs with host namespaces (PID, network, IPC) and uses nsenter to
/// access the node's filesystem, similar to `kubectl debug node/<name>`.
#[tracing::instrument(skip(client))]
pub fn node_shell(client: Client, config: NodeShellConfig) -> LuaResult<NodeShellSession> {
    let pod_name = format!("node-shell-{}", uuid::Uuid::new_v4().simple());
    let ns = &config.namespace;

    // Build resource limits if specified
    let limits = {
        let mut map = BTreeMap::new();
        if let Some(cpu) = &config.cpu_limit {
            map.insert("cpu".to_string(), Quantity(cpu.clone()));
        }
        if let Some(mem) = &config.mem_limit {
            map.insert("memory".to_string(), Quantity(mem.clone()));
        }
        if map.is_empty() {
            None
        } else {
            Some(map)
        }
    };

    // Create the debug pod spec with host namespaces and privileged access
    // Mount host root filesystem to /host and use chroot for shell access
    let pod = Pod {
        metadata: ObjectMeta {
            name: Some(pod_name.clone()),
            namespace: Some(ns.clone()),
            labels: Some(BTreeMap::from([
                ("app".to_string(), "kubectl-nvim-node-shell".to_string()),
                ("node".to_string(), config.node.clone()),
            ])),
            ..Default::default()
        },
        spec: Some(PodSpec {
            node_name: Some(config.node.clone()),
            host_pid: Some(true),
            host_network: Some(true),
            host_ipc: Some(true),
            restart_policy: Some("Never".to_string()),
            // Tolerate all taints to ensure we can schedule on any node
            tolerations: Some(vec![Toleration {
                operator: Some("Exists".to_string()),
                ..Default::default()
            }]),
            // Mount the host's root filesystem
            volumes: Some(vec![Volume {
                name: "host-root".to_string(),
                host_path: Some(HostPathVolumeSource {
                    path: "/".to_string(),
                    type_: Some("Directory".to_string()),
                }),
                ..Default::default()
            }]),
            containers: vec![Container {
                name: "shell".to_string(),
                image: Some(config.image.clone()),
                stdin: Some(true),
                tty: Some(true),
                security_context: Some(SecurityContext {
                    privileged: Some(true),
                    ..Default::default()
                }),
                volume_mounts: Some(vec![VolumeMount {
                    name: "host-root".to_string(),
                    mount_path: "/host".to_string(),
                    ..Default::default()
                }]),
                // Drop into shell - host filesystem is available at /host
                command: Some(vec!["sh".to_string()]),
                resources: limits.map(|l| ResourceRequirements {
                    limits: Some(l),
                    ..Default::default()
                }),
                ..Default::default()
            }],
            ..Default::default()
        }),
        ..Default::default()
    };

    block_on(async {
        let pods: Api<Pod> = Api::namespaced(client.clone(), ns);

        // Create the pod
        pods.create(&PostParams::default(), &pod)
            .await
            .map_err(LuaError::external)?;

        // Wait for the pod to be running
        loop {
            let p = pods.get(&pod_name).await.map_err(LuaError::external)?;
            if let Some(status) = &p.status {
                if let Some(phase) = &status.phase {
                    match phase.as_str() {
                        "Running" => break,
                        "Failed" | "Succeeded" => {
                            // Extract failure reason from container status
                            let reason = status
                                .container_statuses
                                .as_ref()
                                .and_then(|statuses| statuses.first())
                                .and_then(|cs| cs.state.as_ref())
                                .and_then(|state| {
                                    state.terminated.as_ref().map(|t| {
                                        format!(
                                            "reason={}, message={}, exit_code={}",
                                            t.reason.as_deref().unwrap_or("unknown"),
                                            t.message.as_deref().unwrap_or("none"),
                                            t.exit_code
                                        )
                                    })
                                })
                                .unwrap_or_else(|| "unknown".to_string());

                            // Clean up the pod on failure
                            let _ = pods.delete(&pod_name, &DeleteParams::default()).await;
                            return Err(LuaError::RuntimeError(format!(
                                "Node shell pod entered {} state ({})",
                                phase, reason
                            )));
                        }
                        _ => {}
                    }
                }
            }
            sleep(Duration::from_millis(250)).await;
        }

        // Attach to the pod
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

        Ok(NodeShellSession::new(attached, client, ns.clone(), pod_name))
    })
}

/// A session that cleans up the debug pod when closed
pub struct NodeShellSession {
    session: BidirectionalSession<Vec<u8>, Vec<u8>>,
    client: Client,
    namespace: String,
    pod_name: String,
}

impl NodeShellSession {
    fn new(mut proc: AttachedProcess, client: Client, namespace: String, pod_name: String) -> Self {
        let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
        let mut session = BidirectionalSession::new();

        spawn_io_tasks(rt, &mut proc, &mut session);

        NodeShellSession {
            session,
            client,
            namespace,
            pod_name,
        }
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
        // Clean up the debug pod
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

impl UserData for NodeShellSession {
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
                    Ok(0) | Err(_) => {
                        // Process exited - force close session immediately
                        // so is_open() returns false without waiting for stdin task
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
