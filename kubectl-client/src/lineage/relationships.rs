use k8s_openapi::{
    api::{
        admissionregistration::v1::{MutatingWebhookConfiguration, ValidatingWebhookConfiguration},
        apps::v1::{DaemonSet, Deployment, ReplicaSet, StatefulSet},
        autoscaling::v2::HorizontalPodAutoscaler,
        batch::v1::{CronJob, Job},
        core::v1::{Event, PersistentVolume, PersistentVolumeClaim, Pod, Service, ServiceAccount},
        networking::v1::{Ingress, IngressClass, NetworkPolicy},
        policy::v1::PodDisruptionBudget,
        rbac::v1::{ClusterRole, ClusterRoleBinding, Role, RoleBinding},
    },
    kube_aggregator::pkg::apis::apiregistration::v1::APIService,
    serde_json::{from_value, Value},
};

use super::resource_behavior::{ConfigMapBehavior, ResourceBehavior, SecretBehavior};
use super::tree::RelationRef;

/// Extract relationships from a Kubernetes resource based on its kind
/// This is the main dispatcher that deserializes JSON and delegates to trait implementations
pub fn extract_relationships(kind: &str, item: &Value) -> Vec<RelationRef> {
    match kind {
        "Event" => from_value::<Event>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "Ingress" => from_value::<Ingress>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "IngressClass" => from_value::<IngressClass>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "Pod" => from_value::<Pod>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "ClusterRole" => from_value::<ClusterRole>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "Role" => from_value::<Role>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "PersistentVolumeClaim" => from_value::<PersistentVolumeClaim>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "PersistentVolume" => from_value::<PersistentVolume>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "ClusterRoleBinding" => from_value::<ClusterRoleBinding>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "Deployment" => from_value::<Deployment>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "ReplicaSet" => from_value::<ReplicaSet>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "StatefulSet" => from_value::<StatefulSet>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "DaemonSet" => from_value::<DaemonSet>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "Job" => from_value::<Job>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "CronJob" => from_value::<CronJob>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "HorizontalPodAutoscaler" => from_value::<HorizontalPodAutoscaler>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "Service" => from_value::<Service>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "NetworkPolicy" => from_value::<NetworkPolicy>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "RoleBinding" => from_value::<RoleBinding>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "PodDisruptionBudget" => from_value::<PodDisruptionBudget>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "ServiceAccount" => from_value::<ServiceAccount>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "ValidatingWebhookConfiguration" => {
            from_value::<ValidatingWebhookConfiguration>(item.clone())
                .ok()
                .map(|typed| typed.extract_relationships(None))
                .unwrap_or_default()
        }
        "MutatingWebhookConfiguration" => from_value::<MutatingWebhookConfiguration>(item.clone())
            .ok()
            .map(|typed| typed.extract_relationships(None))
            .unwrap_or_default(),
        "APIService" => from_value::<APIService>(item.clone())
            .ok()
            .map(|typed: APIService| typed.extract_relationships(None))
            .unwrap_or_default(),
        _ => Vec::new(),
    }
}

