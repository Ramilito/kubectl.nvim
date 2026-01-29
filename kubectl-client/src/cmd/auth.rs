use futures::stream::{self, StreamExt};
use k8s_openapi::api::authorization::v1::{
    ResourceAttributes, SelfSubjectAccessReview, SelfSubjectAccessReviewSpec,
};
use k8s_openapi::serde_json;
use mlua::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Semaphore;

#[derive(Deserialize, Debug)]
struct ResourceInfo {
    name: String,
    group: String,
    namespaced: bool,
}

#[derive(Deserialize, Debug)]
struct AuthArgs {
    namespace: Option<String>,
    resources: Vec<ResourceInfo>,
}

#[derive(Serialize, Debug, Clone)]
struct AuthRule {
    name: String,
    apigroup: String,
    get: bool,
    list: bool,
    watch: bool,
    create: bool,
    patch: bool,
    update: bool,
    delete: bool,
    deletecollection: bool,
}

impl AuthRule {
    fn new(name: String, apigroup: String) -> Self {
        Self {
            name,
            apigroup,
            get: false,
            list: false,
            watch: false,
            create: false,
            patch: false,
            update: false,
            delete: false,
            deletecollection: false,
        }
    }

    fn set_verb(&mut self, verb: &str, allowed: bool) {
        match verb {
            "get" => self.get = allowed,
            "list" => self.list = allowed,
            "watch" => self.watch = allowed,
            "create" => self.create = allowed,
            "patch" => self.patch = allowed,
            "update" => self.update = allowed,
            "delete" => self.delete = allowed,
            "deletecollection" => self.deletecollection = allowed,
            _ => {}
        }
    }
}

/// Check a single resource+verb combination using SelfSubjectAccessReview
async fn check_access(
    client: kube::Client,
    resource_name: String,
    api_group: String,
    verb: String,
    namespace: Option<String>,
) -> (String, String, String, bool) {
    let resource_attrs = ResourceAttributes {
        group: Some(api_group.clone()),
        resource: Some(resource_name.clone()),
        verb: Some(verb.clone()),
        namespace,
        ..Default::default()
    };

    let review = SelfSubjectAccessReview {
        metadata: Default::default(),
        spec: SelfSubjectAccessReviewSpec {
            resource_attributes: Some(resource_attrs),
            non_resource_attributes: None,
        },
        status: None,
    };

    let body = match serde_json::to_vec(&review) {
        Ok(b) => b,
        Err(_) => return (resource_name, api_group, verb, false),
    };

    let req = match http::Request::builder()
        .method("POST")
        .uri("/apis/authorization.k8s.io/v1/selfsubjectaccessreviews")
        .header("Content-Type", "application/json")
        .body(body)
    {
        Ok(r) => r,
        Err(_) => return (resource_name, api_group, verb, false),
    };

    let result: Result<SelfSubjectAccessReview, _> = client.request(req).await;

    let allowed = result
        .ok()
        .and_then(|r| r.status)
        .map(|s| s.allowed)
        .unwrap_or(false);

    (resource_name, api_group, verb, allowed)
}

#[tracing::instrument(skip(client, resources))]
async fn get_auth_rules_impl(
    client: kube::Client,
    namespace: Option<String>,
    resources: Vec<ResourceInfo>,
) -> LuaResult<String> {
    const VERBS: [&str; 8] = [
        "get",
        "list",
        "watch",
        "create",
        "patch",
        "update",
        "delete",
        "deletecollection",
    ];

    // Build list of (resource, verb) checks to perform
    let mut checks = Vec::new();
    for resource in &resources {
        for verb in VERBS {
            // For namespaced resources, include namespace; for cluster resources, don't
            let ns = if resource.namespaced {
                namespace.clone()
            } else {
                None
            };
            checks.push((
                client.clone(),
                resource.name.clone(),
                resource.group.clone(),
                verb.to_string(),
                ns,
            ));
        }
    }

    // Limit concurrency to 20 requests
    let semaphore = Arc::new(Semaphore::new(20));

    let results = stream::iter(checks)
        .map(|(client, resource_name, api_group, verb, ns)| {
            let sem = semaphore.clone();
            async move {
                let _permit = sem.acquire().await.expect("semaphore closed");
                check_access(client, resource_name, api_group, verb, ns).await
            }
        })
        .buffer_unordered(20)
        .collect::<Vec<_>>()
        .await;

    // Aggregate results into AuthRule structs
    let mut rules_map: HashMap<(String, String), AuthRule> = HashMap::new();

    for (resource_name, api_group, verb, allowed) in results {
        let key = (resource_name.clone(), api_group.clone());
        let entry = rules_map
            .entry(key)
            .or_insert_with(|| AuthRule::new(resource_name, api_group));
        entry.set_verb(&verb, allowed);
    }

    // Convert to sorted vector
    let mut rules: Vec<AuthRule> = rules_map.into_values().collect();
    rules.sort_by(|a, b| a.name.cmp(&b.name).then(a.apigroup.cmp(&b.apigroup)));

    // Serialize to JSON
    serde_json::to_string(&rules)
        .map_err(|e| mlua::Error::external(format!("serialize rules: {e}")))
}

#[tracing::instrument]
pub fn get_auth_rules(_lua: &Lua, json: String) -> LuaResult<String> {
    use crate::with_client;

    let args: AuthArgs = serde_json::from_str(&json)
        .map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;
    let namespace = args.namespace;
    let resources = args.resources;

    match with_client(|client| async move {
        get_auth_rules_impl(client, namespace, resources).await
    }) {
        Ok(json) => Ok(json),
        Err(e) => Ok(format!(
            r#"{{"error":"{}"}}"#,
            e.to_string().replace('"', "\\\"")
        )),
    }
}

