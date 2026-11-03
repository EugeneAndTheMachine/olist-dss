{#-
    Giao đơn — 1 dòng / đơn (accumulating snapshot). Date key = -1 khi mốc chưa xảy ra.
    Tỷ lệ / trung bình luôn = Σ tử số / Σ mẫu số (docs/kpi_dictionary.md).
-#}
select
    order_id as "Order ID",
    purchase_date_key,
    approved_date_key,
    carrier_date_key,
    delivered_date_key,
    estimated_date_key,
    customer_key,
    primary_seller_key as seller_key,
    customer_geo_key,
    seller_geo_key,
    order_status_key,
    item_count as "Item Count",
    order_value as "Order Value",
    freight_total as "Freight Total",
    is_delivered as "Is Delivered",
    is_late as "Is Late",
    is_dispatch_late as "Is Dispatch Late",
    has_carrier_date as "Has Carrier Date",
    approval_lag as "Approval Lag (days)",
    dispatch_lag as "Dispatch Lag (days)",
    transit_lag as "Transit Lag (days)",
    delivery_lag as "Delivery Lag (days)",
    promised_lag as "Promised Lag (days)",
    delay_days as "Delay Days",
    seller_customer_distance_km as "Distance (km)",
    _dq_issue as "DQ Issue"
from {{ ref('fact_order_fulfillment') }}
