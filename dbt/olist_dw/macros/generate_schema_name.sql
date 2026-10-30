{#- Dùng đúng tên schema cấu hình (stg, dw, bi) thay vì <target_schema>_<custom> mặc định của dbt -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
