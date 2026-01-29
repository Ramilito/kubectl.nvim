use k8s_openapi::api::authorization::v1::{
    SelfSubjectRulesReview, SelfSubjectRulesReviewSpec,
};
use k8s_openapi::serde_json;
use mlua::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Deserialize, Debug)]
struct AuthArgs {
    namespace: Option<String>,
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

    fn add_verb(&mut self, verb: &str) {
        match verb {
            "get" => self.get = true,
            "list" => self.list = true,
            "watch" => self.watch = true,
            "create" => self.create = true,
            "patch" => self.patch = true,
            "update" => self.update = true,
            "delete" => self.delete = true,
            "deletecollection" => self.deletecollection = true,
            "*" => {
                // Wildcard means all verbs allowed
                self.get = true;
                self.list = true;
                self.watch = true;
                self.create = true;
                self.patch = true;
                self.update = true;
                self.delete = true;
                self.deletecollection = true;
            }
            _ => {}
        }
    }
}

async fn get_auth_rules_impl(client: kube::Client, namespace: String) -> LuaResult<String> {
    let review = SelfSubjectRulesReview {
        metadata: Default::default(),
        spec: SelfSubjectRulesReviewSpec {
            namespace: Some(namespace),
        },
        status: None,
    };

    // Use raw HTTP POST since SelfSubjectRulesReview is a create-only subresource
    let body = serde_json::to_vec(&review)
        .map_err(|e| mlua::Error::external(format!("serialize review: {e}")))?;
    let req = http::Request::builder()
        .method("POST")
        .uri("/apis/authorization.k8s.io/v1/selfsubjectrulesreviews")
        .header("Content-Type", "application/json")
        .body(body)
        .map_err(|e| mlua::Error::external(format!("build request: {e}")))?;

    let result: SelfSubjectRulesReview = client
        .request(req)
        .await
        .map_err(|e| mlua::Error::external(format!("auth rules request: {e}")))?;

    // Extract resource rules from the response
    let resource_rules = result
        .status
        .map(|s| s.resource_rules)
        .unwrap_or_default();

    // Aggregate by (resource, apiGroup) pair
    let mut rules_map: HashMap<(String, String), AuthRule> = HashMap::new();

    for rule in resource_rules {
        let verbs = rule.verbs;
        let api_groups = rule.api_groups.unwrap_or_default();
        let resources = rule.resources.unwrap_or_default();

        // Handle wildcard resources
        let resource_names: Vec<String> = if resources.contains(&"*".to_string()) {
            vec!["*".to_string()]
        } else {
            resources
        };

        // Handle wildcard api groups
        let api_group_names: Vec<String> = if api_groups.contains(&"*".to_string()) {
            vec!["*".to_string()]
        } else {
            api_groups
        };

        for resource in &resource_names {
            for api_group in &api_group_names {
                let key: (String, String) = (resource.clone(), api_group.clone());
                let entry = rules_map
                    .entry(key.clone())
                    .or_insert_with(|| AuthRule::new(resource.clone(), api_group.clone()));

                for verb in &verbs {
                    entry.add_verb(verb);
                }
            }
        }
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
    let namespace = args.namespace.unwrap_or_else(|| "default".to_string());

    match with_client(|client| async move { get_auth_rules_impl(client, namespace).await }) {
        Ok(json) => Ok(json),
        Err(e) => Ok(format!(
            r#"{{"error":"{}"}}"#,
            e.to_string().replace('"', "\\\"")
        )),
    }
}

