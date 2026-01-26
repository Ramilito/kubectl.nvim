use super::tree::{EdgeType, RelationRef};
use k8s_openapi::api::{
    apps::v1::{DaemonSet, StatefulSet},
    autoscaling::v2::HorizontalPodAutoscaler,
    batch::v1::{CronJob, Job},
    core::v1::{
        Container, Event, ObjectReference, PersistentVolume, PersistentVolumeClaim, Pod,
        PodSpec, Service, Volume,
    },
    networking::v1::{Ingress, IngressClass, NetworkPolicy},
    policy::v1::PodDisruptionBudget,
    rbac::v1::{ClusterRole, ClusterRoleBinding, RoleBinding},
};

/// Trait for defining resource-specific behavior in the lineage graph
pub trait ResourceBehavior {
    /// Extract relationships this resource has to other resources
    fn extract_relationships(&self, namespace: Option<&str>) -> Vec<RelationRef>;

    /// Determine if this resource type is orphaned given its incoming edges
    /// Default: not an orphan-able resource type
    fn is_orphan(_incoming_refs: &[(EdgeType, &str)]) -> bool {
        false
    }
}

// Event resource behavior
impl ResourceBehavior for Event {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();

        // involved_object field (required field in Event)
        if let Some(rel) = object_ref_to_relation(&self.involved_object) {
            relations.push(rel);
        }

        // related field (optional)
        if let Some(related) = &self.related {
            if let Some(rel) = object_ref_to_relation(related) {
                relations.push(rel);
            }
        }

        relations
    }
}

// Ingress resource behavior
impl ResourceBehavior for Ingress {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();
        let namespace = self.metadata.namespace.as_deref();

        let spec = match &self.spec {
            Some(s) => s,
            None => return relations,
        };

        // ingressClassName
        if let Some(class_name) = &spec.ingress_class_name {
            relations.push(RelationRef {
                kind: "IngressClass".to_string(),
                name: class_name.clone(),
                namespace: None,
                api_version: None,
                uid: None,
            });
        }

        // default backend
        if let Some(backend) = &spec.default_backend {
            if let Some(service) = &backend.service {
                relations.push(RelationRef {
                    kind: "Service".to_string(),
                    name: service.name.clone(),
                    namespace: namespace.map(String::from),
                    api_version: None,
                    uid: None,
                });
            }
            if let Some(resource) = &backend.resource {
                relations.push(RelationRef {
                    kind: resource.kind.clone(),
                    name: resource.name.clone(),
                    namespace: namespace.map(String::from),
                    api_version: resource.api_group.clone(),
                    uid: None,
                });
            }
        }

        // rules
        if let Some(rules) = &spec.rules {
            for rule in rules {
                if let Some(http) = &rule.http {
                    for path in &http.paths {
                        if let Some(service) = &path.backend.service {
                            relations.push(RelationRef {
                                kind: "Service".to_string(),
                                name: service.name.clone(),
                                namespace: namespace.map(String::from),
                                api_version: None,
                                uid: None,
                            });
                        }
                        if let Some(resource) = &path.backend.resource {
                            relations.push(RelationRef {
                                kind: resource.kind.clone(),
                                name: resource.name.clone(),
                                namespace: namespace.map(String::from),
                                api_version: resource.api_group.clone(),
                                uid: None,
                            });
                        }
                    }
                }
            }
        }

