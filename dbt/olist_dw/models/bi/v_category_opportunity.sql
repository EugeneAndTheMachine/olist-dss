with latest_run as (
    select model_run_id
    from {{ source('meta', 'model_registry') }}
    where model_name = 'p3_category_portfolio'
    order by trained_at desc
    limit 1
)

select o.*
from {{ source('ml_p3', 'category_opportunity') }} as o
join latest_run as l on l.model_run_id = o.model_run_id
