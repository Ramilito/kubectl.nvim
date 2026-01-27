use super::tree::EdgeType;
use std::collections::HashMap;

/// Declarative exception pattern for matching resource names
pub struct ExceptionPattern {
    pub exact_names: &'static [&'static str],
    pub name_prefixes: &'static [&'static str],
    pub name_suffixes: &'static [&'static str],
    pub namespace_prefixes: &'static [&'static str],
    pub namespace_names: &'static [(&'static str, &'static [&'static str])],
}

impl ExceptionPattern {
    pub fn matches(&self, name: &str, namespace: Option<&str>) -> bool {
        // Check exact name match
        if self.exact_names.iter().any(|&n| n == name) {
            return true;
        }

        // Check name prefix match
        if self
            .name_prefixes
            .iter()
            .any(|&prefix| name.starts_with(prefix))
        {
            return true;
        }

        // Check name suffix match
        if self
            .name_suffixes
            .iter()
            .any(|&suffix| name.ends_with(suffix))
        {
            return true;
        }

        // Check namespace prefix match
        if let Some(ns) = namespace {
            if self
                .namespace_prefixes
                .iter()
                .any(|&prefix| ns.starts_with(prefix))
            {
                return true;
            }

            // Check namespace-specific name matches
            for (ns_name, names) in self.namespace_names {
                if ns == *ns_name && names.iter().any(|&n| n == name) {
                    return true;
                }
            }
        }

        false
    }
}

/// Exception specification for orphan rules
pub enum ExceptionSpec {
    Pattern(&'static ExceptionPattern),
    Function(fn(&str, Option<&str>) -> bool),
}

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
pub struct OrphanContext<'a> {
    pub incoming_refs: &'a [(EdgeType, &'a str)],
    pub labels: Option<&'a HashMap<String, String>>,
    pub resource_type: Option<&'a str>,
    pub missing_refs: Option<&'a HashMap<String, Vec<String>>>,
}

