{#- P1: v_courier_plan — Chỉ lấy model_run_id mới nhất từ ml.courier_plan -#}
with latest_run as (
    select model_run_id
    from {{ source('meta', 'model_registry') }}
    where model_name = 'p1_courier_plan'
    order by trained_at desc
    limit 1
)

select
    c.month as "Forecast Month",
    c.state_code as "State Code",
    c.forecast_orders as "Forecast Delivered Orders",
    c.current_late_rate as "Current Late Rate",
    c.forecast_late_orders as "Forecast Late Orders",
    c.transit_share as "Transit Share",
    c.priority_score as "Courier Priority Score",
    c.priority_rank as "Priority Rank",
    c.recommended_focus as "Recommended Focus",
    c.model_run_id,
    c.model_version as "Model Version"
from {{ source('ml_p1', 'courier_plan') }} as c
inner join latest_run as l
    on c.model_run_id = l.model_run_id

