use k8s_openapi::serde_json::Value;

use super::registry;
use super::tree::RelationRef;

/// Extract relationships from a Kubernetes resource based on its kind
/// Uses the centralized resource handler registry
pub fn extract_relationships(kind: &str, item: &Value) -> Vec<RelationRef> {
    match registry::get_handler(kind) {
        Some(handler) => (handler.extract_relations)(item, None),
        None => Vec::new(),
    }
}

/// Determine if a resource is orphaned based on its kind and graph context
/// A resource is orphaned if it should have consumers but doesn't have any incoming references
/// Uses the centralized resource handler registry
pub fn is_resource_orphan(
    kind: &str,
    name: &str,
    namespace: Option<&str>,
    incoming_refs: &[(super::tree::EdgeType, &str)],
    labels: Option<&std::collections::HashMap<String, String>>,
    resource_type: Option<&str>,
    missing_refs: Option<&std::collections::HashMap<String, Vec<String>>>,
) -> bool {
    // Get the handler for this resource kind
    let Some(handler) = registry::get_handler(kind) else {
        return false; // Unknown resource types are never orphans
    };

    // If no orphan rule is defined, the resource is never an orphan
    let Some(rule) = handler.orphan_rule else {
        return false;
    };

    // Check exception first (e.g., system resources, default service accounts)
    // If this resource is an exception (system resource), it's never an orphan
    if let Some(exception_fn) = rule.exception {
        if exception_fn(name, namespace) {
            return false;
        }
    }

    // Evaluate the orphan condition
    let ctx = super::orphan_rules::OrphanContext {
        name,
        namespace,
        incoming_refs,
        labels,
        resource_type,
        missing_refs,
    };

    super::orphan_rules::evaluate(&rule.condition, &ctx)
}

#[cfg(test)]
mod tests {
    use super::*;
    use k8s_openapi::serde_json::json;

    #[test]
    fn test_extract_event_relationships() {
        let event_json = json!({
            "involvedObject": {
                "kind": "Pod",
                "name": "test-pod",
                "namespace": "default"
            }
        });

        let relations = extract_relationships("Event", &event_json);
        assert_eq!(relations.len(), 1);
        assert_eq!(relations[0].kind, "Pod");
        assert_eq!(relations[0].name, "test-pod");
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

        let relations = extract_relationships("Pod", &pod_json);
        assert_eq!(relations.len(), 2);
        assert!(relations.iter().any(|r| r.kind == "Node"));
        assert!(relations.iter().any(|r| r.kind == "ServiceAccount"));
    }

    #[test]
    fn test_configmap_orphan_detection() {
        use super::super::tree::EdgeType;

        // ConfigMap with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(is_resource_orphan("ConfigMap", "test-cm", Some("default"), &no_refs, None, None, None));

        // ConfigMap with incoming References from Pod is not orphan
        let with_ref = vec![(EdgeType::References, "Pod")];
        assert!(!is_resource_orphan("ConfigMap", "test-cm", Some("default"), &with_ref, None, None, None));

        // ConfigMap with only Owns edge is orphan (shouldn't happen but test it)
        let only_owns = vec![(EdgeType::Owns, "Pod")];
        assert!(is_resource_orphan("ConfigMap", "test-cm", Some("default"), &only_owns, None, None, None));
    }

    #[test]
    fn test_service_orphan_detection() {
        use super::super::tree::EdgeType;

        // Service with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(is_resource_orphan("Service", "test-svc", Some("default"), &no_refs, None, None, None));

        // Service with incoming References from Pod is not orphan
        let with_pod = vec![(EdgeType::References, "Pod")];
        assert!(!is_resource_orphan("Service", "test-svc", Some("default"), &with_pod, None, None, None));

        // Service with incoming References from Ingress is not orphan
        let with_ingress = vec![(EdgeType::References, "Ingress")];
        assert!(!is_resource_orphan("Service", "test-svc", Some("default"), &with_ingress, None, None, None));

        // Service with References from other resources (not Pod/Ingress) is orphan
        let with_other = vec![(EdgeType::References, "ConfigMap")];
        assert!(is_resource_orphan("Service", "test-svc", Some("default"), &with_other, None, None, None));
    }

