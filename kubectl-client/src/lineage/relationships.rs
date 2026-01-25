use k8s_openapi::serde_json::Value;
use super::tree::RelationRef;

/// Extract relationships from a Kubernetes resource based on its kind
#[allow(dead_code)]
pub fn extract_relationships(kind: &str, item: &Value) -> Vec<RelationRef> {
    match kind {
        "Event" => extract_event_relationships(item),
        "Ingress" => extract_ingress_relationships(item),
        "IngressClass" => extract_ingressclass_relationships(item),
        "Pod" => extract_pod_relationships(item),
        "ClusterRole" => extract_clusterrole_relationships(item),
        "PersistentVolumeClaim" => extract_pvc_relationships(item),
        "PersistentVolume" => extract_pv_relationships(item),
        "ClusterRoleBinding" => extract_clusterrolebinding_relationships(item),
        _ => Vec::new(),
    }
}

fn extract_event_relationships(item: &Value) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    // regarding field
    if let Some(regarding) = item.get("regarding").and_then(|v| v.as_object()) {
        if let (Some(kind), Some(name)) = (
            regarding.get("kind").and_then(|v| v.as_str()),
            regarding.get("name").and_then(|v| v.as_str()),
        ) {
            relations.push(RelationRef {
                kind: kind.to_string(),
                name: name.to_string(),
                namespace: regarding
                    .get("namespace")
                    .and_then(|v| v.as_str())
                    .map(String::from),
                api_version: regarding
                    .get("apiVersion")
                    .and_then(|v| v.as_str())
                    .map(String::from),
                uid: regarding.get("uid").and_then(|v| v.as_str()).map(String::from),
            });
        }
    }

    // related field
    if let Some(related) = item.get("related").and_then(|v| v.as_object()) {
        if let (Some(kind), Some(name)) = (
            related.get("kind").and_then(|v| v.as_str()),
            related.get("name").and_then(|v| v.as_str()),
        ) {
            relations.push(RelationRef {
                kind: kind.to_string(),
                name: name.to_string(),
                namespace: related
                    .get("namespace")
                    .and_then(|v| v.as_str())
                    .map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    relations
}

fn extract_ingress_relationships(item: &Value) -> Vec<RelationRef> {
    let mut relations = Vec::new();
    let namespace = item
        .get("metadata")
        .and_then(|m| m.get("namespace"))
        .and_then(|v| v.as_str());

    // ingressClassName
    if let Some(class_name) = item
        .get("spec")
        .and_then(|s| s.get("ingressClassName"))
        .and_then(|v| v.as_str())
    {
        relations.push(RelationRef {
            kind: "IngressClass".to_string(),
            name: class_name.to_string(),
            namespace: None,
            api_version: None,
            uid: None,
        });
    }

    // backend
    if let Some(backend) = item.get("spec").and_then(|s| s.get("backend")) {
        if let Some(rel) = extract_backend_relation(backend, namespace) {
            relations.push(rel);
        }
    }

    // rules
    if let Some(rules) = item
        .get("spec")
        .and_then(|s| s.get("rules"))
        .and_then(|v| v.as_array())
    {
        for rule in rules {
            if let Some(http) = rule.get("http") {
                if let Some(paths) = http.get("paths").and_then(|v| v.as_array()) {
                    for path in paths {
                        if let Some(backend) = path.get("backend") {
                            if let Some(rel) = extract_backend_relation(backend, namespace) {
                                relations.push(rel);
                            }
                        }
                    }
                }
            }
        }
    }

    // tls secrets
    if let Some(tls_list) = item
        .get("spec")
        .and_then(|s| s.get("tls"))
        .and_then(|v| v.as_array())
    {
        for tls in tls_list {
            if let Some(secret_name) = tls.get("secretName").and_then(|v| v.as_str()) {
                relations.push(RelationRef {
                    kind: "Secret".to_string(),
                    name: secret_name.to_string(),
                    namespace: namespace.map(String::from),
                    api_version: None,
                    uid: None,
                });
            }
        }
    }

    relations
}

fn extract_backend_relation(backend: &Value, namespace: Option<&str>) -> Option<RelationRef> {
    // Check for resource backend
    if let Some(resource) = backend.get("resource").and_then(|v| v.as_object()) {
        if let (Some(kind), Some(name)) = (
            resource.get("kind").and_then(|v| v.as_str()),
            resource.get("name").and_then(|v| v.as_str()),
        ) {
            return Some(RelationRef {
                kind: kind.to_string(),
                name: name.to_string(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    // Check for service backend (old API)
    if let Some(service_name) = backend.get("serviceName").and_then(|v| v.as_str()) {
        return Some(RelationRef {
            kind: "Service".to_string(),
            name: service_name.to_string(),
            namespace: namespace.map(String::from),
            api_version: None,
            uid: None,
        });
    }

    // Check for service backend (new API)
    if let Some(service) = backend.get("service").and_then(|v| v.as_object()) {
        if let Some(name) = service.get("name").and_then(|v| v.as_str()) {
            return Some(RelationRef {
                kind: "Service".to_string(),
                name: name.to_string(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    None
}

fn extract_ingressclass_relationships(item: &Value) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    if let Some(parameters) = item
        .get("spec")
        .and_then(|s| s.get("parameters"))
        .and_then(|v| v.as_object())
    {
        if let (Some(kind), Some(name)) = (
            parameters.get("kind").and_then(|v| v.as_str()),
            parameters.get("name").and_then(|v| v.as_str()),
        ) {
            relations.push(RelationRef {
                kind: kind.to_string(),
                name: name.to_string(),
                namespace: parameters
                    .get("namespace")
                    .and_then(|v| v.as_str())
                    .map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    relations
}

fn extract_pod_relationships(item: &Value) -> Vec<RelationRef> {
    let mut relations = Vec::new();
    let namespace = item
        .get("metadata")
        .and_then(|m| m.get("namespace"))
        .and_then(|v| v.as_str());

    let spec = match item.get("spec") {
        Some(s) => s,
        None => return relations,
    };

    // nodeName
    if let Some(node_name) = spec.get("nodeName").and_then(|v| v.as_str()) {
        relations.push(RelationRef {
            kind: "Node".to_string(),
            name: node_name.to_string(),
            namespace: None,
            api_version: None,
            uid: None,
        });
    }

    // priorityClassName
    if let Some(priority_class) = spec.get("priorityClassName").and_then(|v| v.as_str()) {
        relations.push(RelationRef {
            kind: "PriorityClass".to_string(),
            name: priority_class.to_string(),
            namespace: None,
            api_version: None,
            uid: None,
        });
    }

    // runtimeClassName
    if let Some(runtime_class) = spec.get("runtimeClassName").and_then(|v| v.as_str()) {
        relations.push(RelationRef {
            kind: "RuntimeClass".to_string(),
            name: runtime_class.to_string(),
            namespace: None,
            api_version: None,
            uid: None,
        });
    }

    // serviceAccountName
    if let Some(sa_name) = spec.get("serviceAccountName").and_then(|v| v.as_str()) {
        relations.push(RelationRef {
            kind: "ServiceAccount".to_string(),
            name: sa_name.to_string(),
            namespace: namespace.map(String::from),
            api_version: None,
            uid: None,
        });
    }

    // volumes
    if let Some(volumes) = spec.get("volumes").and_then(|v| v.as_array()) {
        for volume in volumes {
            relations.extend(extract_volume_relations(volume, namespace));
        }
    }

    relations
}

#[allow(dead_code)]
fn extract_volume_relations(volume: &Value, namespace: Option<&str>) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    // ConfigMap
    if let Some(config_map) = volume.get("configMap").and_then(|v| v.as_object()) {
        if let Some(name) = config_map.get("name").and_then(|v| v.as_str()) {
            relations.push(RelationRef {
                kind: "ConfigMap".to_string(),
                name: name.to_string(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    // Secret
    if let Some(secret) = volume.get("secret").and_then(|v| v.as_object()) {
        if let Some(name) = secret.get("secretName").and_then(|v| v.as_str()) {
            relations.push(RelationRef {
                kind: "Secret".to_string(),
                name: name.to_string(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    // PersistentVolumeClaim
    if let Some(pvc) = volume
        .get("persistentVolumeClaim")
        .and_then(|v| v.as_object())
    {
        if let Some(name) = pvc.get("claimName").and_then(|v| v.as_str()) {
            relations.push(RelationRef {
                kind: "PersistentVolumeClaim".to_string(),
                name: name.to_string(),
                namespace: namespace.map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    // CSI
    if let Some(csi) = volume.get("csi").and_then(|v| v.as_object()) {
        if let Some(driver) = csi.get("driver").and_then(|v| v.as_str()) {
            relations.push(RelationRef {
                kind: "CSIDriver".to_string(),
                name: driver.to_string(),
                namespace: None,
                api_version: None,
                uid: None,
            });
        }
        if let Some(secret_ref) = csi.get("nodePublishSecretRef").and_then(|v| v.as_object()) {
            if let Some(name) = secret_ref.get("name").and_then(|v| v.as_str()) {
                relations.push(RelationRef {
                    kind: "Secret".to_string(),
                    name: name.to_string(),
                    namespace: namespace.map(String::from),
                    api_version: None,
                    uid: None,
                });
            }
        }
    }

    // Projected
    if let Some(projected) = volume.get("projected").and_then(|v| v.as_object()) {
        if let Some(sources) = projected.get("sources").and_then(|v| v.as_array()) {
            for source in sources {
                if let Some(config_map) = source.get("configMap").and_then(|v| v.as_object()) {
                    if let Some(name) = config_map.get("name").and_then(|v| v.as_str()) {
                        relations.push(RelationRef {
                            kind: "ConfigMap".to_string(),
                            name: name.to_string(),
                            namespace: namespace.map(String::from),
                            api_version: None,
                            uid: None,
                        });
                    }
                }
                if let Some(secret) = source.get("secret").and_then(|v| v.as_object()) {
                    if let Some(name) = secret.get("name").and_then(|v| v.as_str()) {
                        relations.push(RelationRef {
                            kind: "Secret".to_string(),
                            name: name.to_string(),
                            namespace: namespace.map(String::from),
                            api_version: None,
                            uid: None,
                        });
                    }
                }
            }
        }
    }

    relations
}

#[allow(dead_code)]
fn extract_clusterrole_relationships(_item: &Value) -> Vec<RelationRef> {
    // ClusterRole relationships are complex and selector-based
    // For now, return empty - can be enhanced later
    Vec::new()
}

#[allow(dead_code)]
fn extract_pvc_relationships(item: &Value) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    if let Some(volume_name) = item
        .get("spec")
        .and_then(|s| s.get("volumeName"))
        .and_then(|v| v.as_str())
    {
        relations.push(RelationRef {
            kind: "PersistentVolume".to_string(),
            name: volume_name.to_string(),
            namespace: None,
            api_version: None,
            uid: None,
        });
    }

    relations
}

#[allow(dead_code)]
fn extract_pv_relationships(item: &Value) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    if let Some(claim_ref) = item
        .get("spec")
        .and_then(|s| s.get("claimRef"))
        .and_then(|v| v.as_object())
    {
        if let (Some(kind), Some(name)) = (
            claim_ref.get("kind").and_then(|v| v.as_str()),
            claim_ref.get("name").and_then(|v| v.as_str()),
        ) {
            relations.push(RelationRef {
                kind: kind.to_string(),
                name: name.to_string(),
                namespace: claim_ref
                    .get("namespace")
                    .and_then(|v| v.as_str())
                    .map(String::from),
                api_version: None,
                uid: None,
            });
        }
    }

    relations
}

#[allow(dead_code)]
fn extract_clusterrolebinding_relationships(item: &Value) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    // roleRef
    if let Some(role_ref) = item.get("roleRef").and_then(|v| v.as_object()) {
        if let (Some(kind), Some(name)) = (
            role_ref.get("kind").and_then(|v| v.as_str()),
            role_ref.get("name").and_then(|v| v.as_str()),
        ) {
            if kind == "ClusterRole" {
                relations.push(RelationRef {
                    kind: kind.to_string(),
                    name: name.to_string(),
                    namespace: None,
                    api_version: None,
                    uid: None,
                });
            }
        }
    }

    // subjects (ServiceAccounts)
    if let Some(subjects) = item.get("subjects").and_then(|v| v.as_array()) {
        for subject in subjects {
            if let Some(subject_obj) = subject.as_object() {
                let kind = subject_obj.get("kind").and_then(|v| v.as_str());
                let name = subject_obj.get("name").and_then(|v| v.as_str());

                if let (Some("ServiceAccount"), Some(sa_name)) = (kind, name) {
                    let namespace = subject_obj
                        .get("namespace")
                        .and_then(|v| v.as_str())
                        .map(String::from);
                    relations.push(RelationRef {
                        kind: "ServiceAccount".to_string(),
                        name: sa_name.to_string(),
                        namespace,
                        api_version: None,
                        uid: None,
                    });
                }
            }
        }
    }

    relations
}

#[cfg(test)]
mod tests {
    use super::*;
    use k8s_openapi::serde_json::json;

    #[test]
    fn test_extract_event_relationships() {
        let event = json!({
            "regarding": {
                "kind": "Pod",
                "name": "test-pod",
                "namespace": "default"
            }
        });

        let relations = extract_event_relationships(&event);
        assert_eq!(relations.len(), 1);
        assert_eq!(relations[0].kind, "Pod");
        assert_eq!(relations[0].name, "test-pod");
    }

    #[test]
    fn test_extract_pod_relationships() {
        let pod = json!({
            "metadata": {
                "namespace": "default"
            },
            "spec": {
                "nodeName": "node-1",
                "serviceAccountName": "default"
            }
        });

        let relations = extract_pod_relationships(&pod);
        assert_eq!(relations.len(), 2);
        assert!(relations.iter().any(|r| r.kind == "Node"));
        assert!(relations.iter().any(|r| r.kind == "ServiceAccount"));
    }
}
