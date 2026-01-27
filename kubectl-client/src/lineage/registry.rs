//! Resource handler registry for extracting relationships.
//!
//! This module provides a centralized registry of resource-specific handlers that know how to:
//! - Extract relationship references (ConfigMaps, Secrets, Services, etc.)
//! - Extract ownership relationships (via ownerReferences)
//! - Define orphan detection rules
//!
//! The registry pattern eliminates scattered resource-specific logic and makes the codebase
//! more maintainable by centralizing all resource-specific behavior in one place.

use super::orphan_rules::OrphanRule;
use super::resource_behavior::extract_pod_spec_relations;
use super::tree::RelationRef;
use k8s_openapi::api::{
    admissionregistration::v1::{MutatingWebhookConfiguration, ValidatingWebhookConfiguration},
    apps::v1::{DaemonSet, Deployment, ReplicaSet, StatefulSet},
    autoscaling::v2::HorizontalPodAutoscaler,
    batch::v1::{CronJob, Job},
    core::v1::{Event, ObjectReference, PersistentVolume, PersistentVolumeClaim, Pod, ServiceAccount},
    networking::v1::{Ingress, IngressClass},
    rbac::v1::{ClusterRoleBinding, RoleBinding},
};
use k8s_openapi::kube_aggregator::pkg::apis::apiregistration::v1::APIService;
use k8s_openapi::serde_json::Value;
use serde::de::DeserializeOwned;
use std::collections::HashMap;
use std::sync::OnceLock;

/// Handler for a specific Kubernetes resource kind
pub(crate) struct ResourceHandler {
    /// Resource kind (e.g., "Pod", "ConfigMap", "Deployment")
    /// Note: This field duplicates the hash map key but is kept for debugging and documentation
    #[allow(dead_code)]
    pub kind: &'static str,
    /// Function to extract relationships from resource JSON
    pub extract_relations: fn(&Value, Option<&str>) -> Vec<RelationRef>,
    /// Optional orphan detection rule
    pub orphan_rule: Option<&'static OrphanRule>,
}

/// Global registry of resource handlers
static RESOURCE_REGISTRY: OnceLock<HashMap<&'static str, ResourceHandler>> = OnceLock::new();

/// Normalize a resource kind to title case for case-insensitive lookup
/// Examples: "configmap" -> "ConfigMap", "persistentvolumeclaim" -> "PersistentVolumeClaim"
fn normalize_kind(kind: &str) -> String {
    // Common mappings for case-insensitive lookup
    match kind.to_lowercase().as_str() {
        "configmap" => "ConfigMap".to_string(),
        "secret" => "Secret".to_string(),
        "service" => "Service".to_string(),
        "serviceaccount" => "ServiceAccount".to_string(),
        "persistentvolumeclaim" => "PersistentVolumeClaim".to_string(),
        "persistentvolume" => "PersistentVolume".to_string(),
        "storageclass" => "StorageClass".to_string(),
        "role" => "Role".to_string(),
        "rolebinding" => "RoleBinding".to_string(),
        "clusterrole" => "ClusterRole".to_string(),
        "clusterrolebinding" => "ClusterRoleBinding".to_string(),
        "networkpolicy" => "NetworkPolicy".to_string(),
        "poddisruptionbudget" => "PodDisruptionBudget".to_string(),
        "ingressclass" => "IngressClass".to_string(),
        "ingress" => "Ingress".to_string(),
        "horizontalpodautoscaler" => "HorizontalPodAutoscaler".to_string(),
        "replicaset" => "ReplicaSet".to_string(),
        "pod" => "Pod".to_string(),
        "deployment" => "Deployment".to_string(),
        "statefulset" => "StatefulSet".to_string(),
        "daemonset" => "DaemonSet".to_string(),
        "job" => "Job".to_string(),
        "cronjob" => "CronJob".to_string(),
        "event" => "Event".to_string(),
        "node" => "Node".to_string(),
        "namespace" => "Namespace".to_string(),
        "endpointslice" => "EndpointSlice".to_string(),
        "validatingwebhookconfiguration" => "ValidatingWebhookConfiguration".to_string(),
        "mutatingwebhookconfiguration" => "MutatingWebhookConfiguration".to_string(),
        "apiservice" => "APIService".to_string(),
        // If not in the map, try title case (first char uppercase, rest lowercase per word)
        _ => kind.to_string(),
    }
}