        // tls secrets
        if let Some(tls_list) = &spec.tls {
            for tls in tls_list {
                if let Some(secret_name) = &tls.secret_name {
                    relations.push(RelationRef {
                        kind: "Secret".to_string(),
                        name: secret_name.clone(),
                        namespace: namespace.map(String::from),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }

        relations
    }
}

// IngressClass resource behavior
impl ResourceBehavior for IngressClass {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();

        if let Some(spec) = &self.spec {
            if let Some(parameters) = &spec.parameters {
                relations.push(RelationRef {
                    kind: parameters.kind.clone(),
                    name: parameters.name.clone(),
                    namespace: parameters.namespace.clone(),
                    api_version: parameters.api_group.clone(),
                    uid: None,
                });
            }
        }

        relations
    }
}

// Pod resource behavior
impl ResourceBehavior for Pod {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();
        let namespace = self.metadata.namespace.as_deref();

        let spec = match &self.spec {
            Some(s) => s,
            None => return relations,
        };

        // nodeName
        if let Some(node_name) = &spec.node_name {
            relations.push(RelationRef {
                kind: "Node".to_string(),
                name: node_name.clone(),
                namespace: None,
                api_version: None,
                uid: None,
            });
        }

        // priorityClassName
        if let Some(priority_class) = &spec.priority_class_name {
            relations.push(RelationRef {
                kind: "PriorityClass".to_string(),
                name: priority_class.clone(),
                namespace: None,
                api_version: None,
                uid: None,
            });
        }

        // runtimeClassName
        if let Some(runtime_class) = &spec.runtime_class_name {
            relations.push(RelationRef {
                kind: "RuntimeClass".to_string(),
                name: runtime_class.clone(),
                namespace: None,
                api_version: None,
                uid: None,
            });
        }

        // serviceAccountName
        if let Some(sa_name) = &spec.service_account_name {
            relations.push(RelationRef {
                kind: "ServiceAccount".to_string(),
                name: sa_name.clone(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }

        // volumes (includes ConfigMap and Secret references)
        if let Some(volumes) = &spec.volumes {
            for volume in volumes {
                relations.extend(extract_volume_relations(volume, namespace));
            }
        }

        // environment variables from containers
        for container in &spec.containers {
            relations.extend(extract_container_env_relations(container, namespace));
        }

        // environment variables from initContainers
        if let Some(init_containers) = &spec.init_containers {
            for container in init_containers {
                relations.extend(extract_container_env_relations(container, namespace));
            }
        }

        relations
    }
}

// ClusterRole resource behavior
impl ResourceBehavior for ClusterRole {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        // ClusterRole relationships are complex and selector-based
        // For now, return empty - can be enhanced later
        Vec::new()
    }
}

// PersistentVolumeClaim resource behavior
impl ResourceBehavior for PersistentVolumeClaim {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();

        if let Some(spec) = &self.spec {
            if let Some(volume_name) = &spec.volume_name {
                relations.push(RelationRef {
                    kind: "PersistentVolume".to_string(),
                    name: volume_name.clone(),
                    namespace: None,
                    api_version: None,
                    uid: None,
                });
            }
        }

        relations
    }

    fn is_orphan(incoming_refs: &[(EdgeType, &str)]) -> bool {
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && (source_lower == "pod" || source_lower == "statefulset")
        })
    }
}

// PersistentVolume resource behavior
impl ResourceBehavior for PersistentVolume {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();

        if let Some(spec) = &self.spec {
            if let Some(claim_ref) = &spec.claim_ref {
                if let Some(rel) = object_ref_to_relation(claim_ref) {
                    relations.push(rel);
                }
            }
        }

        relations
    }

    fn is_orphan(incoming_refs: &[(EdgeType, &str)]) -> bool {
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && source_lower == "persistentvolumeclaim"
        })
    }
}

// ClusterRoleBinding resource behavior
impl ResourceBehavior for ClusterRoleBinding {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();

        // roleRef
        if self.role_ref.kind == "ClusterRole" {
            relations.push(RelationRef {
                kind: self.role_ref.kind.clone(),
                name: self.role_ref.name.clone(),
                namespace: None,
                api_version: Some(self.role_ref.api_group.clone()),
                uid: None,
            });
        }

