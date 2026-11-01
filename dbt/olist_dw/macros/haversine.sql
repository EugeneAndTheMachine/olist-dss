{#- Khoảng cách đường chim bay (km) giữa 2 toạ độ; null nếu thiếu toạ độ -#}
{% macro haversine_km(lat1, lng1, lat2, lng2) -%}
    (2 * 6371 * asin(sqrt(
        power(sin(radians(({{ lat2 }}) - ({{ lat1 }})) / 2), 2)
        + cos(radians({{ lat1 }})) * cos(radians({{ lat2 }}))
        * power(sin(radians(({{ lng2 }}) - ({{ lng1 }})) / 2), 2)
    )))
{%- endmacro %}

{#- Số ngày (có phần lẻ) giữa 2 timestamp; âm (mốc ngược thứ tự, xem stg_orders._dq_issue) → null -#}
{% macro lag_days(from_ts, to_ts) -%}
    case
        when ({{ to_ts }}) >= ({{ from_ts }})
            then round((extract(epoch from ({{ to_ts }}) - ({{ from_ts }})) / 86400.0)::numeric, 4)
    end
{%- endmacro %}
