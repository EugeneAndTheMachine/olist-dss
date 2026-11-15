{#-
    C-W4: dim_seller — SCD Type 2 trên seller_tier (BR-W10), Type 1 trên các cột còn lại. 1 dòng / phiên bản seller.
    Quy ước (BR-CW4-0, khớp BR-CW8-1 / BR-CW10-1): khoảng đóng [valid_from, valid_to]; phiên bản đầu từ 1900-01-01,
    phiên bản hiện hành tới 9999-12-31; fact tra bằng ngày mua: purchase::date between valid_from and valid_to.

    Bước 1 (PR này): mỗi seller 1 phiên bản, seller_tier = 'Not scored'.
    Bước 2: thêm phiên bản theo tier (int_seller_month_metrics + seed seller_tier_rules). seller_key của phiên bản đầu
    không đổi vì valid_from vẫn là 1900-01-01, nên fact không phải build lại khoá.
-#}
with versions as (
    select
        s.seller_id,
        s.seller_zip_prefix,
        1 as version_no,
        'Not scored'::text as seller_tier,
        null::text as tier_rule_version,
        '1900-01-01'::date as valid_from,
        '9999-12-31'::date as valid_to,
        1::smallint as is_current
    from {{ ref('stg_sellers') }} as s
)

select
    {{ int_sk(['v.seller_id', 'v.valid_from']) }} as seller_key,
    v.seller_id,
    v.version_no,
    {{ coalesce_key('g.geo_key') }} as seller_geo_key,
    v.seller_tier,
    v.tier_rule_version,
    v.valid_from,
    v.valid_to,
    v.is_current
from versions as v
left join {{ ref('dim_geography') }} as g on g.zip_prefix = v.seller_zip_prefix

union all

select
    {{ unknown_key() }}, 'unknown', 1, {{ unknown_key() }}, 'Unknown', null,
    '1900-01-01'::date, '9999-12-31'::date, 1::smallint
