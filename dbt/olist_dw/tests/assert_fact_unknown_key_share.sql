{{ config(severity='warn') }}
-- Mọi fact có tỷ lệ key -1 < 1% (implementation.md mục 11.1, warn). Trả về fact × key vượt ngưỡng.
-- Đơn không có item (S1: 775 đơn = 0,78%) hợp lệ có primary_seller_key = -1 nên vẫn dưới ngưỡng.
{% set checks = [
    ('fact_order_item', ['customer_key', 'product_key', 'seller_key', 'customer_geo_key', 'seller_geo_key', 'order_status_key']),
    ('fact_payment', ['customer_key', 'payment_type_key', 'order_status_key']),
    ('fact_order_fulfillment', ['customer_key', 'primary_seller_key', 'customer_geo_key', 'order_status_key']),
    ('fact_review', ['customer_key', 'customer_geo_key', 'order_status_key']),
    ('fact_seller_month', ['seller_key', 'seller_geo_key']),
    ('fact_seller_product_activity', ['seller_key', 'product_key']),
    ('fact_lead_funnel', ['lead_origin_key']),
] %}

{% for model, keys in checks %}
{% for key in keys %}
select
    '{{ model }}' as fact_name,
    '{{ key }}' as key_name,
    count(*) filter (where {{ key }} = -1) as unknown_rows,
    count(*) as total_rows
from {{ ref(model) }}
having count(*) filter (where {{ key }} = -1) > 0.01 * count(*)
{% if not loop.last %}union all{% endif %}
{% endfor %}
{% if not loop.last %}union all{% endif %}
{% endfor %}