        // subjects (ServiceAccounts)
        if let Some(subjects) = &self.subjects {
            for subject in subjects {
                if subject.kind == "ServiceAccount" {
                    relations.push(RelationRef {
                        kind: "ServiceAccount".to_string(),
                        name: subject.name.clone(),
                        namespace: subject.namespace.clone(),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }

        relations
    }
}

// StatefulSet resource behavior
impl ResourceBehavior for StatefulSet {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();
        let namespace = self.metadata.namespace.as_deref();

        let spec = match &self.spec {
            Some(s) => s,
            None => return relations,
        };

        // volumeClaimTemplates
        if let Some(templates) = &spec.volume_claim_templates {
            for template in templates {
                if let Some(name) = &template.metadata.name {
                    relations.push(RelationRef {
                        kind: "PersistentVolumeClaim".to_string(),
                        name: name.clone(),
                        namespace: namespace.map(String::from),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }

        // serviceName
        if let Some(service_name) = &spec.service_name {
            relations.push(RelationRef {
                kind: "Service".to_string(),
                name: service_name.clone(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }

        relations
    }
}

// DaemonSet resource behavior
impl ResourceBehavior for DaemonSet {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let namespace = self.metadata.namespace.as_deref();

        let spec = match &self.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let pod_spec = match &spec.template.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        extract_pod_spec_relations(pod_spec, namespace)
    }
}

// Job resource behavior
impl ResourceBehavior for Job {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let namespace = self.metadata.namespace.as_deref();

        let spec = match &self.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let pod_spec = match &spec.template.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        extract_pod_spec_relations(pod_spec, namespace)
    }
}

// CronJob resource behavior
impl ResourceBehavior for CronJob {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let namespace = self.metadata.namespace.as_deref();

        let spec = match &self.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let job_spec = match &spec.job_template.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let pod_spec = match &job_spec.template.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        extract_pod_spec_relations(pod_spec, namespace)
    }
}

// HorizontalPodAutoscaler resource behavior
impl ResourceBehavior for HorizontalPodAutoscaler {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();
        let namespace = self.metadata.namespace.as_deref();

        if let Some(spec) = &self.spec {
            // scaleTargetRef
            let scale_target = &spec.scale_target_ref;
            relations.push(RelationRef {
                kind: scale_target.kind.clone(),
                name: scale_target.name.clone(),
                namespace: namespace.map(String::from),
                api_version: scale_target.api_version.clone(),
                uid: None,
            });
        }

        relations
    }
}

// Service resource behavior
impl ResourceBehavior for Service {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        // Service → Pod relationships are selector-based and handled via the selector field
        // in the Resource struct, which is processed in tree.rs link_nodes()
        // The selector matching happens in tree.rs using the selectors_match function
        Vec::new()
    }

    fn is_orphan(incoming_refs: &[(EdgeType, &str)]) -> bool {
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && (source_lower == "pod" || source_lower == "ingress")
        })
    }
}

// NetworkPolicy resource behavior
impl ResourceBehavior for NetworkPolicy {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        // NetworkPolicy → Pod relationships are selector-based (via spec.podSelector)
        // and handled via the selector field in the Resource struct
        // The selector matching happens in tree.rs link_nodes()
        Vec::new()
    }
}

// RoleBinding resource behavior
impl ResourceBehavior for RoleBinding {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();

        // roleRef - can be Role or ClusterRole
        relations.push(RelationRef {
            kind: self.role_ref.kind.clone(),
            name: self.role_ref.name.clone(),
            namespace: if self.role_ref.kind == "Role" {
                self.metadata.namespace.clone()
            } else {
                None
            },
            api_version: Some(self.role_ref.api_group.clone()),
            uid: None,
        });

        // subjects (ServiceAccounts, Users, Groups)
        if let Some(subjects) = &self.subjects {
            for subject in subjects {
                if subject.kind == "ServiceAccount" {
                    relations.push(RelationRef {
                        kind: "ServiceAccount".to_string(),
                        name: subject.name.clone(),
                        namespace: subject.namespace.clone(),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }

        relations
    }
}

// PodDisruptionBudget resource behavior
impl ResourceBehavior for PodDisruptionBudget {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        // PodDisruptionBudget → Pod relationships are selector-based (via spec.selector)
        // and handled via the selector field in the Resource struct
        // The selector matching happens in tree.rs link_nodes()
        Vec::new()
    }
}

// Marker structs for resources without k8s_openapi types
pub struct ConfigMapBehavior;
impl ResourceBehavior for ConfigMapBehavior {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        Vec::new()
    }

    fn is_orphan(incoming_refs: &[(EdgeType, &str)]) -> bool {
        !incoming_refs
            .iter()
            .any(|(edge_type, _)| matches!(edge_type, EdgeType::References))
    }
}

pub struct SecretBehavior;
impl ResourceBehavior for SecretBehavior {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        Vec::new()
    }

    fn is_orphan(incoming_refs: &[(EdgeType, &str)]) -> bool {
        !incoming_refs
            .iter()
            .any(|(edge_type, _)| matches!(edge_type, EdgeType::References))
    }
}

pub struct ServiceAccountBehavior;
impl ResourceBehavior for ServiceAccountBehavior {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        Vec::new()
    }

    fn is_orphan(incoming_refs: &[(EdgeType, &str)]) -> bool {
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && (source_lower == "pod"
                    || source_lower == "rolebinding"
                    || source_lower == "clusterrolebinding")
        })
    }
}

// Helper functions

/// Helper to convert ObjectReference to RelationRef
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

