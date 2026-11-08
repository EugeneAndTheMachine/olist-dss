with latest_run as (
    select model_run_id
    from {{ source('meta', 'model_registry') }}
    where model_name = 'recommendations'
    order by trained_at desc
    limit 1
)

select
    r.rec_id,
    r.decision_maker,
    r.subject_type,
    r.subject_id,
    r.action,
    r.rationale,
    r.score,
    r.status,
    r.created_at,
    r.model_version,
    r.model_run_id
from {{ source('ml_shared', 'recommendations') }} as r
join latest_run as l on l.model_run_id = r.model_run_id
