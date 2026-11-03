{#- Role-playing geography: seller geo. Cùng nguồn dw.dim_geography, tên cột có tiền tố để không lẫn trong Power BI. -#}
select
    geo_key as seller_geo_key,
    zip_prefix as "Seller Zip Prefix",
    city as "Seller City",
    state_code as "Seller State",
    state_name as "Seller State Name",
    region_name as "Seller Region",
    latitude as "Seller Latitude",
    longitude as "Seller Longitude",
    state_population as "Seller State Population"
from {{ ref('dim_geography') }}
