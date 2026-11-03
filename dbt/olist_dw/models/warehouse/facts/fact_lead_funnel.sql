{#-
    Accumulating snapshot — grain: 1 MQL. Mốc: first_contact → won → first_sale (-1 khi chưa xảy ra).
    - gmv_first_90_days = Σ item_price (đơn counts_as_sale) của seller trong [won_date, won_date + 90 ngày].
    - has_full_90d_window: won_date + 90 <= ANALYSIS_END (S1: won_date kéo tới 2018-11, đơn hàng hết 2018-08)
      → chỉ so giá trị kênh trên các lead có cờ này.
    - declared_*: seller tự khai → độ tin thấp.
    - S1: 1 deal won_date trước first_contact_date → days_to_close = null, _dq_issue.
-#}
with mql as (
    select * from {{ ref('stg_mql') }}
),

deals as (
    select * from {{ ref('stg_closed_deals') }}
),

sales as (
    select
        i.seller_id,
        o.order_purchase_timestamp::date as purchase_date,
        i.price
    from {{ ref('stg_order_items') }} as i
    inner join {{ ref('stg_orders') }} as o on i.order_id = o.order_id
    inner join {{ ref('order_status_map') }} as s on o.order_status = s.order_status
    where s.counts_as_sale
),

first_sale as (
    select seller_id, min(purchase_date) as first_sale_date
    from sales
    group by seller_id
),

gmv_90d as (
    select
        d.mql_id,
        sum(s.price) as gmv_first_90_days
    from deals as d
    inner join sales as s
        on d.seller_id = s.seller_id
        and s.purchase_date between d.won_date::date and d.won_date::date + 90
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
        d.seller_id,
        d.sdr_id,
        d.sr_id,
        coalesce(d.business_segment, 'unknown') as business_segment,
        coalesce(d.lead_type, 'unknown') as lead_type,
        coalesce(d.lead_behaviour_profile, 'unknown') as lead_behaviour_profile,
        coalesce(d.business_type, 'unknown') as business_type,
        coalesce(d.has_company::text, 'unknown') as has_company,
        coalesce(d.has_gtin::text, 'unknown') as has_gtin,
        coalesce(d.average_stock, 'unknown') as stock_band,
        d.declared_product_catalog_size,
        d.declared_monthly_revenue,
        fs.first_sale_date,
        g.gmv_first_90_days
    from mql as m
    left join deals as d on m.mql_id = d.mql_id
    left join first_sale as fs on d.seller_id = fs.seller_id
    left join gmv_90d as g on m.mql_id = g.mql_id
),

final as (
    select
        j.mql_id,
        {{ date_key('j.first_contact_date') }} as first_contact_date_key,
        {{ date_key('j.won_date') }} as won_date_key,
        {{ date_key('j.first_sale_date') }} as first_sale_date_key,
        {{ coalesce_key('o.lead_origin_key') }} as lead_origin_key,
        case
            when j.is_won then {{ int_sk(['j.business_segment', 'j.lead_type', 'j.lead_behaviour_profile',
                                          'j.business_type', 'j.has_company', 'j.has_gtin', 'j.stock_band']) }}
            else {{ unknown_key() }}
        end as lead_profile_key,
        case
            when j.is_won then {{ int_sk(["coalesce(j.sdr_id, 'unknown')", "coalesce(j.sr_id, 'unknown')"]) }}
            else {{ unknown_key() }}
        end as sales_rep_key,
        {{ coalesce_key('s.seller_key') }} as seller_key,
        1 as lead_count,
        j.is_won::int as is_won,
        (j.first_sale_date is not null)::int as has_first_sale,
        case
            when j.won_date::date >= j.first_contact_date then j.won_date::date - j.first_contact_date
        end as days_to_close,
        j.declared_product_catalog_size,
        j.declared_monthly_revenue,
        case when j.is_won then coalesce(j.gmv_first_90_days, 0) else 0 end as gmv_first_90_days,
        (j.is_won and j.won_date::date + 90 <= '{{ var("analysis_end") }}'::date)::int as has_full_90d_window,
        case when j.won_date::date < j.first_contact_date then 'won_before_contact' end as _dq_issue,
        current_timestamp as _dw_loaded_at
    from joined as j
    left join {{ ref('dim_lead_origin') }} as o
        on j.origin = o.origin
        and j.landing_page_id is not distinct from o.landing_page_id
    left join {{ ref('dim_seller') }} as s
        on j.seller_id = s.seller_id
        and j.won_date::date between s.valid_from and s.valid_to
)

select * from final
