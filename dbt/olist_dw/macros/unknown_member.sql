{#- Khoá của unknown member trong mọi dim (CLAUDE.md mục 7.3) -#}
{% macro unknown_key() -%}
    -1
{%- endmacro %}

{#- Khoá dim từ lookup: null → -1. Dùng: {{ coalesce_key('c.customer_key') }} -#}
{% macro coalesce_key(expr) -%}
    coalesce({{ expr }}, {{ unknown_key() }})
{%- endmacro %}

{#- Date key YYYYMMDD từ date/timestamp; null (sự kiện chưa xảy ra) → -1 -#}
{% macro date_key(expr) -%}
    coalesce(to_char(({{ expr }})::date, 'YYYYMMDD')::integer, {{ unknown_key() }})
{%- endmacro %}
