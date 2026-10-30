{#-
    Surrogate key bigint xác định từ natural key (CLAUDE.md mục 7.3):
    ('x' || left(md5(concat_ws('|', cols...)), 15))::bit(60)::bigint
    Ổn định giữa các lần build và khi load incremental. Null được thay bằng '' để giữ vị trí cột.
    Dùng: {{ int_sk(['seller_id', 'valid_from']) }}
-#}
{% macro int_sk(cols) -%}
    ('x' || left(md5(concat_ws('|'
    {%- for col in cols -%}
        , coalesce(cast({{ col }} as text), '')
    {%- endfor -%}
    )), 15))::bit(60)::bigint
{%- endmacro %}
