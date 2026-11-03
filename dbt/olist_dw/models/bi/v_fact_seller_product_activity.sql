{#- Factless — 1 seller bán 1 sản phẩm trong 1 tháng. Đếm dòng = số listing hoạt động. -#}
select
    month_date_key,
    seller_key,
    product_key
from {{ ref('fact_seller_product_activity') }}