/// Get the handler for a specific resource kind (case-insensitive)
pub(crate) fn get_handler(kind: &str) -> Option<&'static ResourceHandler> {
    let normalized = normalize_kind(kind);
    RESOURCE_REGISTRY
        .get_or_init(|| {
            let mut registry = HashMap::new();

            // Workload resources
            registry.insert("Pod", ResourceHandler {
                kind: "Pod",
                extract_relations: extract_pod_relations,
                orphan_rule: None,
            });
            registry.insert("Deployment", ResourceHandler {
                kind: "Deployment",
                extract_relations: extract_deployment_relations,
                orphan_rule: None,
            });
            registry.insert("ReplicaSet", ResourceHandler {
                kind: "ReplicaSet",
                extract_relations: extract_replicaset_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("ReplicaSet"),
            });
            registry.insert("StatefulSet", ResourceHandler {
                kind: "StatefulSet",
                extract_relations: extract_statefulset_relations,
                orphan_rule: None,
            });
            registry.insert("DaemonSet", ResourceHandler {
                kind: "DaemonSet",
                extract_relations: extract_daemonset_relations,
                orphan_rule: None,
            });
            registry.insert("Job", ResourceHandler {
                kind: "Job",
                extract_relations: extract_job_relations,
                orphan_rule: None,
            });
            registry.insert("CronJob", ResourceHandler {
                kind: "CronJob",
                extract_relations: extract_cronjob_relations,
                orphan_rule: None,
            });

            // Network resources
            registry.insert("Service", ResourceHandler {
                kind: "Service",
                extract_relations: empty_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("Service"),
            });
            registry.insert("Ingress", ResourceHandler {
                kind: "Ingress",
                extract_relations: extract_ingress_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("Ingress"),
            });
            registry.insert("IngressClass", ResourceHandler {
                kind: "IngressClass",
                extract_relations: extract_ingressclass_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("IngressClass"),
            });
            registry.insert("NetworkPolicy", ResourceHandler {
                kind: "NetworkPolicy",
                extract_relations: empty_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("NetworkPolicy"),
            });
            registry.insert("EndpointSlice", ResourceHandler {
                kind: "EndpointSlice",
                extract_relations: empty_relations,
                orphan_rule: None,
            });

            // Config and storage resources
            registry.insert("ConfigMap", ResourceHandler {
                kind: "ConfigMap",
                extract_relations: empty_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("ConfigMap"),
            });
            registry.insert("Secret", ResourceHandler {
                kind: "Secret",
                extract_relations: empty_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("Secret"),
            });
            registry.insert("PersistentVolumeClaim", ResourceHandler {
                kind: "PersistentVolumeClaim",
                extract_relations: extract_pvc_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("PersistentVolumeClaim"),
            });
            registry.insert("PersistentVolume", ResourceHandler {
                kind: "PersistentVolume",
                extract_relations: extract_pv_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("PersistentVolume"),
            });
            registry.insert("StorageClass", ResourceHandler {
                kind: "StorageClass",
                extract_relations: empty_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("StorageClass"),
            });

            // RBAC resources
            registry.insert("ServiceAccount", ResourceHandler {
                kind: "ServiceAccount",
                extract_relations: extract_serviceaccount_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("ServiceAccount"),
            });
            registry.insert("Role", ResourceHandler {
                kind: "Role",
                extract_relations: empty_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("Role"),
            });
            registry.insert("RoleBinding", ResourceHandler {
                kind: "RoleBinding",
                extract_relations: extract_rolebinding_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("RoleBinding"),
            });
            registry.insert("ClusterRole", ResourceHandler {
                kind: "ClusterRole",
                extract_relations: empty_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("ClusterRole"),
            });
            registry.insert("ClusterRoleBinding", ResourceHandler {
                kind: "ClusterRoleBinding",
                extract_relations: extract_clusterrolebinding_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("ClusterRoleBinding"),
            });

            // Webhook and API resources
            registry.insert("ValidatingWebhookConfiguration", ResourceHandler {
                kind: "ValidatingWebhookConfiguration",
                extract_relations: extract_validatingwebhook_relations,
                orphan_rule: None,
            });
            registry.insert("MutatingWebhookConfiguration", ResourceHandler {
                kind: "MutatingWebhookConfiguration",
                extract_relations: extract_mutatingwebhook_relations,
                orphan_rule: None,
            });
            registry.insert("APIService", ResourceHandler {
                kind: "APIService",
                extract_relations: extract_apiservice_relations,
                orphan_rule: None,
            });

            // Other resources
            registry.insert("HorizontalPodAutoscaler", ResourceHandler {
                kind: "HorizontalPodAutoscaler",
                extract_relations: extract_hpa_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("HorizontalPodAutoscaler"),
            });
            registry.insert("PodDisruptionBudget", ResourceHandler {
                kind: "PodDisruptionBudget",
                extract_relations: empty_relations,
                orphan_rule: super::orphan_rules::get_orphan_rule("PodDisruptionBudget"),
            });
            registry.insert("Namespace", ResourceHandler {
                kind: "Namespace",
                extract_relations: empty_relations,
                orphan_rule: None,
            });
            registry.insert("Node", ResourceHandler {
                kind: "Node",
                extract_relations: empty_relations,
                orphan_rule: None,
            });
            registry.insert("Event", ResourceHandler {
                kind: "Event",
                extract_relations: extract_event_relations,
                orphan_rule: None,
            });

            registry
        })
        .get(normalized.as_str())
}

