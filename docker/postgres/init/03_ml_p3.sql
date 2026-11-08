-- Output ML của P3 (ML-3a forecast, ML-3b portfolio). Append-only theo model_run_id; view bi lấy run mới nhất.
-- Idempotent: make db-init áp lại được trên DB đang có.
create table if not exists ml.category_forecast (
    month          date not null,
    category_level text not null check (category_level in ('category', 'group')),
    category_code  text not null,
    category_key   bigint not null,
    category_group text not null,
    metric         text not null check (metric in ('gmv', 'orders')),
    yhat           numeric,
    yhat_lower     numeric,
    yhat_upper     numeric,
    model_name     text not null,
    is_backtest    smallint not null,
    actual         numeric,
    model_run_id   uuid not null,
    model_version  text not null
);

create table if not exists ml.category_opportunity (
    category_code            text not null,
    gmv_share                numeric,
    forecast_growth          numeric,
    avg_score                numeric,
    late_rate                numeric,
    hhi                      numeric,
    portfolio_class          text,
    quality_flag             smallint,
    opportunity_score        numeric,
    rank                     int,
    category_key             bigint not null,
    category_group           text,
    gmv_12m                  numeric,
    yoy_growth               numeric,
    relative_growth          numeric,
    relative_forecast_growth numeric,
    low_score_rate           numeric,
    freight_ratio            numeric,
    c_size                   numeric,
    c_growth                 numeric,
    c_forecast               numeric,
    c_satisfaction           numeric,
    c_ontime                 numeric,
    c_freight                numeric,
    recruit_sellers_flag     smallint,
    low_volume_flag          smallint,
    recommended_action       text,
    forecast_model_run_id    uuid,
    model_run_id             uuid not null,
    model_version            text not null
);

create index if not exists category_forecast_run_idx on ml.category_forecast (model_run_id);
create index if not exists category_opportunity_run_idx on ml.category_opportunity (model_run_id);
