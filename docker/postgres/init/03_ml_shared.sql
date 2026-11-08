-- Bảng ml dùng chung cho cả 3 bài toán (C-M2). Chỉ ml/recommendations.py ghi vào đây.
-- Idempotent: make db-init áp lại được trên DB đang có (init script chỉ tự chạy khi volume trống).
create table if not exists ml.recommendations (
    rec_id         text not null,
    decision_maker text not null,
    subject_type   text not null,
    subject_id     text not null,
    action         text not null,
    rationale      text,
    score          numeric(10, 5),
    model_run_id   uuid not null,
    model_version  text not null,
    status         text not null default 'proposed',
    created_at     timestamptz not null default now()
);

create index if not exists recommendations_run_idx on ml.recommendations (model_run_id);
