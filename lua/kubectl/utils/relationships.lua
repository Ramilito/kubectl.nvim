local M = {}

function M.extractFieldValue(field_path, item)
  local field = item
  for part in string.gmatch(field_path, "[^%.]+") do
    field = field and field[part]
  end
  return field
end

function M.getRelationship(kind, item, rows)
  local rel_def = M.definition[kind]
  local relations = {}

  if rel_def and rel_def.relationships then
    for _, rel in ipairs(rel_def.relationships) do
      local field_value = M.extractFieldValue(rel.field_path, item)
      if field_value then
        -- Handle array fields
        if type(field_value) == "table" and #field_value > 0 then
          for _, value in ipairs(field_value) do
            local subfield_values = rel.extract_subfield and rel.extract_subfield(value) or { value }
            for _, subfield_value in ipairs(subfield_values) do
              local k = type(rel.target_kind) == "function" and rel.target_kind(subfield_value) or rel.target_kind
              local name = type(rel.target_name) == "function" and rel.target_name(subfield_value) or subfield_value
              local namespace = rel.target_namespace and item.metadata.namespace or nil
              local uid = type(rel.target_uid) == "function" and rel.target_uid(subfield_value) or nil

              if k and name then
                table.insert(relations, {
                  kind = k,
                  apiVersion = rows.apiVersion,
                  name = name,
                  ns = namespace,
                  uid = uid,
                })
              end
            end
          end
        else
          -- Handle single value fields
          local k = type(rel.target_kind) == "function" and rel.target_kind(field_value) or rel.target_kind
          local name = type(rel.target_name) == "function" and rel.target_name(field_value) or field_value
          local namespace = rel.target_namespace and item.metadata.namespace or nil
          local uid = rel.target_uid and rel.target_uid(field_value) or field_value

          if k and name then
            table.insert(relations, {
              kind = k,
              apiVersion = rows.apiVersion,
              name = name,
              ns = namespace,
              uid = uid,
            })
          end
        end
      end
    end
  end
  return relations
end

