use k8s_openapi::api::authorization::v1::{
    ResourceRule, SelfSubjectRulesReview, SelfSubjectRulesReviewSpec,
};
use kube::api::PostParams;
use kube::Api;
use mlua::prelude::*;
use serde::{Deserialize, Serialize};

use crate::with_client;

#[derive(Deserialize)]
struct CanIArgs {
    namespace: Option<String>,
}

#[derive(Serialize)]
struct RuleRow {
    name: String,
    api_group: String,
    get: bool,
    list: bool,
    watch: bool,
    create: bool,
    patch: bool,
    update: bool,
    delete: bool,
    del_list: bool,
    extras: String,
}

fn has_verb(verbs: &[String], verb: &str) -> bool {
    verbs.iter().any(|v| v == "*" || v == verb)
}

fn extra_verbs(verbs: &[String]) -> String {
    let standard = ["get", "list", "watch", "create", "patch", "update", "delete", "deletecollection"];
    let extras: Vec<&String> = verbs
        .iter()
        .filter(|v| *v != "*" && !standard.contains(&v.as_str()))
        .collect();
    extras.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(",")
}

fn resource_rule_to_rows(rule: &ResourceRule) -> Vec<RuleRow> {
    let resources = rule.resources.clone().unwrap_or_default();
    let api_groups = rule.api_groups.clone().unwrap_or_default();
    let verbs = &rule.verbs;

    let res_list: Vec<&str> = if resources.is_empty() {
        vec!["*"]
    } else {
        resources.iter().map(|s| s.as_str()).collect()
    };

    let grp_list: Vec<&str> = if api_groups.is_empty() {
        vec![""]
    } else {
        api_groups.iter().map(|s| s.as_str()).collect()
    };

    let mut rows = Vec::new();
    for res in &res_list {
        for grp in &grp_list {
            rows.push(RuleRow {
                name: res.to_string(),
                api_group: grp.to_string(),
                get: has_verb(verbs, "get"),
                list: has_verb(verbs, "list"),
                watch: has_verb(verbs, "watch"),
                create: has_verb(verbs, "create"),
                patch: has_verb(verbs, "patch"),
                update: has_verb(verbs, "update"),
                delete: has_verb(verbs, "delete"),
                del_list: has_verb(verbs, "deletecollection"),
                extras: extra_verbs(verbs),
            });
        }
    }
    rows
}

#[tracing::instrument]
pub async fn get_self_subject_rules_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CanIArgs = k8s_openapi::serde_json::from_str(&json)
        .map_err(|e| LuaError::external(format!("bad json: {e}")))?;

    with_client(move |client| async move {
        let ns = args.namespace.unwrap_or_else(|| "default".to_string());

        let review = SelfSubjectRulesReview {
            metadata: Default::default(),
            spec: SelfSubjectRulesReviewSpec {
                namespace: Some(ns),
            },
            status: None,
        };

        let api: Api<SelfSubjectRulesReview> = Api::all(client.clone());
        let result = api
            .create(&PostParams::default(), &review)
            .await
            .map_err(|e| LuaError::external(format!("Failed to create SelfSubjectRulesReview: {e}")))?;

        let status = result.status.ok_or_else(|| {
            LuaError::external("SelfSubjectRulesReview returned no status")
        })?;

        let mut rows: Vec<RuleRow> = Vec::new();

        // Process resource rules
        for rule in status.resource_rules {
            rows.extend(resource_rule_to_rows(&rule));
        }

        // Process non-resource rules (show as special entries)
        for rule in status.non_resource_rules {
            let urls = rule.non_resource_urls.clone().unwrap_or_default();
            for url in urls {
                rows.push(RuleRow {
                    name: url,
                    api_group: "(non-resource)".to_string(),
                    get: has_verb(&rule.verbs, "get"),
                    list: has_verb(&rule.verbs, "list"),
                    watch: has_verb(&rule.verbs, "watch"),
                    create: has_verb(&rule.verbs, "create"),
                    patch: has_verb(&rule.verbs, "patch"),
                    update: has_verb(&rule.verbs, "update"),
                    delete: has_verb(&rule.verbs, "delete"),
                    del_list: has_verb(&rule.verbs, "deletecollection"),
                    extras: extra_verbs(&rule.verbs),
                });
            }
        }

        let json_str = k8s_openapi::serde_json::to_string(&rows)
            .map_err(|e| LuaError::RuntimeError(e.to_string()))?;

        Ok(json_str)
    })
}
