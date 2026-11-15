{#- P1: v_hub_location — Chỉ lấy model_run_id mới nhất từ ml.hub_location -#}
with latest_run as (
    select model_run_id
    from {{ source('meta', 'model_registry') }}
    where model_name = 'p1_hub_placement'
    order by trained_at desc
    limit 1
)

select
    h.scenario_id as "Scenario ID",
    h.k as "Hub Count (k)",
    h.weight_basis as "Weight Basis",
    h.hub_rank as "Hub Rank",
    h.geo_cell_id as "Geo Cell ID",
    h.lat as "Latitude",
    h.lng as "Longitude",
    h.state_code as "State Code",
    h.assigned_orders as "Assigned Orders",
    h.assigned_late_orders as "Assigned Late Orders",
    h.avg_assigned_distance_km as "Avg Assigned Distance (km)",
    h.model_run_id,
    h.model_version as "Model Version"
from {{ source('ml_p1', 'hub_location') }} as h
inner join latest_run as l
    on h.model_run_id = l.model_run_id

