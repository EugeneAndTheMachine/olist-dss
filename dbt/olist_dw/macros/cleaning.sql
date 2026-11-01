{#- Rule staging dùng chung (implementation.md mục 9) -#}

{#- Chuỗi rỗng / toàn khoảng trắng → null -#}
{% macro clean_text(col) -%}
    nullif(trim({{ col }}), '')
{%- endmacro %}

{#- Zip prefix 5 số: giữ số 0 đầu (raw là text nên không mất, lpad để phòng nguồn đọc qua pandas/Excel) -#}
{% macro zip5(col) -%}
    lpad(nullif(trim({{ col }}), ''), 5, '0')
{%- endmacro %}

{#- City: bỏ dấu (extension unaccent), lower case, gộp khoảng trắng. 'são paulo' và 'sao paulo' → 'sao paulo' -#}
{% macro clean_city(col) -%}
    nullif(regexp_replace(lower(public.unaccent(trim({{ col }}))), '\s+', ' ', 'g'), '')
{%- endmacro %}

{#- Mã bang 2 ký tự viết hoa -#}
{% macro state_code(col) -%}
    upper(nullif(trim({{ col }}), ''))
{%- endmacro %}

{#- 'True' / 'False' / rỗng → boolean -#}
{% macro to_bool(col) -%}
    case lower(nullif(trim({{ col }}), ''))
        when 'true' then true
        when 'false' then false
    end
{%- endmacro %}
