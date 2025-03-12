Name:{{ pad(desired=18, subtract='Name:', text=name) }}
Namespace:{{ pad(desired=18, subtract='Namespace:', text=namespace) -}}
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
{% if reason is defined %}NomintatedNodeName:     {{ nominated_node_name }}{% endif -%}
{% if init_containers is defined %}
Init Containers:
	{% for container in init_containers -%}
  {{ container.name -}}:
	{%- if container.container_id is defined %}
		Container ID:   {{ container.container_id -}}
	{% endif %}
    Image:          {{ container.image -}}
	{%- if container.image_id is defined %}
    Image ID:       {{ container.image_id -}}
	{% endif %}
  {%- if container.port is defined %}
    Port:           {{ container.port }}
	{% endif %}
  {%- if container.host_port is defined %}
    Host Port:      {{ container.host_port }}
  {%- elif container.host_ports is defined %}
    Host Ports:     {{ container.host_ports }}
	{% endif %}
	{% endfor %}
{% endif -%}