/// Orphan rule for a resource type
pub struct OrphanRule {
    pub exception: Option<ExceptionSpec>,
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

/// Exception function for RoleBinding still used in patterns
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

// Static exception patterns - declarative alternatives to exception functions

pub static CLUSTER_ROLE_EXCEPTION_PATTERN: ExceptionPattern = ExceptionPattern {
    exact_names: &[
        "admin",
        "alert-routing-edit",
        "cloud-provider",
        "cluster-admin",
        "cluster-debugger",
        "edit",
        "eks:extension-metrics-apiserver",
        "global-operators-admin",
        "global-operators-edit",
        "global-operators-view",
        "monitoring-edit",
        "monitoring-rules-edit",
        "monitoring-rules-view",
        "olm-operators-admin",
        "olm-operators-edit",
        "olm-operators-view",
        "openshift-cluster-monitoring-admin",
        "openshift-cluster-monitoring-edit",
        "openshift-cluster-monitoring-view",
        "openshift-csi-main-attacher-role",
        "openshift-csi-main-provisioner-role",
        "openshift-csi-main-resizer-role",
        "openshift-csi-main-snapshotter-role",
        "openshift-csi-provisioner-configmap-and-secret-reader-role",
        "openshift-csi-provisioner-volumeattachment-reader-role",
        "openshift-csi-provisioner-volumesnapshot-reader-role",
        "openshift-csi-resizer-infrastructure-reader-role",
        "openshift-csi-resizer-storageclass-reader-role",
        "resource-metrics-server-resources",
        "storage-admin",
        "sudoer",
        "system:aggregate-to-admin",
        "system:aggregate-to-edit",
        "system:aggregate-to-view",
        "system:aggregated-metrics-reader",
        "system:auth-delegator",
        "system:build-strategy-custom",
        "system:certificates.k8s.io:certificatesigningrequests:nodeclient",
        "system:certificates.k8s.io:certificatesigningrequests:selfnodeclient",
        "system:certificates.k8s.io:kube-apiserver-client-approver",
        "system:certificates.k8s.io:kube-apiserver-client-kubelet-approver",
        "system:certificates.k8s.io:kubelet-serving-approver",
        "system:certificates.k8s.io:legacy-unknown-approver",
        "system:controller:cloud-node-controller",
        "system:controller:glbc",
        "system:heapster",
        "system:image-auditor",
        "system:image-pusher",
        "system:image-signer",
        "system:kube-aggregator",
        "system:kubelet-api-admin",
        "system:metrics-server-aggregated-reader",
        "system:node",
        "system:node-bootstrapper",
        "system:node-problem-detector",
        "system:node-reader",
        "system:openshift:aggregate-snapshots-to-storage-admin",
        "system:openshift:aggregate-to-storage-admin",
        "system:openshift:scc:hostaccess",
        "system:openshift:scc:hostmount",
        "system:openshift:scc:hostnetwork",
        "system:openshift:scc:nonroot",
        "system:openshift:scc:nonroot-v2",
        "system:openshift:scc:privileged",
        "system:openshift:scc:restricted",
        "system:openshift:templateservicebroker-client",
        "system:persistent-volume-provisioner",
        "system:router",
        "system:sdn-manager",
        "view",
    ],
    name_prefixes: &[],
    name_suffixes: &[],
    namespace_prefixes: &[],
    namespace_names: &[],
};

pub static CLUSTER_ROLE_BINDING_EXCEPTION_PATTERN: ExceptionPattern = ExceptionPattern {
    exact_names: &[
        "kubeadm:kubelet-bootstrap",
        "kubeadm:node-autoapprove-bootstrap",
        "kubeadm:node-autoapprove-certificate-rotation",
        "system:controller:route-controller",
        "system:kube-dns",
        "system:node",
        "event-exporter-rb",
        "kubelet-bootstrap",
        "kubelet-bootstrap-node-bootstrapper",
        "kubelet-cluster-admin",
        "kubelet-nodepool-bootstrapper",
        "kubelet-user-npd-binding",
        "metrics-server-nanny:system:auth-delegator",
        "metrics-server:system:auth-delegator",
        "npd-binding",
        "system:controller:horizontal-pod-autoscaler",
        "system:controller:selinux-warning-controller",
        "system:konnectivity-server",
    ],
    name_prefixes: &[],
    name_suffixes: &[],
    namespace_prefixes: &[],
    namespace_names: &[],
};

pub static CONFIG_MAP_EXCEPTION_PATTERN: ExceptionPattern = ExceptionPattern {
    exact_names: &[
        "kube-root-ca.crt",
        "openshift-service-ca.crt",
    ],
    name_prefixes: &[],
    name_suffixes: &[],
    namespace_prefixes: &["openshift-"],
    namespace_names: &[
        ("kube-system", &[
            "amazon-vpc-cni",
            "aws-auth",
            "bootstrap",
            "cluster-autoscaler-status",
            "cluster-config-v1",
            "cluster-dns",
            "cluster-kubestore",
            "clustermetrics",
            "coredns-autoscaler",
            "extension-apiserver-authentication",
            "gke-common-webhook-heartbeat",
            "ingress-uid",
            "konnectivity-agent-autoscaler-config",
            "kube-apiserver-legacy-service-account-token-tracking",
            "kube-dns-autoscaler",
            "kube-proxy",
            "kube-proxy-config",
            "kubeadm-config",
            "kubedns-config-images",
            "kubelet-config",
            "overlay-upgrade-data",
            "root-ca",
            "efficiency-daemon-config",
            "metrics-agent-linux-config-images",
            "metrics-agent-windows-config-images",
            "nvidia-metrics-collector-config-map",
        ]),
        ("kube-public", &["cluster-info"]),
        ("gmp-system", &[
            "config-images",
            "webhook-ca",
            "rule-evaluator",
            "rules-generated",
        ]),
        ("kubernetes-dashboard", &["kubernetes-dashboard-settings"]),
        ("gke-managed-system", &["dcgm-exporter-metrics"]),
    ],
};

pub static SECRET_EXCEPTION_PATTERN: ExceptionPattern = ExceptionPattern {
    exact_names: &[],
    name_prefixes: &["bootstrap-token-"],
    name_suffixes: &[".node-password.k3s"],
    namespace_prefixes: &["openshift-"],
    namespace_names: &[
        ("kube-system", &[
            "k3s-serving",
            "kube-cloud-cfg",
            "kubeadmin",
        ]),
        ("kubernetes-dashboard", &[
            "kubernetes-dashboard-certs",
            "kubernetes-dashboard-csrf",
            "kubernetes-dashboard-key-holder",
        ]),
        ("gmp-system", &[
            "alertmanager",
            "rules",
            "webhook-tls",
        ]),
    ],
};

pub static SERVICE_ACCOUNT_EXCEPTION_PATTERN: ExceptionPattern = ExceptionPattern {
    exact_names: &["default"],
    name_prefixes: &[],
    name_suffixes: &[],
    namespace_prefixes: &[],
    namespace_names: &[],
};

pub static SERVICE_EXCEPTION_PATTERN: ExceptionPattern = ExceptionPattern {
    exact_names: &[],
    name_prefixes: &[],
    name_suffixes: &[],
    namespace_prefixes: &[],
    namespace_names: &[("default", &["kubernetes"])],
};
