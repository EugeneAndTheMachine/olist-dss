{#- Lịch sử chạy pipeline: load_raw (1 dòng / file) và dbt (1 dòng / lệnh). -#}
select
    log_id,
    run_id as "Run ID",
    batch_id as "Batch ID",
    step as "Step",
    split_part(step, ':', 1) as "Step Group",
    started_at as "Started At",
    ended_at as "Ended At",
    started_at::date as "Run Date",
    round(extract(epoch from (ended_at - started_at))::numeric, 1) as "Duration (s)",
    rows_in as "Rows In",
    rows_out as "Rows Out",
    status as "Status",
    message as "Message"
from {{ source('meta', 'etl_run_log') }}
