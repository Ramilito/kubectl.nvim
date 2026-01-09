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
    resources: String,
    api_groups: String,
    verbs: String,
    resource_names: String,
    non_resource_urls: String,
}

fn format_vec(v: &[String]) -> String {
    if v.is_empty() {
        "*".to_string()
    } else if v.len() == 1 && v[0] == "*" {
        "*".to_string()
    } else {
        v.join(",")
    }
}

fn resource_rule_to_row(rule: &ResourceRule) -> RuleRow {
    RuleRow {
        resources: format_vec(&rule.resources.clone().unwrap_or_default()),
        api_groups: format_vec(&rule.api_groups.clone().unwrap_or_default()),
        verbs: format_vec(&rule.verbs),
        resource_names: format_vec(&rule.resource_names.clone().unwrap_or_default()),
        non_resource_urls: String::new(),
    }
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
            rows.push(resource_rule_to_row(&rule));
        }

        // Process non-resource rules
        for rule in status.non_resource_rules {
            rows.push(RuleRow {
                resources: String::new(),
                api_groups: String::new(),
                verbs: format_vec(&rule.verbs),
                resource_names: String::new(),
                non_resource_urls: format_vec(&rule.non_resource_urls.clone().unwrap_or_default()),
            });
        }

        let json_str = k8s_openapi::serde_json::to_string(&rows)
            .map_err(|e| LuaError::RuntimeError(e.to_string()))?;

        Ok(json_str)
    })
}
