{#-
    Accumulating snapshot — grain: 1 MQL. 3 mốc được điền dần: first_contact → won → first_sale; mốc chưa xảy ra → -1.
    Lead chưa chốt: lead_profile_key, sales_rep_key, seller_key = -1 (thuộc tính chỉ có cho lead đã chốt).
    Cờ dạng 0/1 (integer): conversion = Σ is_won / Σ lead_count; days to close = Σ days_to_close / Σ is_won.
    Bán hàng (first sale, GMV 90 ngày) chỉ tính đơn counts_as_sale, theo đúng định nghĩa GMV (mục 8).
    gmv_first_90_days: Σ item_price trong [won_date, won_date + 90 ngày). Chỉ so kênh trên lead has_full_90d_window = 1
    (S1: won_date kéo tới 2018-11-14, sau ANALYSIS_END → cửa sổ bị cắt).
    S1: 1 deal won_date trước first_contact_date → days_to_close = null + _dq_issue.
-#}
with mql as (
    select * from {{ ref('stg_mql') }}
),

deals as (
    select
        *,
        coalesce(business_segment, 'unknown') as business_segment_k,
        coalesce(lead_type, 'unknown') as lead_type_k,
        coalesce(lead_behaviour_profile, 'unknown') as lead_behaviour_profile_k,
        coalesce(business_type, 'unknown') as business_type_k
    from {{ ref('stg_closed_deals') }}
),

sale_items as (
    select
        i.seller_id,
        o.order_purchase_timestamp,
        i.price
    from {{ ref('stg_order_items') }} as i
    inner join {{ ref('stg_orders') }} as o on i.order_id = o.order_id
    inner join {{ ref('dim_order_status') }} as st on o.order_status = st.order_status
    where st.counts_as_sale
),

seller_sales as (
    select
        d.mql_id,
        min(s.order_purchase_timestamp) as first_sale_ts,
        sum(s.price) filter (
            where s.order_purchase_timestamp >= d.won_date::date
            and s.order_purchase_timestamp < d.won_date::date + 90
        ) as gmv_first_90_days
    from deals as d
    inner join sale_items as s on d.seller_id = s.seller_id
    group by d.mql_id
),

joined as (
    select
        m.mql_id,
        m.first_contact_date,
        m.origin,
        m.landing_page_id,
        d.mql_id is not null as is_won,
        d.won_date,
        d.won_date::date - m.first_contact_date as days_to_close_raw,
        d.seller_id,
        d.sdr_id,
        d.sr_id,
        d.business_segment_k,
        d.lead_type_k,
        d.lead_behaviour_profile_k,
        d.business_type_k,
        d.has_company,
        d.has_gtin,
        d.stock_band,
        d.declared_product_catalog_size,
        d.declared_monthly_revenue,
        ss.first_sale_ts,
        ss.gmv_first_90_days
    from mql as m
    left join deals as d on m.mql_id = d.mql_id
    left join seller_sales as ss on m.mql_id = ss.mql_id
),

final as (
    select
        j.mql_id,
        {{ date_key('j.first_contact_date') }} as first_contact_date_key,
        {{ date_key('j.won_date') }} as won_date_key,
        {{ date_key('j.first_sale_ts') }} as first_sale_date_key,
        {{ coalesce_key('o.lead_origin_key') }} as lead_origin_key,
        {{ coalesce_key('p.lead_profile_key') }} as lead_profile_key,
        {{ coalesce_key('r.sales_rep_key') }} as sales_rep_key,
        {{ coalesce_key('s.seller_key') }} as seller_key,
        1 as lead_count,
        j.is_won::int as is_won,
        case when j.days_to_close_raw >= 0 then j.days_to_close_raw end as days_to_close,
        j.declared_product_catalog_size as declared_catalog_size,
        j.declared_monthly_revenue,
        case when j.is_won then coalesce(j.gmv_first_90_days, 0) end as gmv_first_90_days,
        (j.is_won and j.won_date::date + 90 <= '{{ var("analysis_end") }}'::date)::int as has_full_90d_window,
        case when j.days_to_close_raw < 0 then 'won_before_first_contact' end as _dq_issue,
        current_timestamp as _dw_loaded_at,
        current_timestamp as _dw_updated_at
    from joined as j
    left join {{ ref('dim_lead_origin') }} as o
        on j.origin = o.origin
        and j.landing_page_id = o.landing_page_id
    left join {{ ref('dim_lead_profile') }} as p
        on j.business_segment_k = p.business_segment
        and j.lead_type_k = p.lead_type
        and j.lead_behaviour_profile_k = p.lead_behaviour_profile
        and j.business_type_k = p.business_type
        and j.has_company is not distinct from p.has_company
        and j.has_gtin is not distinct from p.has_gtin
        and j.stock_band = p.stock_band
        and p.lead_profile_key <> {{ unknown_key() }}
    left join {{ ref('dim_sales_rep') }} as r
        on j.sdr_id = r.sdr_id
        and j.sr_id = r.sr_id
    left join {{ ref('dim_seller') }} as s
        on j.seller_id = s.seller_id
        and j.won_date::date between s.valid_from and s.valid_to
)

select * from final
