{#- Thứ tự hiển thị seller tier (cột sort cho Power BI): Gold tốt nhất → Unscored; null (chưa có version trước) = 0 -#}
{% macro tier_sort(col) -%}
    case {{ col }}
        when 'Gold' then 1 when 'Silver' then 2 when 'Bronze' then 3
        when 'New' then 4 when 'At-risk' then 5 when 'Unscored' then 6
        when 'unknown' then 9 else 0
    end
{%- endmacro %}