/// Determine if a resource is orphaned based on its kind and graph context
/// A resource is orphaned if it should have consumers but doesn't have any incoming references
/// This dispatcher routes to the appropriate trait implementation
pub fn is_resource_orphan(
    kind: &str,
    name: &str,
    namespace: Option<&str>,
    incoming_refs: &[(super::tree::EdgeType, &str)],
    labels: Option<&std::collections::HashMap<String, String>>,
    resource_type: Option<&str>,
) -> bool {
    match kind {
        // Core resources with clear consumer relationships
        "ConfigMap" | "configmap" => ConfigMapBehavior::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        "Secret" | "secret" => SecretBehavior::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        "Service" | "service" => Service::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        "ServiceAccount" | "serviceaccount" => ServiceAccount::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        // Storage resources
        "PersistentVolumeClaim" | "persistentvolumeclaim" => {
            PersistentVolumeClaim::is_orphan(name, namespace, incoming_refs, labels, resource_type)
        }
        "PersistentVolume" | "persistentvolume" => PersistentVolume::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        // RBAC resources
        "Role" | "role" => Role::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        "ClusterRole" | "clusterrole" => ClusterRole::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        "RoleBinding" | "rolebinding" => RoleBinding::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        "ClusterRoleBinding" | "clusterrolebinding" => {
            ClusterRoleBinding::is_orphan(name, namespace, incoming_refs, labels, resource_type)
        }
        // Policy resources with selector-based relationships
        "NetworkPolicy" | "networkpolicy" => NetworkPolicy::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        "PodDisruptionBudget" | "poddisruptionbudget" => {
            PodDisruptionBudget::is_orphan(name, namespace, incoming_refs, labels, resource_type)
        }
        // Networking resources
        "IngressClass" | "ingressclass" => IngressClass::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        "Ingress" | "ingress" => Ingress::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        // Autoscaling
        "HorizontalPodAutoscaler" | "horizontalpodautoscaler" => {
            HorizontalPodAutoscaler::is_orphan(name, namespace, incoming_refs, labels, resource_type)
        }
        // Workload helpers
        "ReplicaSet" | "replicaset" => ReplicaSet::is_orphan(name, namespace, incoming_refs, labels, resource_type),
        _ => false, // Other resource types are never considered orphans
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use k8s_openapi::{api::core::v1::Pod, serde_json::json};

    #[test]
    fn test_extract_event_relationships() {
        let event_json = json!({
            "involvedObject": {
                "kind": "Pod",
                "name": "test-pod",
                "namespace": "default"
            }
        });

        let event: Event = from_value(event_json.clone()).unwrap();
        let relations = event.extract_relationships(None);
        assert_eq!(relations.len(), 1);
        assert_eq!(relations[0].kind, "Pod");
        assert_eq!(relations[0].name, "test-pod");

        // Also test via dispatcher
        let relations_via_dispatcher = extract_relationships("Event", &event_json);
        assert_eq!(relations_via_dispatcher.len(), 1);
        assert_eq!(relations_via_dispatcher[0].kind, "Pod");
    }

    #[test]
    fn test_extract_pod_relationships() {
        let pod_json = json!({
            "metadata": {
                "namespace": "default"
            },
            "spec": {
                "nodeName": "node-1",
                "serviceAccountName": "default",
                "containers": []
            }
        });

        let pod: Pod = from_value(pod_json.clone()).unwrap();
        let relations = pod.extract_relationships(None);
        assert_eq!(relations.len(), 2);
        assert!(relations.iter().any(|r| r.kind == "Node"));
        assert!(relations.iter().any(|r| r.kind == "ServiceAccount"));

        // Also test via dispatcher
        let relations_via_dispatcher = extract_relationships("Pod", &pod_json);
        assert_eq!(relations_via_dispatcher.len(), 2);
    }

    #[test]
    fn test_configmap_orphan_detection() {
        use super::super::tree::EdgeType;

        // ConfigMap with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(ConfigMapBehavior::is_orphan("test-cm", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("ConfigMap", "test-cm", Some("default"), &no_refs, None, None));

        // ConfigMap with incoming References from Pod is not orphan
        let with_ref = vec![(EdgeType::References, "Pod")];
        assert!(!ConfigMapBehavior::is_orphan("test-cm", Some("default"), &with_ref, None, None));
        assert!(!is_resource_orphan("ConfigMap", "test-cm", Some("default"), &with_ref, None, None));

        // ConfigMap with only Owns edge is orphan (shouldn't happen but test it)
        let only_owns = vec![(EdgeType::Owns, "Pod")];
        assert!(ConfigMapBehavior::is_orphan("test-cm", Some("default"), &only_owns, None, None));
        assert!(is_resource_orphan("ConfigMap", "test-cm", Some("default"), &only_owns, None, None));
    }

    #[test]
    fn test_service_orphan_detection() {
        use super::super::tree::EdgeType;

        // Service with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(Service::is_orphan("test-svc", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("Service", "test-svc", Some("default"), &no_refs, None, None));

        // Service with incoming References from Pod is not orphan
        let with_pod = vec![(EdgeType::References, "Pod")];
        assert!(!Service::is_orphan("test-svc", Some("default"), &with_pod, None, None));
        assert!(!is_resource_orphan("Service", "test-svc", Some("default"), &with_pod, None, None));

        // Service with incoming References from Ingress is not orphan
        let with_ingress = vec![(EdgeType::References, "Ingress")];
        assert!(!Service::is_orphan("test-svc", Some("default"), &with_ingress, None, None));
        assert!(!is_resource_orphan("Service", "test-svc", Some("default"), &with_ingress, None, None));

        // Service with References from other resources (not Pod/Ingress) is orphan
        let with_other = vec![(EdgeType::References, "ConfigMap")];
        assert!(Service::is_orphan("test-svc", Some("default"), &with_other, None, None));
        assert!(is_resource_orphan("Service", "test-svc", Some("default"), &with_other, None, None));
    }

    #[test]
    fn test_pvc_orphan_detection() {
        use super::super::tree::EdgeType;

        // PVC with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(PersistentVolumeClaim::is_orphan("test-pvc", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &no_refs, None, None));

        // PVC with incoming References from Pod is not orphan
        let with_pod = vec![(EdgeType::References, "Pod")];
        assert!(!PersistentVolumeClaim::is_orphan("test-pvc", Some("default"), &with_pod, None, None));
        assert!(!is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &with_pod, None, None));

        // PVC with incoming References from StatefulSet is not orphan
        let with_sts = vec![(EdgeType::References, "StatefulSet")];
        assert!(!PersistentVolumeClaim::is_orphan("test-pvc", Some("default"), &with_sts, None, None));
        assert!(!is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &with_sts, None, None));

        // PVC with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "ConfigMap")];
        assert!(PersistentVolumeClaim::is_orphan("test-pvc", Some("default"), &with_other, None, None));
        assert!(is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &with_other, None, None));
    }

    #[test]
    fn test_serviceaccount_orphan_detection() {
        use super::super::tree::EdgeType;

        // ServiceAccount with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(ServiceAccount::is_orphan("test-sa", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &no_refs, None, None));

        // ServiceAccount with incoming References from Pod is not orphan
        let with_pod = vec![(EdgeType::References, "Pod")];
        assert!(!ServiceAccount::is_orphan("test-sa", Some("default"), &with_pod, None, None));
        assert!(!is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &with_pod, None, None));

        // ServiceAccount with incoming References from RoleBinding is not orphan
        let with_rb = vec![(EdgeType::References, "RoleBinding")];
        assert!(!ServiceAccount::is_orphan("test-sa", Some("default"), &with_rb, None, None));
        assert!(!is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &with_rb, None, None));

        // ServiceAccount with incoming References from ClusterRoleBinding is not orphan
        let with_crb = vec![(EdgeType::References, "ClusterRoleBinding")];
        assert!(!ServiceAccount::is_orphan("test-sa", Some("default"), &with_crb, None, None));
        assert!(!is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &with_crb, None, None));

        // ServiceAccount with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "ConfigMap")];
        assert!(ServiceAccount::is_orphan("test-sa", Some("default"), &with_other, None, None));
        assert!(is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &with_other, None, None));
    }

    #[test]
    fn test_role_orphan_detection() {
        use super::super::tree::EdgeType;

        // Role with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(Role::is_orphan("test-role", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("Role", "test-role", Some("default"), &no_refs, None, None));

        // Role with incoming References from RoleBinding is not orphan
        let with_rb = vec![(EdgeType::References, "RoleBinding")];
        assert!(!Role::is_orphan("test-role", Some("default"), &with_rb, None, None));
        assert!(!is_resource_orphan("Role", "test-role", Some("default"), &with_rb, None, None));

        // Role with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "Pod")];
        assert!(Role::is_orphan("test-role", Some("default"), &with_other, None, None));
        assert!(is_resource_orphan("Role", "test-role", Some("default"), &with_other, None, None));

        // Role with only Owns edge is orphan
        let only_owns = vec![(EdgeType::Owns, "RoleBinding")];
        assert!(Role::is_orphan("test-role", Some("default"), &only_owns, None, None));
        assert!(is_resource_orphan("Role", "test-role", Some("default"), &only_owns, None, None));
    }

    #[test]
    fn test_clusterrole_orphan_detection() {
        use super::super::tree::EdgeType;
        use std::collections::HashMap;

        // ClusterRole with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(ClusterRole::is_orphan("test-role", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("ClusterRole", "test-clusterrole", None, &no_refs, None, None));

        // ClusterRole with incoming References from RoleBinding is not orphan
        let with_rb = vec![(EdgeType::References, "RoleBinding")];
        assert!(!ClusterRole::is_orphan("test-role", Some("default"), &with_rb, None, None));
        assert!(!is_resource_orphan("ClusterRole", "test-clusterrole", None, &with_rb, None, None));

        // ClusterRole with incoming References from ClusterRoleBinding is not orphan
        let with_crb = vec![(EdgeType::References, "ClusterRoleBinding")];
        assert!(!ClusterRole::is_orphan("test-clusterrole", None, &with_crb, None, None));
        assert!(!is_resource_orphan("ClusterRole", "test-clusterrole", None, &with_crb, None, None));

        // ClusterRole with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "Pod")];
        assert!(ClusterRole::is_orphan("test-role", Some("default"), &with_other, None, None));
        assert!(is_resource_orphan("ClusterRole", "test-clusterrole", None, &with_other, None, None));

        // ClusterRole with only Owns edge is orphan
        let only_owns = vec![(EdgeType::Owns, "ClusterRoleBinding")];
        assert!(ClusterRole::is_orphan("test-role", Some("default"), &only_owns, None, None));
        assert!(is_resource_orphan("ClusterRole", "test-clusterrole", None, &only_owns, None, None));

        // ClusterRole with aggregation label is not orphan (even with no refs)
        let mut labels = HashMap::new();
        labels.insert("rbac.authorization.k8s.io/aggregate-to-admin".to_string(), "true".to_string());
        assert!(!ClusterRole::is_orphan("test-clusterrole", None, &no_refs, Some(&labels), None));
        assert!(!is_resource_orphan("ClusterRole", "test-clusterrole", None, &no_refs, Some(&labels), None));

        // ClusterRole with non-aggregation labels but no refs is still orphan
        let mut other_labels = HashMap::new();
        other_labels.insert("app".to_string(), "my-app".to_string());
        assert!(ClusterRole::is_orphan("test-clusterrole", None, &no_refs, Some(&other_labels), None));
        assert!(is_resource_orphan("ClusterRole", "test-clusterrole", None, &no_refs, Some(&other_labels), None));
    }

    #[test]
    fn test_is_resource_orphan_dispatcher() {
        use super::super::tree::EdgeType;

        let no_refs: Vec<(EdgeType, &str)> = vec![];

        // Test supported resource types
        assert!(is_resource_orphan("ConfigMap", "test-cm", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("Secret", "test-secret", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("Service", "test-svc", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("Role", "test-role", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("ClusterRole", "test-clusterrole", None, &no_refs, None, None));

        // Test case-insensitive matching
        assert!(is_resource_orphan("configmap", "test", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("secret", "test", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("role", "test", Some("default"), &no_refs, None, None));
        assert!(is_resource_orphan("clusterrole", "test", None, &no_refs, None, None));

        // Test unsupported resource types (should never be orphans)
        assert!(!is_resource_orphan("Pod", "test", Some("default"), &no_refs, None, None));
        assert!(!is_resource_orphan("Deployment", "test", Some("default"), &no_refs, None, None));
        assert!(!is_resource_orphan("Node", "test-node", None, &no_refs, None, None));
    }

    #[test]
    fn test_system_resource_exceptions() {
        use super::super::tree::EdgeType;

        let no_refs: Vec<(EdgeType, &str)> = vec![];

        // System ClusterRoles are never orphans
        assert!(!is_resource_orphan("ClusterRole", "admin", None, &no_refs, None, None));
        assert!(!is_resource_orphan("ClusterRole", "edit", None, &no_refs, None, None));
        assert!(!is_resource_orphan("ClusterRole", "view", None, &no_refs, None, None));
        assert!(!is_resource_orphan("ClusterRole", "sudoer", None, &no_refs, None, None));
        assert!(!is_resource_orphan("ClusterRole", "cluster-admin", None, &no_refs, None, None));
        assert!(!is_resource_orphan("ClusterRole", "system:node", None, &no_refs, None, None));
        assert!(!is_resource_orphan("ClusterRole", "system:metrics-server", None, &no_refs, None, None));

        // Non-system ClusterRole with no refs is orphan
        assert!(is_resource_orphan("ClusterRole", "my-custom-role", None, &no_refs, None, None));

        // Default ServiceAccount is never orphan (in any namespace)
        assert!(!is_resource_orphan("ServiceAccount", "default", Some("default"), &no_refs, None, None));
        assert!(!is_resource_orphan("ServiceAccount", "default", Some("kube-system"), &no_refs, None, None));
        assert!(!is_resource_orphan("ServiceAccount", "default", Some("my-namespace"), &no_refs, None, None));

        // ServiceAccounts in system namespaces are never orphans
        assert!(!is_resource_orphan("ServiceAccount", "my-sa", Some("kube-system"), &no_refs, None, None));
        assert!(!is_resource_orphan("ServiceAccount", "my-sa", Some("kube-public"), &no_refs, None, None));
        assert!(!is_resource_orphan("ServiceAccount", "my-sa", Some("kube-node-lease"), &no_refs, None, None));

        // Non-system ServiceAccount with no refs is orphan
        assert!(is_resource_orphan("ServiceAccount", "my-sa", Some("default"), &no_refs, None, None));

        // System ConfigMaps are never orphans
        assert!(!is_resource_orphan("ConfigMap", "kube-root-ca.crt", Some("default"), &no_refs, None, None));
        assert!(!is_resource_orphan("ConfigMap", "extension-apiserver-authentication", Some("kube-system"), &no_refs, None, None));
        assert!(!is_resource_orphan("ConfigMap", "my-cm", Some("kube-system"), &no_refs, None, None));
        assert!(!is_resource_orphan("ConfigMap", "my-cm", Some("kube-public"), &no_refs, None, None));

        // Non-system ConfigMap with no refs is orphan
        assert!(is_resource_orphan("ConfigMap", "my-cm", Some("default"), &no_refs, None, None));

        // Secrets in system namespaces are never orphans
        assert!(!is_resource_orphan("Secret", "my-secret", Some("kube-system"), &no_refs, None, None));
        assert!(!is_resource_orphan("Secret", "my-secret", Some("kube-public"), &no_refs, None, None));
        assert!(!is_resource_orphan("Secret", "my-secret", Some("kube-node-lease"), &no_refs, None, None));

        // Service account token secrets are never orphans (checked via label or type)
        let mut sa_labels = std::collections::HashMap::new();
        sa_labels.insert("kubernetes.io/service-account.name".to_string(), "default".to_string());
        assert!(!is_resource_orphan("Secret", "token-secret", Some("default"), &no_refs, Some(&sa_labels), None));

        // Service account token secrets detected by type
        assert!(!is_resource_orphan("Secret", "token-secret", Some("default"), &no_refs, None, Some("kubernetes.io/service-account-token")));

        // Non-system Secret with no refs is orphan
        assert!(is_resource_orphan("Secret", "my-secret", Some("default"), &no_refs, None, None));

        // System Services are never orphans
        assert!(!is_resource_orphan("Service", "kubernetes", Some("default"), &no_refs, None, None));
        assert!(!is_resource_orphan("Service", "my-service", Some("kube-system"), &no_refs, None, None));
        assert!(!is_resource_orphan("Service", "my-service", Some("kube-public"), &no_refs, None, None));

        // Non-system Service with no refs is orphan
        assert!(is_resource_orphan("Service", "my-service", Some("default"), &no_refs, None, None));
    }
}
