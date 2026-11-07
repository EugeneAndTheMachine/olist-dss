{#-
    User chỉ đọc cho Power BI: chỉ thấy schema bi.
    View Postgres chạy với quyền của owner (user dbt) → powerbi_reader đọc được view
    mà không cần quyền trên dw / stg / meta. Gọi ở on-run-end mỗi lần dbt chạy (idempotent).
    alter default privileges: view dbt tạo lại sau này tự có quyền select.
-#}
{% macro grant_bi_reader() %}
    {%- set role = env_var('BI_READER_USER', 'powerbi_reader') -%}
    {%- set pw = env_var('BI_READER_PASSWORD', 'powerbi_reader') | replace("'", "''") -%}
    do $$
    begin
        if not exists (select from pg_roles where rolname = '{{ role }}') then
            create role {{ role }} login password '{{ pw }}';
        else
            alter role {{ role }} login password '{{ pw }}';
        end if;
    end
    $$;
    grant connect on database {{ target.dbname }} to {{ role }};
    grant usage on schema bi to {{ role }};
    grant select on all tables in schema bi to {{ role }};
    alter default privileges in schema bi grant select on tables to {{ role }};
{% endmacro %}
