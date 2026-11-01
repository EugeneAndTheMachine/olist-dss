{#-
    Olist cấp customer_id mới cho mỗi đơn → map customer_id → customer_unique_id (người thật).
    Kèm địa chỉ giao của đơn đó (zip, city, state) để fact lấy customer_geo_key theo từng đơn.
-#}
select
    customer_id,
    customer_unique_id,
    customer_zip_prefix,
    customer_city,
    customer_state
from {{ ref('stg_customers') }}
