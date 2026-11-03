{#-
    Bán hàng — 1 dòng / item (grain giữ nguyên fact_order_item).
    GMV = Σ "Item Price" chỉ đơn counts_as_sale → DAX lọc qua v_dim_order_status[Counts As Sale].
-#}
select
    order_id as "Order ID",
    order_item_id as "Order Item ID",
    purchase_date_key,
    shipping_limit_date_key,
    customer_key,
    product_key,
    seller_key,
    customer_geo_key,
    seller_geo_key,
    order_status_key,
    item_price as "Item Price",
    freight_value as "Freight Value",
    item_total as "Item Total",
    item_count as "Item Count"
from {{ ref('fact_order_item') }}
