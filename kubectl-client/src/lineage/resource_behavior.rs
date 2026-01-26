use super::tree::{EdgeType, RelationRef};
use k8s_openapi::api::{
    admissionregistration::v1::{MutatingWebhookConfiguration, ValidatingWebhookConfiguration},
    apps::v1::{DaemonSet, Deployment, ReplicaSet, StatefulSet},
    autoscaling::v2::HorizontalPodAutoscaler,
    batch::v1::{CronJob, Job},
    core::v1::{
        Container, EphemeralContainer, Event, ObjectReference, PersistentVolume,
        PersistentVolumeClaim, Pod, PodSpec, Service, ServiceAccount, Volume,
    },
    networking::v1::{Ingress, IngressClass, NetworkPolicy},
    policy::v1::PodDisruptionBudget,
    rbac::v1::{ClusterRole, ClusterRoleBinding, Role, RoleBinding},
    storage::v1::StorageClass,
};
use k8s_openapi::kube_aggregator::pkg::apis::apiregistration::v1::APIService;

fn is_exception_cluster_role(name: &str) -> bool {
    matches!(
        name,
        "admin"
            | "alert-routing-edit"
            | "cloud-provider"
            | "cluster-admin"
            | "cluster-debugger"
            | "edit"
            | "eks:extension-metrics-apiserver"
            | "global-operators-admin"
            | "global-operators-edit"
            | "global-operators-view"
            | "monitoring-edit"
            | "monitoring-rules-edit"
            | "monitoring-rules-view"
            | "olm-operators-admin"
            | "olm-operators-edit"
            | "olm-operators-view"
            | "openshift-cluster-monitoring-admin"
            | "openshift-cluster-monitoring-edit"
            | "openshift-cluster-monitoring-view"
            | "openshift-csi-main-attacher-role"
            | "openshift-csi-main-provisioner-role"
            | "openshift-csi-main-resizer-role"
            | "openshift-csi-main-snapshotter-role"
            | "openshift-csi-provisioner-configmap-and-secret-reader-role"
            | "openshift-csi-provisioner-volumeattachment-reader-role"
            | "openshift-csi-provisioner-volumesnapshot-reader-role"
            | "openshift-csi-resizer-infrastructure-reader-role"
            | "openshift-csi-resizer-storageclass-reader-role"
            | "resource-metrics-server-resources"
            | "storage-admin"
            | "sudoer"
            | "system:aggregate-to-admin"
            | "system:aggregate-to-edit"
            | "system:aggregate-to-view"
            | "system:aggregated-metrics-reader"
            | "system:auth-delegator"
            | "system:build-strategy-custom"
            | "system:certificates.k8s.io:certificatesigningrequests:nodeclient"
            | "system:certificates.k8s.io:certificatesigningrequests:selfnodeclient"
            | "system:certificates.k8s.io:kube-apiserver-client-approver"
            | "system:certificates.k8s.io:kube-apiserver-client-kubelet-approver"
            | "system:certificates.k8s.io:kubelet-serving-approver"
            | "system:certificates.k8s.io:legacy-unknown-approver"
            | "system:controller:cloud-node-controller"
            | "system:controller:glbc"
            | "system:heapster"
            | "system:image-auditor"
            | "system:image-pusher"
            | "system:image-signer"
            | "system:kube-aggregator"
            | "system:kubelet-api-admin"
            | "system:metrics-server-aggregated-reader"
            | "system:node"
            | "system:node-bootstrapper"
            | "system:node-problem-detector"
            | "system:node-reader"
            | "system:openshift:aggregate-snapshots-to-storage-admin"
            | "system:openshift:aggregate-to-storage-admin"
            | "system:openshift:scc:hostaccess"
            | "system:openshift:scc:hostmount"
            | "system:openshift:scc:hostnetwork"
            | "system:openshift:scc:nonroot"
            | "system:openshift:scc:nonroot-v2"
            | "system:openshift:scc:privileged"
            | "system:openshift:scc:restricted"
            | "system:openshift:templateservicebroker-client"
            | "system:persistent-volume-provisioner"
            | "system:router"
            | "system:sdn-manager"
            | "view"
    )
}

/// Check if a ServiceAccount is a system default (only "default" SA, not all in system namespaces)
fn is_system_service_account(name: &str) -> bool {
    name == "default"
}

