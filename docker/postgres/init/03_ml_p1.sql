-- P1 (Logistics Manager) — Bảng output ML (docs/refactor_plan.md mục 6.1, 6.5).
-- Append-only, mỗi dòng có model_run_id + model_version.
-- View bi.v_* chỉ lấy model_run_id mới nhất (join meta.model_registry theo trained_at).

-- ML-1a: Điểm rủi ro giao trễ tại thời điểm đặt đơn
create table if not exists ml.order_late_risk (
    order_id      text not null,
    risk_score    numeric(6, 5),
    risk_band     text,
    model_run_id  uuid not null,
    model_version text not null,
    scored_at     timestamptz not null default now()
);

-- ML-1a: Mức độ đóng góp của từng đặc trưng (feature importance / drivers) giải thích nguyên nhân trễ
create table if not exists ml.late_risk_drivers (
    feature       text not null,
    importance    numeric(10, 5),
    importance_pct numeric(8, 5),
    model_run_id  uuid not null,
    model_version text not null,
    created_at    timestamptz not null default now()
);

-- ML-1b: Kịch bản đặt k kho / hub (k = 1..8) theo weighted K-Means / p-median MILP
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

-- ML-1b: Toạ độ và lưu lượng phân bổ của từng kho / hub trong mỗi kịch bản
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

-- ML-1c: Kế hoạch nhu cầu shipper theo bang trong 3 tháng tới
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

