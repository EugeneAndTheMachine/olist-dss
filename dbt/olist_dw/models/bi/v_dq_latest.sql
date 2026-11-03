{#- Kết quả test dbt của lần chạy gần nhất (meta_publish.py ghi meta.dq_results sau mỗi dbt build). -#}
with latest_run as (
    select run_id
    from {{ source('meta', 'dq_results') }}
    order by executed_at desc nulls last
    limit 1
)

select
    r.run_id as "Run ID",
    r.test_name as "Test Name",
    r.test_type as "Test Type",
    r.model as "Model",
    case
        when r.model like 'stg\_%' or r.model like 'int\_%' then 'stg'
        when r.model like 'dim\_%' or r.model like 'fact\_%' then 'dw'
        when r.model like 'v\_%' then 'bi'
        else 'other'
    end as "Layer",
    r.status as "Status",
    case when r.status = 'pass' then 1 else 0 end as "Is Pass",
    coalesce(r.failures, 0) as "Failures",
    r.message as "Message",
    r.executed_at as "Executed At"
from {{ source('meta', 'dq_results') }} as r
inner join latest_run as l on r.run_id = l.run_id
