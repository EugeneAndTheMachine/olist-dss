{#-
    C-W9: fact_order_fulfillment — Accumulating snapshot (grain: 1 đơn).
    5 vai trò ngày được điền dần (purchase, approved, carrier, delivered, estimated); mốc chưa xảy ra → date_key = -1.
    Rules: BR-W2, BR-W5, BR-W6, BR-W11, BR-O2, BR-O3, BR-O4, BR-K2, BR-P1-1 (docs/business_rules.md).
-#}
with orders as (
    select * from {{ ref('stg_orders') }}
),

agg as (
    select * from {{ ref('int_order_agg') }}
),

primary_seller as (
    select * from {{ ref('int_order_primary_seller') }}
),

joined as (
    select
        o.*,
        m.customer_unique_id,
        m.customer_zip_prefix,
        a.item_count,
        a.order_value,
        a.freight_total,
        a.max_shipping_limit_date,
        ps.primary_seller_id
    from orders as o
    left join {{ ref('int_customer_map') }} as m on o.customer_id = m.customer_id
    left join agg as a on o.order_id = a.order_id
    left join primary_seller as ps on o.order_id = ps.order_id
),

final as (
    select
        j.order_id,
        {{ date_key('j.order_purchase_timestamp') }} as purchase_date_key,
        {{ date_key('j.order_approved_at') }} as approved_date_key,
        {{ date_key('j.order_delivered_carrier_date') }} as carrier_date_key,
        {{ date_key('j.order_delivered_customer_date') }} as delivered_date_key,
        {{ date_key('j.order_estimated_delivery_date') }} as estimated_date_key,
        {{ coalesce_key('c.customer_key') }} as customer_key,
        {{ coalesce_key('s.seller_key') }} as primary_seller_key,
        {{ coalesce_key('cg.geo_key') }} as customer_geo_key,
        {{ coalesce_key('s.seller_geo_key') }} as seller_geo_key,
        {{ coalesce_key('st.order_status_key') }} as order_status_key,
        coalesce(j.item_count, 0) as item_count,
        coalesce(j.order_value, 0) as order_value,
        coalesce(j.freight_total, 0) as freight_total,
        j.is_delivered::int as is_delivered,
        j.is_late::int as is_late,
        case
            when j.order_delivered_carrier_date > j.max_shipping_limit_date then 1
            else 0
        end as is_dispatch_late,
        (j.order_delivered_carrier_date is not null)::int as has_carrier_date,
        {{ lag_days('j.order_purchase_timestamp', 'j.order_approved_at') }} as approval_lag,
        {{ lag_days('j.order_approved_at', 'j.order_delivered_carrier_date') }} as dispatch_lag,
        {{ lag_days('j.order_delivered_carrier_date', 'j.order_delivered_customer_date') }} as transit_lag,
        case
            when j.is_delivered then {{ lag_days('j.order_purchase_timestamp', 'j.order_delivered_customer_date') }}
        end as delivery_lag,
        {{ lag_days('j.order_purchase_timestamp', 'j.order_estimated_delivery_date') }} as promised_lag,
        j.delay_days,
        round({{ haversine_km('sg.latitude', 'sg.longitude', 'cg.latitude', 'cg.longitude') }}::numeric, 1)
            as seller_customer_distance_km,
        j._dq_issue,
        current_timestamp as _dw_loaded_at,
        current_timestamp as _dw_updated_at
    from joined as j
    left join {{ ref('dim_customer') }} as c on j.customer_unique_id = c.customer_unique_id
    left join {{ ref('dim_geography') }} as cg on j.customer_zip_prefix = cg.zip_prefix
    left join {{ ref('dim_seller') }} as s
        on j.primary_seller_id = s.seller_id
        and j.order_purchase_timestamp::date between s.valid_from and s.valid_to
    left join {{ ref('dim_geography') }} as sg on s.seller_geo_key = sg.geo_key
    left join {{ ref('dim_order_status') }} as st on j.order_status = st.order_status
)

select * from final

