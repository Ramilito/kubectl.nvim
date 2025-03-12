Name:             {{ name }}
Namespace:        {{ namespace -}}
{% if priority is defined %}
Priority:         {{ priority }} {% endif -%}
{% if runtime_class_name is defined -%} 
	RuntimeClassName: {{ runtime_class_name }} {% endif %}
{% if service_account_name is defined -%} 
	Service Account:  {{ service_account_name }} {% endif -%}
{% if node_name is defined %}
Node:             {{ node_name }}{% endif %}
Labels: {% for key, value in labels %}
  {%- if loop.first %}          {{ key }}={{ value }}{%- else %}
                  {{ key }}={{ value }}{%- endif -%}{% endfor %}
Annotations: {% for key, value in annotations %}
  {%- if loop.first %}     {{ key }}={{ value }}{%- else %}
                  {{ key }}={{ value }}{%- endif -%}{% endfor %}
Status:
    Phase:      {{ phase }}
    {% if message is defined %}Message:    {{ message }}{% endif %}
    {% if reason is defined %}Reason:     {{ reason }}{% endif %}
