use k8s_openapi::{
    api::batch::v1::{CronJob, Job},
    apimachinery::pkg::apis::meta::v1::{ObjectMeta, OwnerReference}, serde_json::json,
};
use kube::{
    api::{Api, Patch, PatchParams, PostParams},
    Resource, ResourceExt,
};
use mlua::{Error as LuaError, Lua, Result as LuaResult};
use tracing::info;
use std::collections::BTreeMap;
use tokio::runtime::Runtime;

use crate::{CLIENT_INSTANCE, RUNTIME};

pub fn create_job_from_cronjob(
    _lua: &Lua,
    args: (String, String, String, bool),
) -> LuaResult<String> {
    let (job_name, namespace, cronjob_name, dry_run) = args;

    info!("{:?}", dry_run);
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
        .clone();

    rt.block_on(async move {
        let cj_api: Api<CronJob> = Api::namespaced(client.clone(), &namespace);
        let cronjob = cj_api.get(&cronjob_name).await.unwrap();

        let mut annotations: BTreeMap<String, String> = cronjob
            .spec
            .as_ref()
            .and_then(|s| s.job_template.metadata.as_ref())
            .and_then(|m| m.annotations.clone())
            .unwrap_or_default();
        annotations.insert("cronjob.kubernetes.io/instantiate".into(), "manual".into());

        let owner_ref = OwnerReference {
            api_version: CronJob::api_version(&()).to_string(),
            kind: CronJob::kind(&()).to_string(),
            name: cronjob.name_any(),
            uid: cronjob
                .meta()
                .uid
                .clone()
                .expect("server never returns CronJob without UID"),
            controller: Some(true),
            block_owner_deletion: None, // ← keep it `None` so no extra finalizer RBAC is needed
        };

        let cj_job_spec = cronjob
            .spec
            .as_ref()
            .and_then(|s| s.job_template.spec.clone())
            .expect("CronJob without JobTemplate spec");

        let job = Job {
            metadata: ObjectMeta {
                name: Some(job_name.clone()),
                namespace: Some(namespace.clone()),
                annotations: Some(annotations),
                labels: cronjob
                    .spec
                    .as_ref()
                    .and_then(|s| s.job_template.metadata.as_ref())
                    .and_then(|m| m.labels.clone()),
                owner_references: Some(vec![owner_ref]),
                ..Default::default()
            },
            spec: Some(cj_job_spec),
            ..Default::default()
        };

        let jobs_api: Api<Job> = Api::namespaced(client.clone(), &namespace);
        let pp = PostParams {
            dry_run,
            ..Default::default()
        };
        info!("{:?}", pp);
        jobs_api
            .create(&pp, &job)
            .await
            .map(|_| format!("Job '{job_name}' created from CronJob '{cronjob_name}'"))
            .map_err(|e| LuaError::RuntimeError(format!("failed to create Job: {e:?}")))
    })
}

pub fn suspend_cronjob(_lua: &Lua, args: (String, String, bool)) -> LuaResult<String> {
    let (cronjob_name, namespace, suspend) = args;

    let rt = RUNTIME
        .get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
        .clone();

    rt.block_on(async move {
        let cj_api: Api<CronJob> = Api::namespaced(client, &namespace);

        let patch = json!({ "spec": { "suspend": suspend } });
        let pp = PatchParams::default();

        match cj_api.patch(&cronjob_name, &pp, &Patch::Merge(&patch)).await {
            Ok(_) => Ok(format!(
                "CronJob '{cronjob_name}' is now {}",
                if suspend { "SUSPENDED" } else { "RESUMED" }
            )),
            Err(e) => Err(LuaError::RuntimeError(format!(
                "failed to update CronJob: {e:?}"
            ))),
        }
    })
}
