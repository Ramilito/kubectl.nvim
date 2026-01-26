use super::tree::EdgeType;
use std::collections::HashMap;

/// Declarative orphan condition DSL
#[derive(Debug, Clone)]
pub enum OrphanCondition {
    /// Resource has no incoming References edges
    NoIncomingRefs,
    /// Resource has no incoming References from specific kinds
    NoIncomingFrom(&'static [&'static str]),
    /// Resource has an outgoing reference that doesn't exist in the cluster
    HasMissingRef(&'static str),
    /// Resource has no owner (no Owns edge)
    NoOwner,
    /// Resource is a service account token (special SA secret)
    IsServiceAccountToken,
    /// All conditions must be true
    And(&'static [OrphanCondition]),
    /// Any condition must be true
    Or(&'static [OrphanCondition]),
}

/// Context data needed for evaluating orphan conditions
#[allow(dead_code)]
pub struct OrphanContext<'a> {
    pub name: &'a str,
    pub namespace: Option<&'a str>,
    pub incoming_refs: &'a [(EdgeType, &'a str)],
    pub labels: Option<&'a HashMap<String, String>>,
    pub resource_type: Option<&'a str>,
    pub missing_refs: Option<&'a HashMap<String, Vec<String>>>,
}

/// Orphan rule for a resource type
pub struct OrphanRule {
    pub exception: Option<fn(&str, Option<&str>) -> bool>,
    pub condition: OrphanCondition,
}

/// Evaluate an orphan condition against a context
pub fn evaluate(condition: &OrphanCondition, ctx: &OrphanContext) -> bool {
    match condition {
        OrphanCondition::NoIncomingRefs => !ctx
            .incoming_refs
            .iter()
            .any(|(edge_type, _)| matches!(edge_type, EdgeType::References)),

        OrphanCondition::NoIncomingFrom(kinds) => !ctx.incoming_refs.iter().any(|(edge_type, source_kind)| {
            matches!(edge_type, EdgeType::References)
                && kinds
                    .iter()
                    .any(|k| source_kind.eq_ignore_ascii_case(k))
        }),

        OrphanCondition::HasMissingRef(kind) => ctx
            .missing_refs
            .map(|m| m.contains_key(*kind))
            .unwrap_or(false),

        OrphanCondition::NoOwner => !ctx
            .incoming_refs
            .iter()
            .any(|(edge_type, _)| matches!(edge_type, EdgeType::Owns)),

        OrphanCondition::IsServiceAccountToken => {
            // Check the Secret type field first (most reliable)
            if let Some(secret_type) = ctx.resource_type {
                if secret_type == "kubernetes.io/service-account-token" {
                    return false;
                }
            }

            // Fallback: Check for the label that indicates this is a service account token
            if let Some(label_map) = ctx.labels {
                if label_map.contains_key("kubernetes.io/service-account.name") {
                    return false;
                }
            }

            // If neither check passes, it's not a service account token (condition is false)
            true
        }

        OrphanCondition::And(conditions) => conditions.iter().all(|c| evaluate(c, ctx)),

        OrphanCondition::Or(conditions) => conditions.iter().any(|c| evaluate(c, ctx)),
    }
}

/// Exception functions (moved from resource_behavior.rs)

