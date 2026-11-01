{#-
    S1 (A4): 610 product thiếu category → 'unknown'; 4 product weight 0 → null; 2 product thiếu kích thước.
    Sửa tên cột sai chính tả gốc *_lenght → *_length. Bản dịch + category_group được join ở dim_product.
-#}
with source as (
    select * from {{ source('raw', 'products') }}
),

deduped as (
    select
        *,
        row_number() over (partition by product_id order by _loaded_at desc) as _rn
    from source
),

typed as (
    select
        {{ clean_text('product_id') }} as product_id,
        lower({{ clean_text('product_category_name') }}) as product_category_name,
        {{ clean_text('product_name_lenght') }}::numeric::int as product_name_length,
        {{ clean_text('product_description_lenght') }}::numeric::int as product_description_length,
        {{ clean_text('product_photos_qty') }}::numeric::int as product_photos_qty,
        {{ clean_text('product_weight_g') }}::numeric as product_weight_g,
        {{ clean_text('product_length_cm') }}::numeric as product_length_cm,
        {{ clean_text('product_height_cm') }}::numeric as product_height_cm,
        {{ clean_text('product_width_cm') }}::numeric as product_width_cm,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
),

final as (
    select
        product_id,
        coalesce(product_category_name, 'unknown') as product_category_name,
        product_name_length,
        product_description_length,
        product_photos_qty,
        nullif(product_weight_g, 0) as product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm,
        product_length_cm * product_height_cm * product_width_cm as product_volume_cm3,
        nullif(concat_ws(',',
            case when product_category_name is null then 'missing_category' end,
            case when product_weight_g = 0 then 'zero_weight' end
        ), '') as _dq_issue,
        _batch_id,
        _loaded_at
    from typed
)

select * from final
