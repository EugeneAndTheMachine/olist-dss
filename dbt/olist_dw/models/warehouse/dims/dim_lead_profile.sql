{#-
    Junk dimension: tổ hợp thuộc tính hồ sơ seller khai khi chốt deal. Type 1.
    Thuộc tính chỉ tồn tại cho lead đã chốt → lead chưa chốt dùng key -1; KHÔNG dùng làm feature dự đoán conversion.
    Thuộc tính text không khai → 'unknown'; has_company / has_gtin null = không khai.
-#}
with profiles as (
    select distinct
        coalesce(business_segment, 'unknown') as business_segment,
        coalesce(lead_type, 'unknown') as lead_type,
        coalesce(lead_behaviour_profile, 'unknown') as lead_behaviour_profile,
        coalesce(business_type, 'unknown') as business_type,
        has_company,
        has_gtin,
        stock_band
    from {{ ref('stg_closed_deals') }}
),

final as (
    select
        {{ int_sk(['business_segment', 'lead_type', 'lead_behaviour_profile', 'business_type',
                   'has_company', 'has_gtin', 'stock_band']) }} as lead_profile_key,
        business_segment,
        lead_type,
        lead_behaviour_profile,
        business_type,
        has_company,
        has_gtin,
        stock_band,
        case stock_band
            when '1-5' then 1
            when '5-20' then 2
            when '20-50' then 3
            when '50-200' then 4
            when '200+' then 5
            else 99
        end as stock_band_sort
    from profiles

    union all

    select
        {{ unknown_key() }},
        'unknown',
        'unknown',
        'unknown',
        'unknown',
        null::boolean,
        null::boolean,
        'unknown',
        99
)

select * from final