pub fn is_exception_cluster_role(name: &str) -> bool {
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

pub fn is_exception_cluster_role_binding(name: &str) -> bool {
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

pub fn is_exception_role_binding(name: &str, namespace: Option<&str>) -> bool {
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

pub fn is_exception_config_map(name: &str, namespace: Option<&str>) -> bool {
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

pub fn is_exception_secret(name: &str, namespace: Option<&str>) -> bool {
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

pub fn is_system_service_account(name: &str) -> bool {
    name == "default"
}

pub fn is_system_service(name: &str, namespace: Option<&str>) -> bool {
    name == "kubernetes" && namespace == Some("default")
}

/// Static orphan rules table
pub fn get_orphan_rule(kind: &str) -> Option<&'static OrphanRule> {
    static RULES: std::sync::OnceLock<HashMap<&'static str, OrphanRule>> =
        std::sync::OnceLock::new();

    RULES
        .get_or_init(|| {
            let mut rules = HashMap::new();

            // ConfigMap
            rules.insert(
                "ConfigMap",
                OrphanRule {
                    exception: Some(|name, ns| is_exception_config_map(name, ns)),
                    condition: OrphanCondition::NoIncomingRefs,
                },
            );

            // Secret - has exception and special SA token handling
            rules.insert(
                "Secret",
                OrphanRule {
                    exception: Some(|name, ns| is_exception_secret(name, ns)),
                    condition: OrphanCondition::And(&[
                        OrphanCondition::IsServiceAccountToken,
                        OrphanCondition::NoIncomingRefs,
                    ]),
                },
            );

            // Service
            rules.insert(
                "Service",
                OrphanRule {
                    exception: Some(|name, ns| is_system_service(name, ns)),
                    condition: OrphanCondition::NoIncomingFrom(&[
                        "Pod",
                        "Ingress",
                        "ValidatingWebhookConfiguration",
                        "MutatingWebhookConfiguration",
                        "APIService",
                    ]),
                },
            );

            // ServiceAccount
            rules.insert(
                "ServiceAccount",
                OrphanRule {
                    exception: Some(|name, _ns| is_system_service_account(name)),
                    condition: OrphanCondition::NoIncomingFrom(&[
                        "Pod",
                        "Deployment",
                        "StatefulSet",
                        "DaemonSet",
                        "Job",
                        "CronJob",
                        "ReplicaSet",
                        "RoleBinding",
                        "ClusterRoleBinding",
                    ]),
                },
            );

            // PersistentVolumeClaim
            rules.insert(
                "PersistentVolumeClaim",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::NoIncomingFrom(&["Pod", "StatefulSet"]),
                },
            );

            // PersistentVolume
            rules.insert(
                "PersistentVolume",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::NoIncomingFrom(&["PersistentVolumeClaim"]),
                },
            );

            // StorageClass
            rules.insert(
                "StorageClass",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::NoIncomingFrom(&[
                        "PersistentVolumeClaim",
                        "PersistentVolume",
                    ]),
                },
            );

            // ClusterRole
            rules.insert(
                "ClusterRole",
                OrphanRule {
                    exception: Some(|name, _ns| is_exception_cluster_role(name)),
                    condition: OrphanCondition::NoIncomingFrom(&[
                        "RoleBinding",
                        "ClusterRoleBinding",
                    ]),
                },
            );

            // Role
            rules.insert(
                "Role",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::NoIncomingFrom(&["RoleBinding"]),
                },
            );

            // ClusterRoleBinding
            rules.insert(
                "ClusterRoleBinding",
                OrphanRule {
                    exception: Some(|name, _ns| is_exception_cluster_role_binding(name)),
                    condition: OrphanCondition::Or(&[
                        OrphanCondition::NoIncomingFrom(&["ClusterRole"]),
                        OrphanCondition::HasMissingRef("ServiceAccount"),
                    ]),
                },
            );

            // RoleBinding
            rules.insert(
                "RoleBinding",
                OrphanRule {
                    exception: Some(|name, ns| is_exception_role_binding(name, ns)),
                    condition: OrphanCondition::Or(&[
                        OrphanCondition::NoIncomingFrom(&["Role", "ClusterRole"]),
                        OrphanCondition::HasMissingRef("ServiceAccount"),
                    ]),
                },
            );

            // HorizontalPodAutoscaler
            rules.insert(
                "HorizontalPodAutoscaler",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::NoIncomingFrom(&[
                        "Deployment",
                        "StatefulSet",
                        "ReplicaSet",
                    ]),
                },
            );

            // NetworkPolicy
            rules.insert(
                "NetworkPolicy",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::NoIncomingFrom(&["Pod"]),
                },
            );

            // PodDisruptionBudget
            rules.insert(
                "PodDisruptionBudget",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::NoIncomingFrom(&["Pod"]),
                },
            );

            // IngressClass
            rules.insert(
                "IngressClass",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::NoIncomingFrom(&["Ingress"]),
                },
            );

            // Ingress
            rules.insert(
                "Ingress",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::NoIncomingFrom(&["Service"]),
                },
            );

            // ReplicaSet
            rules.insert(
                "ReplicaSet",
                OrphanRule {
                    exception: None,
                    condition: OrphanCondition::And(&[
                        OrphanCondition::NoOwner,
                        OrphanCondition::NoIncomingFrom(&["Pod"]),
                    ]),
                },
            );

            rules
        })
        .get(kind)
}

/// Check if a resource is an orphan using the declarative system
pub fn is_orphan(
    kind: &str,
    name: &str,
    namespace: Option<&str>,
    incoming_refs: &[(EdgeType, &str)],
    labels: Option<&std::collections::HashMap<String, String>>,
    resource_type: Option<&str>,
    missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>,
) -> bool {
    // Get the rule for this kind
    let rule = match get_orphan_rule(kind) {
        Some(r) => r,
        None => return false, // No rule = not orphanable
    };

    // Check exception first
    if let Some(exception_fn) = rule.exception {
        if exception_fn(name, namespace) {
            return false;
        }
    }

    // Evaluate the condition
    let ctx = OrphanContext {
        name,
        namespace,
        incoming_refs,
        labels,
        resource_type,
        missing_refs,
    };

    evaluate(&rule.condition, &ctx)
}