/// Check if a ClusterRoleBinding is a system resource that should never be considered orphan
fn is_exception_cluster_role_binding(name: &str) -> bool {
    matches!(
        name,
        "kubeadm:kubelet-bootstrap"
            | "kubeadm:node-autoapprove-bootstrap"
            | "kubeadm:node-autoapprove-certificate-rotation"
            | "system:controller:route-controller"
            | "system:kube-dns"
            | "system:node"
            | "event-exporter-rb"
            | "kubelet-bootstrap"
            | "kubelet-bootstrap-node-bootstrapper"
            | "kubelet-cluster-admin"
            | "kubelet-nodepool-bootstrapper"
            | "kubelet-user-npd-binding"
            | "metrics-server-nanny:system:auth-delegator"
            | "metrics-server:system:auth-delegator"
            | "npd-binding"
            | "system:controller:horizontal-pod-autoscaler"
            | "system:controller:selinux-warning-controller"
            | "system:konnectivity-server"
    )
}

/// Check if a RoleBinding is a system resource that should never be considered orphan
fn is_exception_role_binding(name: &str, namespace: Option<&str>) -> bool {
    match namespace {
        Some("kube-system") => {
            // system::* and system:controller:* patterns
            name.starts_with("system::") || name.starts_with("system:controller:")
                || matches!(name, "kube-proxy" | "kubeadm:kubelet-config" | "kubeadm:nodes-kubeadm-config" | "gce:podsecuritypolicy:pdcsi-node-sa")
        }
        Some("kube-public") => {
            matches!(name, "kubeadm:bootstrap-signer-clusterinfo" | "system:controller:bootstrap-signer")
        }
        Some("gmp-public") => name == "operator",
        _ => false,
    }
}

/// Check if a ConfigMap is a system resource that should never be considered orphan
fn is_exception_config_map(name: &str, namespace: Option<&str>) -> bool {
    // Pattern-based exceptions (any namespace)
    if name == "kube-root-ca.crt" || name == "openshift-service-ca.crt" {
        return true;
    }

    match namespace {
        Some("kube-system") => matches!(
            name,
            "amazon-vpc-cni"
                | "aws-auth"
                | "bootstrap"
                | "cluster-autoscaler-status"
                | "cluster-config-v1"
                | "cluster-dns"
                | "cluster-kubestore"
                | "clustermetrics"
                | "coredns-autoscaler"
                | "extension-apiserver-authentication"
                | "gke-common-webhook-heartbeat"
                | "ingress-uid"
                | "konnectivity-agent-autoscaler-config"
                | "kube-apiserver-legacy-service-account-token-tracking"
                | "kube-dns-autoscaler"
                | "kube-proxy"
                | "kube-proxy-config"
                | "kubeadm-config"
                | "kubedns-config-images"
                | "kubelet-config"
                | "overlay-upgrade-data"
                | "root-ca"
                | "efficiency-daemon-config"
                | "metrics-agent-linux-config-images"
                | "metrics-agent-windows-config-images"
                | "nvidia-metrics-collector-config-map"
        ),
        Some("kube-public") => name == "cluster-info",
        Some("gmp-system") => {
            matches!(name, "config-images" | "webhook-ca" | "rule-evaluator" | "rules-generated")
        }
        Some("kubernetes-dashboard") => name == "kubernetes-dashboard-settings",
        Some("gke-managed-system") => name == "dcgm-exporter-metrics",
        Some(ns) if ns.starts_with("openshift-") => true,
        _ => false,
    }
}

/// Check if a Secret is a system resource that should never be considered orphan
fn is_exception_secret(name: &str, namespace: Option<&str>) -> bool {
    match namespace {
        Some("kube-system") => {
            // bootstrap-token-* pattern
            name.starts_with("bootstrap-token-")
                || name.ends_with(".node-password.k3s")
                || matches!(name, "k3s-serving" | "kube-cloud-cfg" | "kubeadmin")
        }
        Some("kubernetes-dashboard") => matches!(
            name,
            "kubernetes-dashboard-certs"
                | "kubernetes-dashboard-csrf"
                | "kubernetes-dashboard-key-holder"
        ),
        Some("gmp-system") => matches!(name, "alertmanager" | "rules" | "webhook-tls"),
        Some(ns) if ns.starts_with("openshift-") => true,
        _ => false,
    }
}

