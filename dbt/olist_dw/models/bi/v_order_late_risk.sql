{#- P1: v_order_late_risk — Chỉ lấy model_run_id mới nhất từ ml.order_late_risk -#}
with latest_run as (
    select model_run_id
    from {{ source('meta', 'model_registry') }}
    where model_name = 'p1_late_risk'
    order by trained_at desc
    limit 1
)

select
    r.order_id as "Order ID",
    r.risk_score as "Late Risk Score",
    r.risk_band as "Late Risk Band",
    r.model_run_id,
    r.model_version as "Model Version",
    r.scored_at as "Scored At"
from {{ source('ml_p1', 'order_late_risk') }} as r
inner join latest_run as l
    on r.model_run_id = l.model_run_id

