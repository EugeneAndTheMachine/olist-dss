{#- P2: v_fact_geo_month — fact_geo_month trong cửa sổ phân tích (BR-W4). Nối v_dim_customer_geo cho measure cầu,
    v_dim_seller_geo cho measure cung (cùng geo_key), v_dim_date qua month_date_key. -#}
select
    geo_key,
    month_date_key,
    to_date(month_date_key::text, 'YYYYMMDD') as month_date,
    orders_placed,
    gmv_placed,
    freight_placed,
    orders_local,
    gmv_local,
    customers_active,
    customers_new,
    delivered_orders,
    late_orders,
    delivery_lag_sum,
    orders_shipped,
    gmv_sold,
    sellers_active
from {{ ref('fact_geo_month') }}
where month_date_key between {{ var('analysis_start') | replace('-', '') }} and {{ var('analysis_end') | replace('-', '') }}
