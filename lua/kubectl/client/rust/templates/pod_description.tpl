Name:             {{ name }}
Namespace:        {{ namespace -}}
{% if priority is defined %}
Priority:         {{ priority }} {% endif -%}
{% if runtime_class_name is defined -%} 
	RuntimeClassName: {{ runtime_class_name }} {% endif %}
{% if service_account_name is defined -%} 
	Service Account:  {{ service_account_name }} {% endif -%}
{% if node_name is defined %}
Node:             {{ node_name }}{% endif -%}
{% if start_time is defined %}
Start time:       {{ start_time }}{% endif %}
Labels: {% for key, value in labels %}
  {%- if loop.first %}          {{ key }}={{ value }}{%- else %}
                  {{ key }}={{ value }}{%- endif -%}{% endfor %}
Annotations: {% for key, value in annotations %}
  {%- if loop.first %}     {{ key }}={{ value }}{%- else %}
                  {{ key }}={{ value }}{%- endif -%}{% endfor %}
Status: 					{{ status }}
{% if reason is defined %}Reason:     {{ reason }}{% endif -%}
{% if message is defined %}Message:    {{ message }}{% endif -%}
{% if seccomp_profile is defined %}SeccompProfile:   {{ seccomp_profile }}{% endif -%}
{% if localhost_profile is defined %}LocalhostProfile: {{ localhost_profile }}{% endif -%}
IP: 					    {{ ip }}
{% if pod_ips is defined -%}
IPs:
{%- for ip in pod_ips %}
  IP:           {{ ip }}
{% endfor %}
{% else %}
IPs: <none>
{% endif %}
Controlled By: 		{{ controlled_by }}
