-- Lấy đúng run forecast mà run portfolio mới nhất đã dùng, để trang 7 không ghép dự báo và ranking của hai lần chạy.
with latest_portfolio as (
    select model_run_id
    from {{ source('meta', 'model_registry') }}
    where model_name = 'p3_category_portfolio'
    order by trained_at desc
    limit 1
),

latest_run as (
    select distinct o.forecast_model_run_id as model_run_id
    from {{ source('ml_p3', 'category_opportunity') }} as o
    join latest_portfolio as p on p.model_run_id = o.model_run_id
)

select
    f.month,
    to_char(f.month, 'YYYYMMDD')::int as month_date_key,
    f.category_level,
    f.category_code,
    f.category_key,
    f.category_group,
    f.metric,
    f.yhat,
    f.yhat_lower,
    f.yhat_upper,
    f.actual,
    f.is_backtest,
    f.is_sparse,
    f.model_name,
    f.model_version,
    f.model_run_id
from {{ source('ml_p3', 'category_forecast') }} as f
join latest_run as l on l.model_run_id = f.model_run_id
