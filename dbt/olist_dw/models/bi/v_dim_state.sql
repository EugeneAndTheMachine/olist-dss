{#- C-B1: v_dim_state — 1 dòng / bang (+ 'NA' cho member -1 của dim_geography). Thuộc tính cấp bang: vùng, dân số (BR-W12). -#}
select state_code, state_name, region_name, ibge_state_id, population_2018 as state_population
from {{ ref('br_states') }}

union all

select 'NA', 'Unknown', 'Unknown', null, null
