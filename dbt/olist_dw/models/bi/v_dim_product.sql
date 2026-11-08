select
    product_key,
    product_id,
    category_key,
    photos_qty,
    weight_g,
    volume_cm3,
    weight_band,
    size_band
from {{ ref('dim_product') }}
