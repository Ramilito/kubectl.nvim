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
    incoming_refs: &[(super::tree::EdgeType, &str)],
) -> bool {
    match kind {
        // Core resources with clear consumer relationships
        "ConfigMap" | "configmap" => ConfigMapBehavior::is_orphan(incoming_refs),
        "Secret" | "secret" => SecretBehavior::is_orphan(incoming_refs),
        "Service" | "service" => Service::is_orphan(incoming_refs),
        "ServiceAccount" | "serviceaccount" => ServiceAccount::is_orphan(incoming_refs),
        // Storage resources
        "PersistentVolumeClaim" | "persistentvolumeclaim" => {
            PersistentVolumeClaim::is_orphan(incoming_refs)
        }
        "PersistentVolume" | "persistentvolume" => PersistentVolume::is_orphan(incoming_refs),
        // RBAC resources
        "Role" | "role" => Role::is_orphan(incoming_refs),
        "ClusterRole" | "clusterrole" => ClusterRole::is_orphan(incoming_refs),
        "RoleBinding" | "rolebinding" => RoleBinding::is_orphan(incoming_refs),
        "ClusterRoleBinding" | "clusterrolebinding" => {
            ClusterRoleBinding::is_orphan(incoming_refs)
        }
        // Policy resources with selector-based relationships
        "NetworkPolicy" | "networkpolicy" => NetworkPolicy::is_orphan(incoming_refs),
        "PodDisruptionBudget" | "poddisruptionbudget" => {
            PodDisruptionBudget::is_orphan(incoming_refs)
        }
        // Networking resources
        "IngressClass" | "ingressclass" => IngressClass::is_orphan(incoming_refs),
        "Ingress" | "ingress" => Ingress::is_orphan(incoming_refs),
        // Autoscaling
        "HorizontalPodAutoscaler" | "horizontalpodautoscaler" => {
            HorizontalPodAutoscaler::is_orphan(incoming_refs)
        }
        // Workload helpers
        "ReplicaSet" | "replicaset" => ReplicaSet::is_orphan(incoming_refs),
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
        assert!(ConfigMapBehavior::is_orphan(&no_refs));
        assert!(is_resource_orphan("ConfigMap", &no_refs));

        // ConfigMap with incoming References from Pod is not orphan
        let with_ref = vec![(EdgeType::References, "Pod")];
        assert!(!ConfigMapBehavior::is_orphan(&with_ref));
        assert!(!is_resource_orphan("ConfigMap", &with_ref));

        // ConfigMap with only Owns edge is orphan (shouldn't happen but test it)
        let only_owns = vec![(EdgeType::Owns, "Pod")];
        assert!(ConfigMapBehavior::is_orphan(&only_owns));
        assert!(is_resource_orphan("ConfigMap", &only_owns));
    }

    #[test]
    fn test_service_orphan_detection() {
        use super::super::tree::EdgeType;

        // Service with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(Service::is_orphan(&no_refs));
        assert!(is_resource_orphan("Service", &no_refs));

        // Service with incoming References from Pod is not orphan
        let with_pod = vec![(EdgeType::References, "Pod")];
        assert!(!Service::is_orphan(&with_pod));
        assert!(!is_resource_orphan("Service", &with_pod));

        // Service with incoming References from Ingress is not orphan
        let with_ingress = vec![(EdgeType::References, "Ingress")];
        assert!(!Service::is_orphan(&with_ingress));
        assert!(!is_resource_orphan("Service", &with_ingress));

        // Service with References from other resources (not Pod/Ingress) is orphan
        let with_other = vec![(EdgeType::References, "ConfigMap")];
        assert!(Service::is_orphan(&with_other));
        assert!(is_resource_orphan("Service", &with_other));
    }

    #[test]
    fn test_pvc_orphan_detection() {
        use super::super::tree::EdgeType;

        // PVC with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(PersistentVolumeClaim::is_orphan(&no_refs));
        assert!(is_resource_orphan("PersistentVolumeClaim", &no_refs));

        // PVC with incoming References from Pod is not orphan
        let with_pod = vec![(EdgeType::References, "Pod")];
        assert!(!PersistentVolumeClaim::is_orphan(&with_pod));
        assert!(!is_resource_orphan("PersistentVolumeClaim", &with_pod));

        // PVC with incoming References from StatefulSet is not orphan
        let with_sts = vec![(EdgeType::References, "StatefulSet")];
        assert!(!PersistentVolumeClaim::is_orphan(&with_sts));
        assert!(!is_resource_orphan("PersistentVolumeClaim", &with_sts));

        // PVC with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "ConfigMap")];
        assert!(PersistentVolumeClaim::is_orphan(&with_other));
        assert!(is_resource_orphan("PersistentVolumeClaim", &with_other));
    }

    #[test]
    fn test_serviceaccount_orphan_detection() {
        use super::super::tree::EdgeType;

        // ServiceAccount with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(ServiceAccount::is_orphan(&no_refs));
        assert!(is_resource_orphan("ServiceAccount", &no_refs));

        // ServiceAccount with incoming References from Pod is not orphan
        let with_pod = vec![(EdgeType::References, "Pod")];
        assert!(!ServiceAccount::is_orphan(&with_pod));
        assert!(!is_resource_orphan("ServiceAccount", &with_pod));

        // ServiceAccount with incoming References from RoleBinding is not orphan
        let with_rb = vec![(EdgeType::References, "RoleBinding")];
        assert!(!ServiceAccount::is_orphan(&with_rb));
        assert!(!is_resource_orphan("ServiceAccount", &with_rb));

        // ServiceAccount with incoming References from ClusterRoleBinding is not orphan
        let with_crb = vec![(EdgeType::References, "ClusterRoleBinding")];
        assert!(!ServiceAccount::is_orphan(&with_crb));
        assert!(!is_resource_orphan("ServiceAccount", &with_crb));

        // ServiceAccount with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "ConfigMap")];
        assert!(ServiceAccount::is_orphan(&with_other));
        assert!(is_resource_orphan("ServiceAccount", &with_other));
    }

    #[test]
    fn test_role_orphan_detection() {
        use super::super::tree::EdgeType;

        // Role with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(Role::is_orphan(&no_refs));
        assert!(is_resource_orphan("Role", &no_refs));

        // Role with incoming References from RoleBinding is not orphan
        let with_rb = vec![(EdgeType::References, "RoleBinding")];
        assert!(!Role::is_orphan(&with_rb));
        assert!(!is_resource_orphan("Role", &with_rb));

        // Role with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "Pod")];
        assert!(Role::is_orphan(&with_other));
        assert!(is_resource_orphan("Role", &with_other));

        // Role with only Owns edge is orphan
        let only_owns = vec![(EdgeType::Owns, "RoleBinding")];
        assert!(Role::is_orphan(&only_owns));
        assert!(is_resource_orphan("Role", &only_owns));
    }

    #[test]
    fn test_clusterrole_orphan_detection() {
        use super::super::tree::EdgeType;

        // ClusterRole with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(ClusterRole::is_orphan(&no_refs));
        assert!(is_resource_orphan("ClusterRole", &no_refs));

        // ClusterRole with incoming References from RoleBinding is not orphan
        let with_rb = vec![(EdgeType::References, "RoleBinding")];
        assert!(!ClusterRole::is_orphan(&with_rb));
        assert!(!is_resource_orphan("ClusterRole", &with_rb));

        // ClusterRole with incoming References from ClusterRoleBinding is not orphan
        let with_crb = vec![(EdgeType::References, "ClusterRoleBinding")];
        assert!(!ClusterRole::is_orphan(&with_crb));
        assert!(!is_resource_orphan("ClusterRole", &with_crb));

        // ClusterRole with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "Pod")];
        assert!(ClusterRole::is_orphan(&with_other));
        assert!(is_resource_orphan("ClusterRole", &with_other));

        // ClusterRole with only Owns edge is orphan
        let only_owns = vec![(EdgeType::Owns, "ClusterRoleBinding")];
        assert!(ClusterRole::is_orphan(&only_owns));
        assert!(is_resource_orphan("ClusterRole", &only_owns));
    }

    #[test]
    fn test_is_resource_orphan_dispatcher() {
        use super::super::tree::EdgeType;

        let no_refs: Vec<(EdgeType, &str)> = vec![];

        // Test supported resource types
        assert!(is_resource_orphan("ConfigMap", &no_refs));
        assert!(is_resource_orphan("Secret", &no_refs));
        assert!(is_resource_orphan("Service", &no_refs));
        assert!(is_resource_orphan("PersistentVolumeClaim", &no_refs));
        assert!(is_resource_orphan("ServiceAccount", &no_refs));
        assert!(is_resource_orphan("Role", &no_refs));
        assert!(is_resource_orphan("ClusterRole", &no_refs));

        // Test case-insensitive matching
        assert!(is_resource_orphan("configmap", &no_refs));
        assert!(is_resource_orphan("secret", &no_refs));
        assert!(is_resource_orphan("role", &no_refs));
        assert!(is_resource_orphan("clusterrole", &no_refs));

        // Test unsupported resource types (should never be orphans)
        assert!(!is_resource_orphan("Pod", &no_refs));
        assert!(!is_resource_orphan("Deployment", &no_refs));
        assert!(!is_resource_orphan("Node", &no_refs));
    }
}
