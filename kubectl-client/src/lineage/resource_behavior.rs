use super::tree::RelationRef;
use k8s_openapi::api::core::v1::{
    Container, EnvFromSource, EnvVar, EphemeralContainer, PodSpec, Volume,
};

// Accessor traits for common K8s structures
/// Trait for types that have environment variables (Container, EphemeralContainer)
pub(crate) trait HasEnv {
    fn env(&self) -> Option<&Vec<EnvVar>>;
    fn env_from(&self) -> Option<&Vec<EnvFromSource>>;
}

impl HasEnv for Container {
    fn env(&self) -> Option<&Vec<EnvVar>> {
        self.env.as_ref()
    }
    fn env_from(&self) -> Option<&Vec<EnvFromSource>> {
        self.env_from.as_ref()
    }
}

impl HasEnv for EphemeralContainer {
    fn env(&self) -> Option<&Vec<EnvVar>> {
        self.env.as_ref()
    }
    fn env_from(&self) -> Option<&Vec<EnvFromSource>> {
        self.env_from.as_ref()
    }
}


// Helper functions

/// Extract environment variable relationships from any container type
pub(crate) fn extract_env_relations(container: &impl HasEnv, namespace: Option<&str>) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    // env with valueFrom
    if let Some(env_vars) = container.env() {
        for env in env_vars {
            if let Some(value_from) = &env.value_from {
                // configMapKeyRef
                if let Some(config_map_ref) = &value_from.config_map_key_ref {
                    relations.push(RelationRef::new("ConfigMap", config_map_ref.name.clone()).ns(namespace));
                }
                // secretKeyRef
                if let Some(secret_ref) = &value_from.secret_key_ref {
                    relations.push(RelationRef::new("Secret", secret_ref.name.clone()).ns(namespace));
                }
            }
        }
    }

    // envFrom
    if let Some(env_from) = container.env_from() {
        for env in env_from {
            // configMapRef
            if let Some(config_map_ref) = &env.config_map_ref {
                relations.push(RelationRef::new("ConfigMap", config_map_ref.name.clone()).ns(namespace));
            }
            // secretRef
            if let Some(secret_ref) = &env.secret_ref {
                relations.push(RelationRef::new("Secret", secret_ref.name.clone()).ns(namespace));
            }
        }
    }

    relations
}

/// Extract volume relationships
pub(crate) fn extract_volume_relations(volume: &Volume, namespace: Option<&str>) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    // ConfigMap
    if let Some(config_map) = &volume.config_map {
        relations.push(RelationRef::new("ConfigMap", config_map.name.clone()).ns(namespace));
    }

    // Secret
    if let Some(secret) = &volume.secret {
        if let Some(name) = &secret.secret_name {
            relations.push(RelationRef::new("Secret", name.clone()).ns(namespace));
        }
    }

    // PersistentVolumeClaim
    if let Some(pvc) = &volume.persistent_volume_claim {
        relations.push(RelationRef::new("PersistentVolumeClaim", pvc.claim_name.clone()).ns(namespace));
    }

    // CSI
    if let Some(csi) = &volume.csi {
        relations.push(RelationRef::new("CSIDriver", csi.driver.clone()));
        if let Some(secret_ref) = &csi.node_publish_secret_ref {
            relations.push(RelationRef::new("Secret", secret_ref.name.clone()).ns(namespace));
        }
    }

    // Projected
    if let Some(projected) = &volume.projected {
        if let Some(sources) = &projected.sources {
            for source in sources {
                if let Some(config_map) = &source.config_map {
                    relations.push(RelationRef::new("ConfigMap", config_map.name.clone()).ns(namespace));
                }
                if let Some(secret) = &source.secret {
                    relations.push(RelationRef::new("Secret", secret.name.clone()).ns(namespace));
                }
            }
        }
    }

    relations
}

/// Extract relationships from a PodSpec (used by DaemonSet, Job, CronJob)
pub(crate) fn extract_pod_spec_relations(spec: &PodSpec, namespace: Option<&str>) -> Vec<RelationRef> {
    let mut relations = Vec::new();

    // serviceAccountName
    if let Some(sa_name) = &spec.service_account_name {
        relations.push(RelationRef::new("ServiceAccount", sa_name.clone()).ns(namespace));
    }

    // volumes
    if let Some(volumes) = &spec.volumes {
        for volume in volumes {
            relations.extend(extract_volume_relations(volume, namespace));
        }
    }

    // environment variables from all container types - unified iteration
    for container in &spec.containers {
        relations.extend(extract_env_relations(container, namespace));
    }

    if let Some(init_containers) = &spec.init_containers {
        for container in init_containers {
            relations.extend(extract_env_relations(container, namespace));
        }
    }

    if let Some(ephemeral_containers) = &spec.ephemeral_containers {
        for container in ephemeral_containers {
            relations.extend(extract_env_relations(container, namespace));
        }
    }

    // imagePullSecrets
    if let Some(image_pull_secrets) = &spec.image_pull_secrets {
        for secret_ref in image_pull_secrets {
            relations.push(RelationRef::new("Secret", secret_ref.name.clone()).ns(namespace));
        }
    }

    relations
}
