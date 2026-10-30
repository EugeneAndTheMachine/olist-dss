-- Bảng metadata (CLAUDE.md mục 11.2). Tạo rỗng để view bi build được ngay lần đầu.

create table if not exists meta.etl_run_log (
    log_id      bigserial primary key,
    run_id      text not null,
    batch_id    text,
    step        text not null,
    started_at  timestamptz,
    ended_at    timestamptz,
    rows_in     bigint,
    rows_out    bigint,
    status      text not null check (status in ('running', 'success', 'failed', 'skipped')),
    message     text
);

create table if not exists meta.dq_results (
    result_id   bigserial primary key,
    run_id      text not null,
    test_name   text not null,
    test_type   text,
    model       text,
    status      text,
    failures    bigint,
    message     text,
    executed_at timestamptz
);

-- Trạng thái hiện tại: meta_publish.py xoá và ghi lại mỗi lần chạy
create table if not exists meta.data_dictionary (
    schema_name text not null,
    table_name  text not null,
    column_name text not null,
    data_type   text,
    description text,
    updated_at  timestamptz not null default now(),
    primary key (schema_name, table_name, column_name)
);

create table if not exists meta.source_to_target (
    target_model        text not null,
    target_column       text,
    source_models       text,
    transformation_note text,
    updated_at          timestamptz not null default now()
);

create table if not exists meta.model_registry (
    model_run_id  uuid primary key,
    model_name    text not null,
    model_version text not null,
    trained_at    timestamptz not null default now(),
    train_window  text,
    params_json   jsonb,
    metrics_json  jsonb
);

-- COULD: ghi nhận quyết định chấp nhận / bác bỏ đề xuất
create table if not exists meta.decision_log (
    decision_id bigserial primary key,
    rec_id      text not null,
    decided_by  text not null,
    decision    text not null check (decision in ('accept', 'reject')),
    note        text,
    decided_at  timestamptz not null default now()
);
