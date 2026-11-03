{#-
    S6 bước 2: chấm tier mỗi seller × tháng theo ngưỡng trong seed seller_tier_rules (rule_version = var).
    Cấu trúc logic (HOẶC / VÀ) nằm ở đây, seed chỉ giữ ngưỡng để Seller Quality Manager chỉnh:
      New     : months_since_first < 3
      Bronze  : orders_3m < 5 (đủ thâm niên nhưng quá ít đơn để chấm At-risk/Silver/Gold)
      At-risk : orders_3m >= 5 VÀ (late_rate_3m >= 0.15 HOẶC avg_score_3m < 3.5)
      Gold    : orders_3m >= 50 VÀ late_rate_3m < 0.05 VÀ avg_score_3m >= 4.5
      Silver  : orders_3m >= 15 VÀ late_rate_3m < 0.08 VÀ avg_score_3m >= 4.2
      Bronze  : còn lại
    Thiếu dữ liệu (chưa có đơn giao / chưa có review trong 3 tháng) → điều kiện tương ứng = false.
    Tháng không có đơn bán: giữ tier tháng trước (không tạo version mới).
    Thay đổi 01/11 so với rule gốc "New: < 3 tháng HOẶC orders_3m < 5": vế "HOẶC" làm seller bán 22 tháng
    nhưng ít đơn bị gắn nhãn New (tháng 08/2018: 288 seller) → New chỉ theo thâm niên, ít đơn → Bronze.
-#}
with metrics as (
    select * from {{ ref('int_seller_month_metrics') }}
),

rules as (
    select
        rule_version,
        max(min_months_since_first) filter (where tier = 'New') as new_min_months,
        max(min_orders_3m) filter (where tier = 'New') as new_min_orders,
        max(min_orders_3m) filter (where tier = 'At-risk') as risk_min_orders,
        max(max_late_rate_3m) filter (where tier = 'At-risk') as risk_late_rate,
        max(min_avg_score_3m) filter (where tier = 'At-risk') as risk_avg_score,
        max(min_orders_3m) filter (where tier = 'Gold') as gold_min_orders,
        max(max_late_rate_3m) filter (where tier = 'Gold') as gold_max_late,
        max(min_avg_score_3m) filter (where tier = 'Gold') as gold_min_score,
        max(min_orders_3m) filter (where tier = 'Silver') as silver_min_orders,
        max(max_late_rate_3m) filter (where tier = 'Silver') as silver_max_late,
        max(min_avg_score_3m) filter (where tier = 'Silver') as silver_min_score
    from {{ ref('seller_tier_rules') }}
    where rule_version = '{{ var("seller_tier_rule_version") }}'
    group by rule_version
),

scored as (
    select
        m.*,
        r.rule_version,
        r.new_min_months,
        case
            when m.orders = 0 then null
            when m.months_since_first < r.new_min_months then 'New'
            when m.orders_3m < r.new_min_orders then 'Bronze'
            when coalesce(m.late_rate_3m >= r.risk_late_rate, false)
              or coalesce(m.avg_score_3m < r.risk_avg_score, false) then 'At-risk'
            when m.orders_3m >= r.gold_min_orders
             and coalesce(m.late_rate_3m < r.gold_max_late, false)
             and coalesce(m.avg_score_3m >= r.gold_min_score, false) then 'Gold'
            when m.orders_3m >= r.silver_min_orders
             and coalesce(m.late_rate_3m < r.silver_max_late, false)
             and coalesce(m.avg_score_3m >= r.silver_min_score, false) then 'Silver'
            else 'Bronze'
        end as tier_scored
    from metrics as m
    cross join rules as r
),

-- Mang tier tháng gần nhất có đơn sang các tháng không có đơn
carried as (
    select
        *,
        count(tier_scored) over (partition by seller_id order by month_start) as tier_grp
    from scored
)

select
    seller_id,
    month_start,
    rule_version,
    orders,
    orders_3m,
    late_rate_3m,
    avg_score_3m,
    months_since_first,
    tier_scored,
    case
        -- New chỉ theo thâm niên: seller ngừng bán khi còn New không được giữ nhãn New sau 3 tháng
        when carried_tier = 'New' and months_since_first >= new_min_months then 'Bronze'
        else carried_tier
    end as seller_tier
from (
    select
        c.*,
        coalesce(
            first_value(c.tier_scored) over (partition by c.seller_id, c.tier_grp order by c.month_start),
            'New'
        ) as carried_tier
    from carried as c
) as with_carry
