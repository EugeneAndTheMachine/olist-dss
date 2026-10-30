{#- Model mẫu cho dim: khoá băm từ natural key + dòng unknown -1 -#}
with status_map as (
    select
        order_status,
        status_group,
        counts_as_sale
    from {{ ref('order_status_map') }}
),

final as (
    select
        {{ int_sk(['order_status']) }} as order_status_key,
        order_status,
        status_group,
        counts_as_sale
    from status_map

    union all

    select
        {{ unknown_key() }} as order_status_key,
        'unknown' as order_status,
        'Unknown' as status_group,
        false as counts_as_sale
)

select
    order_status_key,
    order_status,
    status_group,
    counts_as_sale
from final
