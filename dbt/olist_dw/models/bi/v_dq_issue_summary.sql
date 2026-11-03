{#- Lỗi dữ liệu được giữ lại + gắn cờ (không xoá dòng), theo model. Nguồn: meta.dq_issue_summary. -#}
select
    layer as "Layer",
    model_name as "Model",
    issue as "Issue",
    issue_rows as "Issue Rows",
    total_rows as "Total Rows",
    issue_pct as "Issue %",
    checked_at as "Checked At"
from {{ ref('dq_issue_summary') }}