/// Check if a Service is a system resource (only "kubernetes" service in default namespace)
fn is_system_service(name: &str, namespace: Option<&str>) -> bool {
    name == "kubernetes" && namespace == Some("default")
}

/// Trait for defining resource-specific behavior in the lineage graph
pub trait ResourceBehavior {
    /// Extract relationships this resource has to other resources
    fn extract_relationships(&self, namespace: Option<&str>) -> Vec<RelationRef>;

    /// Determine if this resource type is orphaned given its incoming edges
    /// Default: not an orphan-able resource type
    fn is_orphan(
        _name: &str,
        _namespace: Option<&str>,
        _incoming_refs: &[(EdgeType, &str)],
        _labels: Option<&std::collections::HashMap<String, String>>,
        _resource_type: Option<&str>,
        _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>,
    ) -> bool {
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

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // Ingress is orphaned if it has no incoming References from Service
        // (meaning its backend services don't exist in the cluster)
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            matches!(edge_type, EdgeType::References) && source_kind.eq_ignore_ascii_case("service")
        })
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

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // IngressClass is orphaned if no Ingress references it
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            matches!(edge_type, EdgeType::References) && source_kind.eq_ignore_ascii_case("ingress")
        })
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

        // environment variables from ephemeralContainers
        if let Some(ephemeral_containers) = &spec.ephemeral_containers {
            for container in ephemeral_containers {
                relations.extend(extract_ephemeral_container_env_relations(
                    container, namespace,
                ));
            }
        }

        // imagePullSecrets
        if let Some(image_pull_secrets) = &spec.image_pull_secrets {
            for secret_ref in image_pull_secrets {
                relations.push(RelationRef {
                    kind: "Secret".to_string(),
                    name: secret_ref.name.clone(),
                    namespace: namespace.map(String::from),
                    api_version: None,
                    uid: None,
                });
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

    fn is_orphan(
        name: &str,
        _namespace: Option<&str>,
        incoming_refs: &[(EdgeType, &str)],
        _labels: Option<&std::collections::HashMap<String, String>>,
        _resource_type: Option<&str>,
        _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>,
    ) -> bool {
        // Check exception list first
        if is_exception_cluster_role(name) {
            return false;
        }

        // ClusterRole is orphaned if it has no incoming References from RoleBinding or ClusterRoleBinding
        // Note: We don't check aggregation labels here because that requires checking if another
        // ClusterRole's aggregation rule actually matches this role's labels (complex cross-reference)
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && (source_lower == "rolebinding" || source_lower == "clusterrolebinding")
        })
    }
}

// Role resource behavior
impl ResourceBehavior for Role {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        // Role relationships are similar to ClusterRole
        // For now, return empty - can be enhanced later
        Vec::new()
    }

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // Role is orphaned if it has no incoming References from RoleBinding
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References) && source_lower == "rolebinding"
        })
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

            if let Some(storage_class) = &spec.storage_class_name {
                relations.push(RelationRef {
                    kind: "StorageClass".to_string(),
                    name: storage_class.clone(),
                    namespace: None,
                    api_version: None,
                    uid: None,
                });
            }
        }

        relations
    }

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
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

            if let Some(storage_class) = &spec.storage_class_name {
                relations.push(RelationRef {
                    kind: "StorageClass".to_string(),
                    name: storage_class.clone(),
                    namespace: None,
                    api_version: None,
                    uid: None,
                });
            }
        }

        relations
    }

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && source_lower == "persistentvolumeclaim"
        })
    }
}

// StorageClass resource behavior
impl ResourceBehavior for StorageClass {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        // StorageClass is referenced by PVCs and PVs, it doesn't reference other resources
        Vec::new()
    }

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // StorageClass is orphaned if no PVC or PV references it
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && (source_lower == "persistentvolumeclaim" || source_lower == "persistentvolume")
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

    fn is_orphan(name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // Check exception list first
        if is_exception_cluster_role_binding(name) {
            return false;
        }

        // ClusterRoleBinding is orphaned if:
        // 1. The ClusterRole it references doesn't exist, OR
        // 2. Any ServiceAccount subjects it references don't exist

        // Check if ClusterRole exists
        let has_cluster_role = incoming_refs.iter().any(|(edge_type, source_kind)| {
            matches!(edge_type, EdgeType::References)
                && source_kind.eq_ignore_ascii_case("clusterrole")
        });

        if !has_cluster_role {
            return true;
        }

        // Check if any ServiceAccount subjects are missing
        if let Some(missing) = missing_refs {
            if missing.contains_key("ServiceAccount") {
                return true;
            }
        }

        false
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

        // Extract pod spec relations (ConfigMaps, Secrets, etc.)
        if let Some(pod_spec) = &spec.template.spec {
            relations.extend(extract_pod_spec_relations(pod_spec, namespace));
        }

        relations
    }
}

