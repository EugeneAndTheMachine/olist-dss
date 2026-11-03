select
    product_key,
    product_id as "Product ID",
    category_pt as "Category (PT)",
    category_en as "Category",
    category_group as "Category Group",
    photos_qty as "Photos Qty",
    name_length as "Name Length",
    description_length as "Description Length",
    weight_g as "Weight (g)",
    length_cm as "Length (cm)",
    height_cm as "Height (cm)",
    width_cm as "Width (cm)",
    volume_cm3 as "Volume (cm3)",
    weight_band as "Weight Band",
    case weight_band
        when '< 0.5 kg' then 1 when '0.5–2 kg' then 2 when '2–5 kg' then 3
        when '5–10 kg' then 4 when '>= 10 kg' then 5 else 9
    end as "Weight Band Sort",
    size_band as "Size Band",
    case size_band
        when '< 1 L' then 1 when '1–10 L' then 2 when '10–50 L' then 3
        when '>= 50 L' then 4 else 9
    end as "Size Band Sort"
from {{ ref('dim_product') }}
