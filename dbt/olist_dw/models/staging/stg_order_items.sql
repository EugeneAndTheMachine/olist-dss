{#- Làm sạch text inline cho tới khi macro clean_text dùng chung (C-R1, owner C-S1) có trên main. -#}
with source as (
    select * from {{ source('raw', 'order_items') }}
),

deduped as (
    select
        *,
        row_number() over (partition by order_id, order_item_id order by _loaded_at desc) as _rn
    from source
),

typed as (
    select
        nullif(trim(order_id), '') as order_id,
        nullif(trim(order_item_id), '')::int as order_item_id,
        nullif(trim(product_id), '') as product_id,
        nullif(trim(seller_id), '') as seller_id,
        nullif(trim(shipping_limit_date), '')::timestamp as shipping_limit_raw,
        nullif(trim(price), '')::numeric(12, 2) as price,
        nullif(trim(freight_value), '')::numeric(12, 2) as freight_value,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
),

{#- Khoảng theo dim_date (BR-W3); var có giá trị mặc định cho tới khi C-W1 thêm vào dbt_project.yml. -#}
final as (
    select
        order_id,
        order_item_id,
        product_id,
        seller_id,
        case
            when shipping_limit_raw >= '{{ var("date_spine_start", "2016-01-01") }}'::date
             and shipping_limit_raw < '{{ var("date_spine_end", "2019-12-31") }}'::date + 1
                then shipping_limit_raw
        end as shipping_limit_at,
        price,
        freight_value,
        case
            when shipping_limit_raw < '{{ var("date_spine_start", "2016-01-01") }}'::date
              or shipping_limit_raw >= '{{ var("date_spine_end", "2019-12-31") }}'::date + 1
                then 'shipping_limit_out_of_range'
        end as _dq_issue,
        _batch_id,
        _loaded_at
    from typed
)

select * from final
