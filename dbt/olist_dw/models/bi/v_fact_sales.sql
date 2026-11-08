select
    purchase_date_key,
    shipping_limit_date_key,
    customer_key,
    product_key,
    seller_key,
    customer_geo_key,
    seller_geo_key,
    order_status_key,
    order_id,
    order_item_id,
    seller_id,
    item_price,
    freight_value,
    item_total,
    item_count
from {{ ref('fact_order_item') }}