/// Extract container environment variable relationships
fn extract_container_env_relations(container: &Container, namespace: Option<&str>) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    // env with valueFrom
    if let Some(env_vars) = &container.env {
        for env in env_vars {
            if let Some(value_from) = &env.value_from {
                // configMapKeyRef
                if let Some(config_map_ref) = &value_from.config_map_key_ref {
                    relations.push(RelationRef {
                        kind: "ConfigMap".to_string(),
                        name: config_map_ref.name.clone(),
                        namespace: namespace.map(String::from),
                        api_version: None,
                        uid: None,
                    });
                }
                // secretKeyRef
                if let Some(secret_ref) = &value_from.secret_key_ref {
                    relations.push(RelationRef {
                        kind: "Secret".to_string(),
                        name: secret_ref.name.clone(),
                        namespace: namespace.map(String::from),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }
    }

    // envFrom
    if let Some(env_from) = &container.env_from {
        for env in env_from {
            // configMapRef
            if let Some(config_map_ref) = &env.config_map_ref {
                relations.push(RelationRef {
                    kind: "ConfigMap".to_string(),
                    name: config_map_ref.name.clone(),
                    namespace: namespace.map(String::from),
                    api_version: None,
                    uid: None,
                });
            }
            // secretRef
            if let Some(secret_ref) = &env.secret_ref {
                relations.push(RelationRef {
                    kind: "Secret".to_string(),
                    name: secret_ref.name.clone(),
                    namespace: namespace.map(String::from),
                    api_version: None,
                    uid: None,
                });
            }
        }
    }

    relations
}

/// Extract volume relationships
fn extract_volume_relations(volume: &Volume, namespace: Option<&str>) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    // ConfigMap
    if let Some(config_map) = &volume.config_map {
        relations.push(RelationRef {
            kind: "ConfigMap".to_string(),
            name: config_map.name.clone(),
            namespace: namespace.map(String::from),
            api_version: None,
            uid: None,
        });
    }

    // Secret
    if let Some(secret) = &volume.secret {
        if let Some(name) = &secret.secret_name {
            relations.push(RelationRef {
                kind: "Secret".to_string(),
                name: name.clone(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    // PersistentVolumeClaim
    if let Some(pvc) = &volume.persistent_volume_claim {
        relations.push(RelationRef {
            kind: "PersistentVolumeClaim".to_string(),
            name: pvc.claim_name.clone(),
            namespace: namespace.map(String::from),
            api_version: None,
            uid: None,
        });
    }

    // CSI
    if let Some(csi) = &volume.csi {
        relations.push(RelationRef {
            kind: "CSIDriver".to_string(),
            name: csi.driver.clone(),
            namespace: None,
            api_version: None,
            uid: None,
        });
        if let Some(secret_ref) = &csi.node_publish_secret_ref {
            relations.push(RelationRef {
                kind: "Secret".to_string(),
                name: secret_ref.name.clone(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    // Projected
    if let Some(projected) = &volume.projected {
        if let Some(sources) = &projected.sources {
            for source in sources {
                if let Some(config_map) = &source.config_map {
                    relations.push(RelationRef {
                        kind: "ConfigMap".to_string(),
                        name: config_map.name.clone(),
                        namespace: namespace.map(String::from),
                        api_version: None,
                        uid: None,
                    });
                }
                if let Some(secret) = &source.secret {
                    relations.push(RelationRef {
                        kind: "Secret".to_string(),
                        name: secret.name.clone(),
                        namespace: namespace.map(String::from),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }
    }

    relations
}

/// Extract relationships from a PodSpec (used by DaemonSet, Job, CronJob)
fn extract_pod_spec_relations(spec: &PodSpec, namespace: Option<&str>) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    // serviceAccountName
    if let Some(sa_name) = &spec.service_account_name {
        relations.push(RelationRef {
            kind: "ServiceAccount".to_string(),
            name: sa_name.clone(),
            namespace: namespace.map(String::from),
            api_version: None,
            uid: None,
        });
    }

    // volumes
    if let Some(volumes) = &spec.volumes {
        for volume in volumes {
            relations.extend(extract_volume_relations(volume, namespace));
        }
    }

    // environment variables from containers
    for container in &spec.containers {
        relations.extend(extract_container_env_relations(container, namespace));
    }

    // environment variables from initContainers
    if let Some(init_containers) = &spec.init_containers {
        for container in init_containers {
            relations.extend(extract_container_env_relations(container, namespace));
        }
    }

    relations
}