// Helper to deserialize and extract
fn deserialize_and_extract<T: DeserializeOwned>(
    item: &Value,
    extractor: impl FnOnce(&T) -> Vec<RelationRef>,
) -> Vec<RelationRef> {
    match k8s_openapi::serde_json::from_value::<T>(item.clone()) {
        Ok(resource) => extractor(&resource),
        Err(_) => Vec::new(),
    }
}

// Shared function for resources with no outgoing relationships
fn empty_relations(_item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    Vec::new()
}

// Helper to convert ObjectReference to RelationRef
fn object_ref_to_relation(obj_ref: &ObjectReference) -> Option<RelationRef> {
    let kind = obj_ref.kind.as_ref()?;
    let name = obj_ref.name.as_ref()?;

    Some(RelationRef {
        kind: kind.clone(),
        name: name.clone(),
        namespace: obj_ref.namespace.clone(),
        api_version: obj_ref.api_version.clone(),
        uid: obj_ref.uid.clone(),
    })
}

// Resource-specific extraction functions

fn extract_pod_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<Pod>(item, |pod| {
        let mut relations = Vec::new();

        let spec = match &pod.spec {
            Some(s) => s,
            None => return relations,
        };

        // Pod-specific relationships
        if let Some(node_name) = &spec.node_name {
            relations.push(RelationRef::new("Node", node_name.clone()));
        }

        if let Some(priority_class) = &spec.priority_class_name {
            relations.push(RelationRef::new("PriorityClass", priority_class.clone()));
        }

        if let Some(runtime_class) = &spec.runtime_class_name {
            relations.push(RelationRef::new("RuntimeClass", runtime_class.clone()));
        }

        // PodSpec relationships
        relations.extend(extract_pod_spec_relations(spec, pod.metadata.namespace.as_deref()));

        relations
    })
}

fn extract_deployment_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<Deployment>(item, |deployment| {
        let namespace = deployment.metadata.namespace.as_deref();
        let spec = match &deployment.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let pod_spec = match &spec.template.spec {
            Some(ps) => ps,
            None => return Vec::new(),
        };

        extract_pod_spec_relations(pod_spec, namespace)
    })
}

fn extract_replicaset_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<ReplicaSet>(item, |rs| {
        let namespace = rs.metadata.namespace.as_deref();
        let spec = match &rs.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let template = match &spec.template {
            Some(t) => t,
            None => return Vec::new(),
        };

        let pod_spec = match &template.spec {
            Some(ps) => ps,
            None => return Vec::new(),
        };

        extract_pod_spec_relations(pod_spec, namespace)
    })
}

fn extract_statefulset_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<StatefulSet>(item, |sts| {
        let mut relations = Vec::new();
        let namespace = sts.metadata.namespace.as_deref();

        let spec = match &sts.spec {
            Some(s) => s,
            None => return relations,
        };

        // volumeClaimTemplates
        if let Some(templates) = &spec.volume_claim_templates {
            for template in templates {
                if let Some(name) = &template.metadata.name {
                    relations.push(RelationRef::new("PersistentVolumeClaim", name.clone()).ns(namespace));
                }
            }
        }

        // serviceName
        if let Some(service_name) = &spec.service_name {
            relations.push(RelationRef::new("Service", service_name.clone()).ns(namespace));
        }

        // PodSpec relationships
        if let Some(pod_spec) = &spec.template.spec {
            relations.extend(extract_pod_spec_relations(pod_spec, namespace));
        }

        relations
    })
}

