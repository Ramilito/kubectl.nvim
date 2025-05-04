use futures::{AsyncBufReadExt, TryStreamExt};
use k8s_openapi::api::core::v1::Pod;
use k8s_openapi::chrono::{Duration, Utc};
use k8s_openapi::serde_json;
use kube::api::LogParams;
use kube::Api;
use tokio::runtime::Runtime;

use crate::structs::CmdStreamArgs;
use crate::{CLIENT_INSTANCE, RUNTIME};

pub async fn log_stream_async(_lua: mlua::Lua, json: String) -> mlua::Result<String> {
    let args: CmdStreamArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let since_time = args
        .since_time_input
        .as_deref()
        .and_then(parse_duration)
        .map(|d| Utc::now() - d);

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE.lock().unwrap();
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let fut = async {
        let pods: Api<Pod> = Api::namespaced(client.clone(), &args.namespace);
        let pod = match pods.get(&args.name).await {
            Ok(pod) => pod,
            Err(e) => {
                return Ok(format!(
                    "No pod named {} in {} found: {}",
                    args.name, args.namespace, e
                ))
            }
        };

        let spec = pod
            .spec
            .ok_or_else(|| mlua::Error::external("No pod spec found"))?;

        let mut containers = spec.containers;
        if let Some(ref container) = args.container {
            containers.retain(|c| c.name == *container);
            if containers.is_empty() {
                return Ok(format!(
                    "No container named {} found in pod {}",
                    container, args.name
                ));
            }
        }
        if containers.is_empty() {
            return Err(mlua::Error::external("No containers in this Pod"));
        }

        let mut streams = Vec::new();
        for container in containers {
            let container_name = container.name;
            let lp = LogParams {
                follow: false,
                container: Some(container_name.clone()),
                since_time,
                pretty: true,
                timestamps: args.timestamps.unwrap_or_default(),
                previous: args.previous.unwrap_or_default(),
                ..LogParams::default()
            };

            let s = match pods.log_stream(&args.name, &lp).await {
                Ok(s) => s,
                Err(e) => {
                    return Ok(format!(
                        "No log stream for pod {} in {} found: {}",
                        args.name, args.namespace, e
                    ))
                }
            };

            let stream = s.lines().map_ok(move |line| {
                if args.prefix.unwrap_or_default() {
                    format!("[{}] {}", container_name, line)
                } else {
                    line.to_string()
                }
            });
            streams.push(stream);
        }

        let mut combined = futures::stream::select_all(streams);
        let mut collected_logs = String::new();

        while let Some(line) = combined.try_next().await? {
            collected_logs.push_str(&line);
            collected_logs.push('\n');
        }

        Ok(collected_logs)
    };

    rt.block_on(fut)
}

fn parse_duration(s: &str) -> Option<Duration> {
    if s == "0" || s.is_empty() {
        return None;
    }
    if s.len() < 2 {
        return None;
    }
    let (num_str, unit) = s.split_at(s.len() - 1);
    let num: i64 = num_str.parse().ok()?;
    match unit {
        "s" => Some(Duration::seconds(num)),
        "m" => Some(Duration::minutes(num)),
        "h" => Some(Duration::hours(num)),
        _ => None,
    }
}