// Deployment resource behavior
impl ResourceBehavior for Deployment {
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

// ReplicaSet resource behavior
impl ResourceBehavior for ReplicaSet {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let namespace = self.metadata.namespace.as_deref();

        let spec = match &self.spec {
            Some(s) => s,
            None => return Vec::new(),
        };

        let pod_spec = match &spec.template {
            Some(t) => match &t.spec {
                Some(s) => s,
                None => return Vec::new(),
            },
            None => return Vec::new(),
        };

        extract_pod_spec_relations(pod_spec, namespace)
    }

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // ReplicaSet is orphaned if:
        // 1. It has no owning Deployment (no incoming Owns edge)
        // 2. AND it has no Pods (no incoming References from Pod)
        let has_owner = incoming_refs
            .iter()
            .any(|(edge_type, _)| matches!(edge_type, EdgeType::Owns));
        let has_pods = incoming_refs.iter().any(|(edge_type, source_kind)| {
            matches!(edge_type, EdgeType::References) && source_kind.eq_ignore_ascii_case("pod")
        });
        !has_owner && !has_pods
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

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // HPA is orphaned if its target (Deployment/StatefulSet/ReplicaSet) doesn't exist
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && (source_lower == "deployment"
                    || source_lower == "statefulset"
                    || source_lower == "replicaset")
        })
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

    fn is_orphan(name: &str, namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // System Services are never orphans
        if is_system_service(name, namespace) {
            return false;
        }

        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && (source_lower == "pod"
                    || source_lower == "ingress"
                    || source_lower == "validatingwebhookconfiguration"
                    || source_lower == "mutatingwebhookconfiguration"
                    || source_lower == "apiservice")
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

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // NetworkPolicy is orphaned if it has no incoming References from Pod
        // (meaning its podSelector doesn't match any pods)
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            matches!(edge_type, EdgeType::References) && source_kind.eq_ignore_ascii_case("pod")
        })
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

    fn is_orphan(name: &str, namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // Check exception list first
        if is_exception_role_binding(name, namespace) {
            return false;
        }

        // RoleBinding is orphaned if:
        // 1. The Role or ClusterRole it references doesn't exist, OR
        // 2. Any ServiceAccount subjects it references don't exist

        // Check if Role or ClusterRole exists
        let has_role = incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && (source_lower == "role" || source_lower == "clusterrole")
        });

        if !has_role {
            return true;
        }

        // Check if any ServiceAccount subjects are missing
        if let Some(missing) = missing_refs {
            if missing.contains_key("ServiceAccount") {
                return true;
            }
        }

        false
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

    fn is_orphan(_name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // PodDisruptionBudget is orphaned if it has no incoming References from Pod
        // (meaning its selector doesn't match any pods it's supposed to protect)
        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            matches!(edge_type, EdgeType::References) && source_kind.eq_ignore_ascii_case("pod")
        })
    }
}

// ValidatingWebhookConfiguration resource behavior
impl ResourceBehavior for ValidatingWebhookConfiguration {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();