fn extract_daemonset_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<DaemonSet>(item, |ds| {
        let namespace = ds.metadata.namespace.as_deref();
        let spec = match &ds.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let pod_spec = match &spec.template.spec {
            Some(ps) => ps,
            None => return Vec::new(),
        };

        extract_pod_spec_relations(pod_spec, namespace)
    })
}

fn extract_job_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<Job>(item, |job| {
        let namespace = job.metadata.namespace.as_deref();
        let spec = match &job.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let pod_spec = match &spec.template.spec {
            Some(ps) => ps,
            None => return Vec::new(),
        };

        extract_pod_spec_relations(pod_spec, namespace)
    })
}

fn extract_cronjob_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<CronJob>(item, |cronjob| {
        let namespace = cronjob.metadata.namespace.as_deref();
        let spec = match &cronjob.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let job_spec = match &spec.job_template.spec {
            Some(js) => js,
            None => return Vec::new(),
        };

        let pod_spec = match &job_spec.template.spec {
            Some(ps) => ps,
            None => return Vec::new(),
        };

        extract_pod_spec_relations(pod_spec, namespace)
    })
}

fn extract_ingress_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<Ingress>(item, |ingress| {
        let mut relations = Vec::new();
        let namespace = ingress.metadata.namespace.as_deref();

        let spec = match &ingress.spec {
            Some(s) => s,
            None => return relations,
        };

        // ingressClassName
        if let Some(class_name) = &spec.ingress_class_name {
            relations.push(RelationRef::new("IngressClass", class_name.clone()));
        }

        // default backend
        if let Some(backend) = &spec.default_backend {
            if let Some(service) = &backend.service {
                relations.push(RelationRef::new("Service", service.name.clone()).ns(namespace));
            }
            if let Some(resource) = &backend.resource {
                relations.push(
                    RelationRef::new(resource.kind.clone(), resource.name.clone())
                        .ns(namespace)
                        .api(resource.api_group.as_ref()),
                );
            }
        }

        // rules
        if let Some(rules) = &spec.rules {
            for rule in rules {
                if let Some(http) = &rule.http {
                    for path in &http.paths {
                        if let Some(service) = &path.backend.service {
                            relations.push(RelationRef::new("Service", service.name.clone()).ns(namespace));
                        }
                        if let Some(resource) = &path.backend.resource {
                            relations.push(
                                RelationRef::new(resource.kind.clone(), resource.name.clone())
                                    .ns(namespace)
                                    .api(resource.api_group.as_ref()),
                            );
                        }
                    }
                }
            }
        }

        // tls secrets
        if let Some(tls_list) = &spec.tls {
            for tls in tls_list {
                if let Some(secret_name) = &tls.secret_name {
                    relations.push(RelationRef::new("Secret", secret_name.clone()).ns(namespace));
                }
            }
        }

        relations
    })
}

fn extract_ingressclass_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<IngressClass>(item, |ingress_class| {
        let mut relations = Vec::new();

        if let Some(spec) = &ingress_class.spec {
            if let Some(parameters) = &spec.parameters {
                relations.push(
                    RelationRef::new(parameters.kind.clone(), parameters.name.clone())
                        .ns(parameters.namespace.as_ref())
                        .api(parameters.api_group.as_ref()),
                );
            }
        }

        relations
    })
}

fn extract_pvc_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<PersistentVolumeClaim>(item, |pvc| {
        let mut relations = Vec::new();

        if let Some(spec) = &pvc.spec {
            if let Some(volume_name) = &spec.volume_name {
                relations.push(RelationRef::new("PersistentVolume", volume_name.clone()));
            }

            if let Some(storage_class) = &spec.storage_class_name {
                relations.push(RelationRef::new("StorageClass", storage_class.clone()));
            }
        }

        relations
    })
}

fn extract_pv_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<PersistentVolume>(item, |pv| {
        let mut relations = Vec::new();

        if let Some(spec) = &pv.spec {
            if let Some(claim_ref) = &spec.claim_ref {
                if let Some(rel) = object_ref_to_relation(claim_ref) {
                    relations.push(rel);
                }
            }

            if let Some(storage_class) = &spec.storage_class_name {
                relations.push(RelationRef::new("StorageClass", storage_class.clone()));
            }
        }

        relations
    })
}

