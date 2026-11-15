{#-
    Interface ổn định cho các fact: customer_id (theo đơn) → customer_unique_id (người mua thật),
    kèm địa chỉ giao của chính đơn đó. Fact cấp đơn lấy customer_geo_key từ zip ở đây;
    dim_customer chọn zip của đơn đầu tiên (BR-CS3-2, BR-W8).
-#}
select
    customer_id,
    customer_unique_id,
    customer_zip_prefix,
    customer_city,
    customer_state
from {{ ref('stg_customers') }}
