select
    category_key,
    category_pt,
    category_en,
    category_name,
    category_group,
    is_rankable
from {{ ref('dim_category') }}