M.definition = {
  Event = {
    kind = "Event",
    relationships = {
      {
        relationship_type = "dependency",
        field_path = "regarding",
        target_kind = function(field_value)
          return field_value.kind
        end,
        target_name = function(field_value)
          return field_value.name
        end,
        target_namespace = function(field_value)
          return field_value.namespace
        end,
        target_uid = function(field_value)
          return field_value.uid
        end,
      },
      {
        relationship_type = "dependency",
        field_path = "related",
        target_kind = function(field_value)
          return field_value.kind
        end,
        target_name = function(field_value)
          return field_value.name
        end,
        target_namespace = function(field_value)
          return field_value.namespace
        end,
      },
    },
  },
  Ingress = {
    kind = "Ingress",
    relationships = {
      {
        relationship_type = "dependency",
        field_path = "spec.ingressClassName",
        target_kind = "IngressClass",
        target_name = function(field_value)
          return field_value
        end,
        target_namespace = false,
      },
      {
        relationship_type = "dependency",
        field_path = "spec.backend",
        target_kind = function(backend)
          if backend.resource then
            return backend.resource.kind
          elseif backend.serviceName or backend.service then
            return "Service"
          end
        end,
        target_name = function(backend)
          if backend.resource then
            return backend.resource.name
          elseif backend.serviceName or backend.service then
            return backend.serviceName or backend.service.name
          end
        end,
        target_namespace = true,
      },
      {
        relationship_type = "dependency",
        field_path = "spec.rules",
        extract_subfield = function(rule)
          local backends = {}
          if rule.http then
            for _, path in ipairs(rule.http.paths) do
              table.insert(backends, path.backend)
            end
          end
          return backends
        end,
        target_kind = function(backend)
          if backend.resource then
            return backend.resource.kind
          elseif backend.serviceName or backend.service then
            return "Service"
          end
        end,
        target_name = function(backend)
          if backend.resource then
            return backend.resource.name
          elseif backend.serviceName or backend.service then
            return backend.serviceName or backend.service.name
          end
        end,
        target_namespace = true,
      },
      {
        relationship_type = "dependency",
        field_path = "spec.tls",
        extract_subfield = function(tls)
          return { tls.secretName }
        end,
        target_kind = "Secret",
        target_name = function(secretName)
          return secretName
        end,
        target_namespace = true,
      },
    },
  },
  Pod = {
    kind = "Pod",
    relationships = {
      -- RelationshipPodNode: Handles the node on which the pod is scheduled.
      {
        relationship_type = "dependency",
        field_path = "spec.nodeName",
        target_kind = "Node",
        target_name = function(field_value)
          return field_value
        end,
      },

      -- RelationshipPodPriorityClass: Handles the PriorityClass assigned to the pod.
      {
        relationship_type = "dependency",
        field_path = "spec.priorityClassName",
        target_kind = "PriorityClass",
        target_name = function(field_value)
          return field_value
        end,
      },

      -- RelationshipPodRuntimeClass: Handles the RuntimeClass of the pod.
      {
        relationship_type = "dependency",
        field_path = "spec.runtimeClassName",
        target_kind = "RuntimeClass",
        target_name = function(field_value)
          return field_value
        end,
      },

      -- RelationshipPodSecurityPolicy: Handles the PodSecurityPolicy assigned to the pod.
      {
        relationship_type = "dependency",
        field_path = "metadata.annotations",
        target_kind = "PodSecurityPolicy",
        target_name = function(annotations)
          return annotations["kubernetes.io/psp"]
        end,
        target_namespace = false,
      },

      -- RelationshipPodServiceAccount: Handles the ServiceAccount assigned to the pod.
      {
        relationship_type = "dependency",
        field_path = "spec.serviceAccountName",
        target_kind = "ServiceAccount",
        target_name = function(field_value)
          return field_value
        end,
        target_namespace = true, -- Same namespace as pod
      },

      -- RelationshipPodVolume: Handles volumes such as ConfigMaps, Secrets, and PersistentVolumeClaims.
      {
        relationship_type = "dependency",
        field_path = "spec.volumes",
        extract_subfield = function(volume)
          local refs = {}
          -- ConfigMap Volume
          if volume.configMap then
            table.insert(refs, {
              kind = "ConfigMap",
              name = volume.configMap.name,
              ns = nil,
            })
          end
          -- CSI Volume
          if volume.csi then
            table.insert(refs, {
              kind = "CSIDriver",
              name = volume.csi.driver,
              ns = nil,
            })
            if volume.csi.nodePublishSecretRef then
              table.insert(refs, {
                kind = "Secret",
                name = volume.csi.nodePublishSecretRef.name,
                ns = nil,
              })
            end
          end
          -- PersistentVolumeClaim
          if volume.persistentVolumeClaim then
            table.insert(refs, {
              kind = "PersistentVolumeClaim",
              name = volume.persistentVolumeClaim.claimName,
              ns = nil,
            })
          end
          -- Projected Sources
          if volume.projected then
            for _, source in ipairs(volume.projected.sources) do
              if source.configMap then
                table.insert(refs, {
                  kind = "ConfigMap",
                  name = source.configMap.name,
                  ns = nil,
                })
              elseif source.secret then
                table.insert(refs, {
                  kind = "Secret",
                  name = source.secret.name,
                  ns = nil,
                })
              end
            end
          end
          -- Secret Volume
          if volume.secret then
            table.insert(refs, {
              kind = "Secret",
              name = volume.secret.secretName,
              ns = nil,
            })
          end
          return refs
        end,
        target_kind = function(ref)
          return ref.kind
        end,
        target_name = function(ref)
          return ref.name
        end,
        target_namespace = function(ref)
          return ref.ns
        end,
      },
    },
  },
}

return M
