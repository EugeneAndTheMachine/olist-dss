{#-
    Đảm bảo 5 bảng output ML của P1 tồn tại trong schema ml trước khi tạo view bi.v_*
    (vì container Postgres đang chạy không tự chạy lại docker/postgres/init/03_ml_p1.sql).
-#}
{% macro ensure_ml_p1_tables() %}
create table if not exists ml.order_late_risk (
    order_id      text not null,
    risk_score    numeric(6, 5),
    risk_band     text,
    model_run_id  uuid not null,
    model_version text not null,
    scored_at     timestamptz not null default now()
);

create table if not exists ml.late_risk_drivers (
    feature        text not null,
    importance     numeric(10, 5),
    importance_pct numeric(8, 5),
    model_run_id   uuid not null,
    model_version  text not null,
    created_at     timestamptz not null default now()
);

create table if not exists ml.hub_scenario (
    scenario_id          text not null,
    k                    integer not null,
    weight_basis         text not null,
    method               text not null,
    avg_distance_km      numeric(10, 2),
    p90_distance_km      numeric(10, 2),
    demand_within_300km  numeric(8, 5),
    predicted_late_rate  numeric(8, 5),
    model_run_id         uuid not null,
    model_version        text not null,
    created_at           timestamptz not null default now()
);

create table if not exists ml.hub_location (
    scenario_id              text not null,
    k                        integer not null,
    weight_basis             text not null,
    hub_rank                 integer not null,
    geo_cell_id              text not null,
    lat                      numeric(9, 5),
    lng                      numeric(9, 5),
    state_code               text,
    assigned_orders          bigint,
    assigned_late_orders     bigint,
    avg_assigned_distance_km numeric(10, 2),
    model_run_id             uuid not null,
    model_version            text not null,
    created_at               timestamptz not null default now()
);

create table if not exists ml.courier_plan (
    month                date not null,
    state_code           text not null,
    forecast_orders      numeric(12, 2),
    current_late_rate    numeric(8, 5),
    forecast_late_orders numeric(12, 2),
    transit_share        numeric(8, 5),
    priority_score       numeric(10, 4),
    priority_rank        integer,
    recommended_focus    text,
    model_run_id         uuid not null,
    model_version        text not null,
    created_at           timestamptz not null default now()
);
{% endmacro %}

