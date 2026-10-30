-- Bảng output ML (CLAUDE.md mục 13). Append-only, mỗi dòng có model_run_id + model_version.
-- View bi.v_* chỉ lấy model_run_id mới nhất (join meta.model_registry theo trained_at).

-- M3
create table if not exists ml.order_late_risk (
    order_id      text not null,
    risk_score    numeric(6, 5),
    risk_band     text,
    model_run_id  uuid not null,
    model_version text not null,
    scored_at     timestamptz not null default now()
);

create table if not exists ml.promise_whatif (
    route_seller_state   text not null,
    route_customer_state text not null,
    buffer_days          integer not null check (buffer_days between -5 and 7),
    orders               bigint,
    late_orders          bigint,
    late_rate            numeric(8, 5),
    avg_promised_days    numeric(10, 3),
    model_run_id         uuid not null,
    model_version        text not null,
    created_at           timestamptz not null default now()
);

-- M4
create table if not exists ml.customer_segment_history (
    customer_unique_id text not null,
    as_of_date         date not null,
    segment            text not null,
    r                  numeric,
    f                  numeric,
    m                  numeric,
    had_late           boolean,
    low_review         boolean,
    model_run_id       uuid not null,
    model_version      text not null
);

create table if not exists ml.voucher_allocation (
    scenario_id        text not null,
    budget             numeric(14, 2) not null,
    customer_unique_id text not null,
    segment            text,
    expected_value     numeric(14, 2),
    voucher_value      numeric(14, 2),
    model_run_id       uuid not null,
    model_version      text not null
);

-- M5
create table if not exists ml.gmv_forecast (
    month          date not null,
    category_group text not null,
    region_name    text not null,
    yhat           numeric(16, 2),
    yhat_lower     numeric(16, 2),
    yhat_upper     numeric(16, 2),
    model_run_id   uuid not null,
    model_version  text not null
);

-- M6
create table if not exists ml.seller_risk_score (
    seller_id     text not null,
    as_of_month   date not null,
    risk_score    numeric(6, 5),
    risk_band     text,
    top_drivers   text,
    model_run_id  uuid not null,
    model_version text not null
);

create table if not exists ml.channel_value (
    origin           text not null,
    leads            bigint,
    won              bigint,
    conversion       numeric(8, 5),
    gmv_90d_per_lead numeric(14, 2),
    model_run_id     uuid not null,
    model_version    text not null
);

-- M7
create table if not exists ml.recommendations (
    rec_id         text not null,
    decision_maker text not null,
    subject_type   text not null,
    subject_id     text not null,
    action         text not null,
    rationale      text,
    score          numeric(10, 5),
    model_run_id   uuid not null,
    model_version  text not null,
    status         text not null default 'proposed',
    created_at     timestamptz not null default now()
);
