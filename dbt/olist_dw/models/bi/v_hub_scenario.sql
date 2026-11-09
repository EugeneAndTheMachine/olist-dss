{#- P1: v_hub_scenario — Chỉ lấy model_run_id mới nhất từ ml.hub_scenario -#}
{{ config(pre_hook="{{ ensure_ml_p1_tables() }}") }}
with latest_run as (
    select model_run_id
    from {{ source('meta', 'model_registry') }}
    where model_name = 'p1_hub_placement'
    order by trained_at desc
    limit 1
)

select
    s.scenario_id as "Scenario ID",
    s.k as "Hub Count (k)",
    s.weight_basis as "Weight Basis",
    s.method as "Method",
    s.avg_distance_km as "Avg Distance (km)",
    s.p90_distance_km as "P90 Distance (km)",
    s.demand_within_300km as "Demand Within 300km Share",
    s.predicted_late_rate as "Predicted Late Rate",
    s.model_run_id,
    s.model_version as "Model Version"
from {{ source('ml_p1', 'hub_scenario') }} as s
inner join latest_run as l
    on s.model_run_id = l.model_run_id

