{#- P1: v_late_risk_drivers — Chỉ lấy model_run_id mới nhất từ ml.late_risk_drivers -#}
{{ config(pre_hook="{{ ensure_ml_p1_tables() }}") }}
with latest_run as (
    select model_run_id
    from {{ source('meta', 'model_registry') }}
    where model_name = 'p1_late_risk'
    order by trained_at desc
    limit 1
)

select
    d.feature as "Feature",
    d.importance as "Importance",
    d.importance_pct as "Importance Share",
    d.model_run_id,
    d.model_version as "Model Version"
from {{ source('ml_p1', 'late_risk_drivers') }} as d
inner join latest_run as l
    on d.model_run_id = l.model_run_id

