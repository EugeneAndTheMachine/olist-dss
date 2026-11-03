{#- Role-playing geography: customer geo. Cùng nguồn dw.dim_geography, tên cột có tiền tố để không lẫn trong Power BI. -#}
select
    geo_key as customer_geo_key,
    zip_prefix as "Customer Zip Prefix",
    city as "Customer City",
    state_code as "Customer State",
    state_name as "Customer State Name",
    region_name as "Customer Region",
    latitude as "Customer Latitude",
    longitude as "Customer Longitude",
    state_population as "Customer State Population"
from {{ ref('dim_geography') }}
