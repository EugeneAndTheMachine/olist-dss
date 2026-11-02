{#-
    Deal đã chốt (842). Thuộc tính profile chỉ có cho lead đã chốt → không dùng làm feature conversion.
    S1 (A6): chỉ 380 / 842 seller_id có trong sellers; 1 deal won_date trước first_contact_date (giữ, gắn cờ ở fact).
    S5: average_stock → stock_band (giá trị ngoài 5 dải hoặc null → 'unknown'); declared_monthly_revenue = 0
    ở 797 / 842 deal → coi là không khai (null), để trung bình không bị kéo về 0.
-#}
with source as (
    select * from {{ source('raw', 'closed_deals') }}
),

deduped as (
    select
        *,
        row_number() over (partition by mql_id order by _loaded_at desc) as _rn
    from source
)

select
    {{ clean_text('mql_id') }} as mql_id,
    {{ clean_text('seller_id') }} as seller_id,
    {{ clean_text('sdr_id') }} as sdr_id,
    {{ clean_text('sr_id') }} as sr_id,
    {{ clean_text('won_date') }}::timestamp as won_date,
    lower({{ clean_text('business_segment') }}) as business_segment,
    lower({{ clean_text('lead_type') }}) as lead_type,
    lower({{ clean_text('lead_behaviour_profile') }}) as lead_behaviour_profile,
    {{ to_bool('has_company') }} as has_company,
    {{ to_bool('has_gtin') }} as has_gtin,
    lower({{ clean_text('average_stock') }}) as average_stock,
    case
        when lower({{ clean_text('average_stock') }}) in ('1-5', '5-20', '20-50', '50-200', '200+')
            then lower({{ clean_text('average_stock') }})
        else 'unknown'
    end as stock_band,
    lower({{ clean_text('business_type') }}) as business_type,
    {{ clean_text('declared_product_catalog_size') }}::numeric as declared_product_catalog_size,
    nullif({{ clean_text('declared_monthly_revenue') }}::numeric, 0) as declared_monthly_revenue,
    _batch_id,
    _loaded_at::timestamptz as _loaded_at
from deduped
where _rn = 1