    #[test]
    fn test_pvc_orphan_detection() {
        use super::super::tree::EdgeType;

        // PVC with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &no_refs, None, None, None));

        // PVC with incoming References from Pod is not orphan
        let with_pod = vec![(EdgeType::References, "Pod")];
        assert!(!is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &with_pod, None, None, None));

        // PVC with incoming References from StatefulSet is not orphan
        let with_sts = vec![(EdgeType::References, "StatefulSet")];
        assert!(!is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &with_sts, None, None, None));

        // PVC with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "ConfigMap")];
        assert!(is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &with_other, None, None, None));
    }

    #[test]
    fn test_serviceaccount_orphan_detection() {
        use super::super::tree::EdgeType;

        // ServiceAccount with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &no_refs, None, None, None));

        // ServiceAccount with incoming References from Pod is not orphan
        let with_pod = vec![(EdgeType::References, "Pod")];
        assert!(!is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &with_pod, None, None, None));

        // ServiceAccount with incoming References from RoleBinding is not orphan
        let with_rb = vec![(EdgeType::References, "RoleBinding")];
        assert!(!is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &with_rb, None, None, None));

        // ServiceAccount with incoming References from ClusterRoleBinding is not orphan
        let with_crb = vec![(EdgeType::References, "ClusterRoleBinding")];
        assert!(!is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &with_crb, None, None, None));

        // ServiceAccount with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "ConfigMap")];
        assert!(is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &with_other, None, None, None));
    }

    #[test]
    fn test_role_orphan_detection() {
        use super::super::tree::EdgeType;

        // Role with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(is_resource_orphan("Role", "test-role", Some("default"), &no_refs, None, None, None));

        // Role with incoming References from RoleBinding is not orphan
        let with_rb = vec![(EdgeType::References, "RoleBinding")];
        assert!(!is_resource_orphan("Role", "test-role", Some("default"), &with_rb, None, None, None));

        // Role with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "Pod")];
        assert!(is_resource_orphan("Role", "test-role", Some("default"), &with_other, None, None, None));

        // Role with only Owns edge is orphan
        let only_owns = vec![(EdgeType::Owns, "RoleBinding")];
        assert!(is_resource_orphan("Role", "test-role", Some("default"), &only_owns, None, None, None));
    }

    #[test]
    fn test_clusterrole_orphan_detection() {
        use super::super::tree::EdgeType;

        // ClusterRole with no incoming references is orphan
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(is_resource_orphan("ClusterRole", "test-clusterrole", None, &no_refs, None, None, None));

        // ClusterRole with incoming References from RoleBinding is not orphan
        let with_rb = vec![(EdgeType::References, "RoleBinding")];
        assert!(!is_resource_orphan("ClusterRole", "test-clusterrole", None, &with_rb, None, None, None));

        // ClusterRole with incoming References from ClusterRoleBinding is not orphan
        let with_crb = vec![(EdgeType::References, "ClusterRoleBinding")];
        assert!(!is_resource_orphan("ClusterRole", "test-clusterrole", None, &with_crb, None, None, None));

        // ClusterRole with References from other resources is orphan
        let with_other = vec![(EdgeType::References, "Pod")];
        assert!(is_resource_orphan("ClusterRole", "test-clusterrole", None, &with_other, None, None, None));

        // ClusterRole with only Owns edge is orphan
        let only_owns = vec![(EdgeType::Owns, "ClusterRoleBinding")];
        assert!(is_resource_orphan("ClusterRole", "test-clusterrole", None, &only_owns, None, None, None));

        // ClusterRole in exception list is not orphan
        assert!(!is_resource_orphan("ClusterRole", "admin", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "edit", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "view", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "cluster-admin", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "system:node", None, &no_refs, None, None, None));
    }

    #[test]
    fn test_is_resource_orphan_dispatcher() {
        use super::super::tree::EdgeType;

        let no_refs: Vec<(EdgeType, &str)> = vec![];

        // Test supported resource types
        assert!(is_resource_orphan("ConfigMap", "test-cm", Some("default"), &no_refs, None, None, None));
        assert!(is_resource_orphan("Secret", "test-secret", Some("default"), &no_refs, None, None, None));
        assert!(is_resource_orphan("Service", "test-svc", Some("default"), &no_refs, None, None, None));
        assert!(is_resource_orphan("PersistentVolumeClaim", "test-pvc", Some("default"), &no_refs, None, None, None));
        assert!(is_resource_orphan("ServiceAccount", "test-sa", Some("default"), &no_refs, None, None, None));
        assert!(is_resource_orphan("Role", "test-role", Some("default"), &no_refs, None, None, None));
        assert!(is_resource_orphan("ClusterRole", "test-clusterrole", None, &no_refs, None, None, None));

        // Test case-insensitive matching
        assert!(is_resource_orphan("configmap", "test", Some("default"), &no_refs, None, None, None));
        assert!(is_resource_orphan("secret", "test", Some("default"), &no_refs, None, None, None));
        assert!(is_resource_orphan("role", "test", Some("default"), &no_refs, None, None, None));
        assert!(is_resource_orphan("clusterrole", "test", None, &no_refs, None, None, None));

        // Test unsupported resource types (should never be orphans)
        assert!(!is_resource_orphan("Pod", "test", Some("default"), &no_refs, None, None, None));
        assert!(!is_resource_orphan("Deployment", "test", Some("default"), &no_refs, None, None, None));
        assert!(!is_resource_orphan("Node", "test-node", None, &no_refs, None, None, None));
    }

    #[test]
    fn test_system_resource_exceptions() {
        use super::super::tree::EdgeType;

        let no_refs: Vec<(EdgeType, &str)> = vec![];

        // ClusterRoles in exception list are never orphans
        assert!(!is_resource_orphan("ClusterRole", "admin", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "edit", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "view", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "sudoer", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "cluster-admin", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "system:node", None, &no_refs, None, None, None));
        assert!(!is_resource_orphan("ClusterRole", "system:metrics-server-aggregated-reader", None, &no_refs, None, None, None));

        // ClusterRoles NOT in exception list with no refs are orphans
        assert!(is_resource_orphan("ClusterRole", "my-custom-role", None, &no_refs, None, None, None));
        assert!(is_resource_orphan("ClusterRole", "system:csi-external-attacher", None, &no_refs, None, None, None));

        // Default ServiceAccount is never orphan (in any namespace)
        assert!(!is_resource_orphan("ServiceAccount", "default", Some("default"), &no_refs, None, None, None));
        assert!(!is_resource_orphan("ServiceAccount", "default", Some("kube-system"), &no_refs, None, None, None));
        assert!(!is_resource_orphan("ServiceAccount", "default", Some("my-namespace"), &no_refs, None, None, None));

        // Non-default ServiceAccount with no refs is orphan (even in system namespaces)
        assert!(is_resource_orphan("ServiceAccount", "my-sa", Some("kube-system"), &no_refs, None, None, None));
        assert!(is_resource_orphan("ServiceAccount", "my-sa", Some("default"), &no_refs, None, None, None));

        // Specific system ConfigMaps are never orphans
        assert!(!is_resource_orphan("ConfigMap", "kube-root-ca.crt", Some("default"), &no_refs, None, None, None));
        assert!(!is_resource_orphan("ConfigMap", "kube-root-ca.crt", Some("kube-system"), &no_refs, None, None, None));
        assert!(!is_resource_orphan("ConfigMap", "extension-apiserver-authentication", Some("kube-system"), &no_refs, None, None, None));

        // Other ConfigMaps with no refs are orphans (even in system namespaces)
        assert!(is_resource_orphan("ConfigMap", "my-cm", Some("kube-system"), &no_refs, None, None, None));
        assert!(is_resource_orphan("ConfigMap", "my-cm", Some("default"), &no_refs, None, None, None));

        // Service account token secrets are never orphans (checked via label or type)
        let mut sa_labels = std::collections::HashMap::new();
        sa_labels.insert("kubernetes.io/service-account.name".to_string(), "default".to_string());
        assert!(!is_resource_orphan("Secret", "token-secret", Some("default"), &no_refs, Some(&sa_labels), None, None));

        // Service account token secrets detected by type
        assert!(!is_resource_orphan("Secret", "token-secret", Some("default"), &no_refs, None, Some("kubernetes.io/service-account-token"), None));

        // Other Secrets with no refs are orphans (even in system namespaces)
        assert!(is_resource_orphan("Secret", "my-secret", Some("kube-system"), &no_refs, None, None, None));
        assert!(is_resource_orphan("Secret", "my-secret", Some("default"), &no_refs, None, None, None));

        // Only "kubernetes" Service in default namespace is never orphan
        assert!(!is_resource_orphan("Service", "kubernetes", Some("default"), &no_refs, None, None, None));

        // Other Services with no refs are orphans (even in system namespaces)
        assert!(is_resource_orphan("Service", "my-service", Some("kube-system"), &no_refs, None, None, None));
        assert!(is_resource_orphan("Service", "my-service", Some("default"), &no_refs, None, None, None));
    }

    #[test]
    fn test_rolebinding_broken_references() {
        use super::super::tree::EdgeType;
        use std::collections::HashMap;

        // RoleBinding with Role ref but NO missing ServiceAccounts is NOT orphan
        let with_role = vec![(EdgeType::References, "Role")];
        assert!(!is_resource_orphan("RoleBinding", "test-rb", Some("default"), &with_role, None, None, None));

        // RoleBinding with ClusterRole ref but NO missing ServiceAccounts is NOT orphan
        let with_clusterrole = vec![(EdgeType::References, "ClusterRole")];
        assert!(!is_resource_orphan("RoleBinding", "test-rb", Some("default"), &with_clusterrole, None, None, None));

        // RoleBinding with Role ref but WITH missing ServiceAccount IS orphan
        let mut missing_refs = HashMap::new();
        missing_refs.insert("ServiceAccount".to_string(), vec!["missing-sa".to_string()]);
        assert!(is_resource_orphan("RoleBinding", "test-rb", Some("default"), &with_role, None, None, Some(&missing_refs)));

        // RoleBinding without any Role ref is orphan (regardless of missing_refs)
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(is_resource_orphan("RoleBinding", "test-rb", Some("default"), &no_refs, None, None, None));
    }

    #[test]
    fn test_clusterrolebinding_broken_references() {
        use super::super::tree::EdgeType;
        use std::collections::HashMap;

        // ClusterRoleBinding with ClusterRole ref but NO missing ServiceAccounts is NOT orphan
        let with_clusterrole = vec![(EdgeType::References, "ClusterRole")];
        assert!(!is_resource_orphan("ClusterRoleBinding", "test-crb", None, &with_clusterrole, None, None, None));

        // ClusterRoleBinding with ClusterRole ref but WITH missing ServiceAccount IS orphan
        let mut missing_refs = HashMap::new();
        missing_refs.insert("ServiceAccount".to_string(), vec!["kube-system/missing-sa".to_string()]);
        assert!(is_resource_orphan("ClusterRoleBinding", "test-crb", None, &with_clusterrole, None, None, Some(&missing_refs)));

        // ClusterRoleBinding without ClusterRole ref is orphan (regardless of missing_refs)
        let no_refs: Vec<(EdgeType, &str)> = vec![];
        assert!(is_resource_orphan("ClusterRoleBinding", "test-crb", None, &no_refs, None, None, None));

        // ClusterRoleBinding with multiple missing ServiceAccounts is orphan
        let mut multiple_missing = HashMap::new();
        multiple_missing.insert("ServiceAccount".to_string(), vec![
            "kube-system/sa1".to_string(),
            "default/sa2".to_string(),
        ]);
        assert!(is_resource_orphan("ClusterRoleBinding", "test-crb", None, &with_clusterrole, None, None, Some(&multiple_missing)));
    }
}