        if let Some(webhooks) = &self.webhooks {
            for webhook in webhooks {
                if let Some(service) = &webhook.client_config.service {
                    relations.push(RelationRef {
                        kind: "Service".to_string(),
                        name: service.name.clone(),
                        namespace: Some(service.namespace.clone()),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }

        relations
    }
}

// MutatingWebhookConfiguration resource behavior
impl ResourceBehavior for MutatingWebhookConfiguration {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();

        if let Some(webhooks) = &self.webhooks {
            for webhook in webhooks {
                if let Some(service) = &webhook.client_config.service {
                    relations.push(RelationRef {
                        kind: "Service".to_string(),
                        name: service.name.clone(),
                        namespace: Some(service.namespace.clone()),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }

        relations
    }
}

// APIService resource behavior
impl ResourceBehavior for APIService {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();

        if let Some(spec) = &self.spec {
            if let Some(service) = &spec.service {
                if let Some(name) = &service.name {
                    relations.push(RelationRef {
                        kind: "Service".to_string(),
                        name: name.clone(),
                        namespace: service.namespace.clone(),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }

        relations
    }
}

// Marker structs for resources without k8s_openapi types
pub struct ConfigMapBehavior;
impl ResourceBehavior for ConfigMapBehavior {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        Vec::new()
    }

    fn is_orphan(name: &str, namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // Check exception list first
        if is_exception_config_map(name, namespace) {
            return false;
        }

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

    fn is_orphan(name: &str, namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], labels: Option<&std::collections::HashMap<String, String>>, resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // Check exception list first
        if is_exception_secret(name, namespace) {
            return false;
        }

        // Service account token secrets are never orphans (automatically managed by Kubernetes)
        // Check the Secret type field first (most reliable)
        if let Some(secret_type) = resource_type {
            if secret_type == "kubernetes.io/service-account-token" {
                return false;
            }
        }

        // Fallback: Check for the label that indicates this is a service account token
        if let Some(label_map) = labels {
            if label_map.contains_key("kubernetes.io/service-account.name") {
                return false;
            }
        }

        // Secret is orphaned if it has NO incoming References edge from any resource
        // (Pods, ServiceAccounts, Ingress, etc. all create References edges to Secrets)
        !incoming_refs
            .iter()
            .any(|(edge_type, _)| matches!(edge_type, EdgeType::References))
    }
}

// ServiceAccount resource behavior
impl ResourceBehavior for ServiceAccount {
    fn extract_relationships(&self, _namespace: Option<&str>) -> Vec<RelationRef> {
        let mut relations = Vec::new();
        let namespace = self.metadata.namespace.as_deref();

        // secrets[] - manually added secrets
        if let Some(secrets) = &self.secrets {
            for secret_ref in secrets {
                if let Some(name) = &secret_ref.name {
                    relations.push(RelationRef {
                        kind: "Secret".to_string(),
                        name: name.clone(),
                        namespace: namespace.map(String::from),
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }

        // imagePullSecrets[]
        if let Some(image_pull_secrets) = &self.image_pull_secrets {
            for secret_ref in image_pull_secrets {
                relations.push(RelationRef {
                    kind: "Secret".to_string(),
                    name: secret_ref.name.clone(),
                    namespace: namespace.map(String::from),
                    api_version: None,
                    uid: None,
                });
            }
        }

        relations
    }

    fn is_orphan(name: &str, _namespace: Option<&str>, incoming_refs: &[(EdgeType, &str)], _labels: Option<&std::collections::HashMap<String, String>>, _resource_type: Option<&str>, _missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>) -> bool {
        // Only "default" ServiceAccount is never an orphan (it's auto-created in every namespace)
        if is_system_service_account(name) {
            return false;
        }

        !incoming_refs.iter().any(|(edge_type, source_kind)| {
            let source_lower = source_kind.to_lowercase();
            matches!(edge_type, EdgeType::References)
                && (source_lower == "pod"
                    || source_lower == "deployment"
                    || source_lower == "statefulset"
                    || source_lower == "daemonset"
                    || source_lower == "job"
                    || source_lower == "cronjob"
                    || source_lower == "replicaset"
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

/// Extract ephemeral container environment variable relationships
fn extract_ephemeral_container_env_relations(
    container: &EphemeralContainer,
    namespace: Option<&str>,
) -> Vec<RelationRef> {
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

    // environment variables from ephemeralContainers
    if let Some(ephemeral_containers) = &spec.ephemeral_containers {
        for container in ephemeral_containers {
            relations.extend(extract_ephemeral_container_env_relations(
                container, namespace,
            ));
        }
    }

    // imagePullSecrets
    if let Some(image_pull_secrets) = &spec.image_pull_secrets {
        for secret_ref in image_pull_secrets {
            relations.push(RelationRef {
                kind: "Secret".to_string(),
                name: secret_ref.name.clone(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    relations
}