fn extract_serviceaccount_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<ServiceAccount>(item, |sa| {
        let mut relations = Vec::new();
        let namespace = sa.metadata.namespace.as_deref();

        // secrets[] - manually added secrets
        if let Some(secrets) = &sa.secrets {
            for secret_ref in secrets {
                if let Some(name) = &secret_ref.name {
                    relations.push(RelationRef::new("Secret", name.clone()).ns(namespace));
                }
            }
        }

        // imagePullSecrets[]
        if let Some(image_pull_secrets) = &sa.image_pull_secrets {
            for secret_ref in image_pull_secrets {
                relations.push(RelationRef::new("Secret", secret_ref.name.clone()).ns(namespace));
            }
        }

        relations
    })
}

fn extract_rolebinding_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<RoleBinding>(item, |rb| {
        let mut relations = Vec::new();

        // roleRef - can be Role or ClusterRole
        let role_namespace = if rb.role_ref.kind == "Role" {
            rb.metadata.namespace.as_ref()
        } else {
            None
        };
        relations.push(
            RelationRef::new(rb.role_ref.kind.clone(), rb.role_ref.name.clone())
                .ns(role_namespace)
                .api(Some(&rb.role_ref.api_group)),
        );

        // subjects (ServiceAccounts, Users, Groups)
        if let Some(subjects) = &rb.subjects {
            for subject in subjects {
                if subject.kind == "ServiceAccount" {
                    relations.push(
                        RelationRef::new("ServiceAccount", subject.name.clone())
                            .ns(subject.namespace.as_ref()),
                    );
                }
            }
        }

        relations
    })
}

fn extract_clusterrolebinding_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<ClusterRoleBinding>(item, |crb| {
        let mut relations = Vec::new();

        // roleRef
        if crb.role_ref.kind == "ClusterRole" {
            relations.push(
                RelationRef::new(crb.role_ref.kind.clone(), crb.role_ref.name.clone())
                    .api(Some(&crb.role_ref.api_group)),
            );
        }

        // subjects (ServiceAccounts)
        if let Some(subjects) = &crb.subjects {
            for subject in subjects {
                if subject.kind == "ServiceAccount" {
                    relations.push(
                        RelationRef::new("ServiceAccount", subject.name.clone())
                            .ns(subject.namespace.as_ref()),
                    );
                }
            }
        }

        relations
    })
}

fn extract_validatingwebhook_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<ValidatingWebhookConfiguration>(item, |vwc| {
        vwc.webhooks
            .as_ref()
            .into_iter()
            .flatten()
            .filter_map(|w| w.client_config.service.as_ref())
            .map(|s| RelationRef::new("Service", s.name.clone()).ns(Some(&s.namespace)))
            .collect()
    })
}

fn extract_mutatingwebhook_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<MutatingWebhookConfiguration>(item, |mwc| {
        mwc.webhooks
            .as_ref()
            .into_iter()
            .flatten()
            .filter_map(|w| w.client_config.service.as_ref())
            .map(|s| RelationRef::new("Service", s.name.clone()).ns(Some(&s.namespace)))
            .collect()
    })
}

fn extract_apiservice_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<APIService>(item, |api_service| {
        let mut relations = Vec::new();

        if let Some(spec) = &api_service.spec {
            if let Some(service) = &spec.service {
                if let Some(name) = &service.name {
                    relations.push(RelationRef::new("Service", name.clone()).ns(service.namespace.as_ref()));
                }
            }
        }

        relations
    })
}

fn extract_hpa_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<HorizontalPodAutoscaler>(item, |hpa| {
        let mut relations = Vec::new();
        let namespace = hpa.metadata.namespace.as_deref();

        if let Some(spec) = &hpa.spec {
            // scaleTargetRef
            let scale_target = &spec.scale_target_ref;
            relations.push(
                RelationRef::new(scale_target.kind.clone(), scale_target.name.clone())
                    .ns(namespace)
                    .api(scale_target.api_version.as_ref()),
            );
        }

        relations
    })
}

fn extract_event_relations(item: &Value, _namespace: Option<&str>) -> Vec<RelationRef> {
    deserialize_and_extract::<Event>(item, |event| {
        let mut relations = Vec::new();

        // involved_object field (required field in Event)
        if let Some(rel) = object_ref_to_relation(&event.involved_object) {
            relations.push(rel);
        }

        // related field (optional)
        if let Some(related) = &event.related {
            if let Some(rel) = object_ref_to_relation(related) {
                relations.push(rel);
            }
        }

        relations
    })
}
