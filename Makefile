# Olist DW — lệnh chính. Windows: chạy trong Git Bash hoặc WSL2 (xem docs/SETUP.md).
# Airflow DAG gọi cùng các script/command này (airflow/dags/olist_pipeline.py).

-include .env
export

# Mọi lệnh Python/dbt chạy trong venv do uv quản lý (.venv, khoá bằng uv.lock)
UV ?= uv
PYTHON ?= $(UV) run python
DBT_DIR := dbt/olist_dw
# dbt >= 1.5 chỉ nhận --project-dir/--profiles-dir SAU subcommand → truyền bằng env (được export ở trên)
DBT_PROJECT_DIR := $(DBT_DIR)
DBT_PROFILES_DIR := $(DBT_DIR)
DBT := $(UV) run dbt
COMPOSE := docker compose
# DDL idempotent (schemas, meta, ml.*); 00_databases.sql chỉ chạy lần đầu nên không áp lại
INIT_SQL := $(sort $(wildcard docker/postgres/init/0[1-9]*.sql))

.PHONY: help venv lock up up-airflow down ingest load-raw db-init dbt-profile dbt-deps seed build ml ml-recommendations meta docs docs-serve all replay reset-db

help:
	@echo "make venv                 # uv sync: tạo/cập nhật .venv theo uv.lock"
	@echo "make up | up-airflow | down"
	@echo "make ingest | load-raw | db-init | dbt-deps | seed | build | ml | meta | docs | docs-serve"
	@echo "make all                  # up -> ingest -> load-raw -> db-init -> dbt -> ml -> meta -> docs"
	@echo "make replay MONTH=2017-11 # nạp lại 1 tháng"
	@echo "make reset-db             # XOÁ toàn bộ schema (hỏi xác nhận)"

venv:
	$(UV) sync

# Sau khi sửa dependency trong pyproject.toml: cập nhật uv.lock + requirements.txt (cho pip / Airflow tham khảo)
lock:
	$(UV) lock
	$(UV) export --format requirements-txt --no-hashes --all-groups --no-header -o requirements.txt

up:
	$(COMPOSE) up -d postgres azurite

up-airflow:
	$(COMPOSE) --profile airflow up -d --build

down:
	$(COMPOSE) --profile airflow down

ingest:
	$(PYTHON) -m ingestion.download_kaggle
	$(PYTHON) -m ingestion.upload_to_lake

load-raw:
	$(PYTHON) -m ingestion.load_raw

# Init script chỉ tự chạy khi volume trống: áp lại DDL (thêm bảng ml.* mới) trên DB đang có
db-init:
	for f in $(INIT_SQL) ; do \
		$(COMPOSE) exec -T -e PGOPTIONS=--client-min-messages=warning postgres psql -q -v ON_ERROR_STOP=1 -U $(POSTGRES_USER) -d $(POSTGRES_DB) < $$f || exit 1; \
	done

$(DBT_DIR)/profiles.yml:
	cp $(DBT_DIR)/profiles.example.yml $(DBT_DIR)/profiles.yml

dbt-profile: $(DBT_DIR)/profiles.yml

dbt-deps: dbt-profile
	$(DBT) deps

seed: dbt-profile
	$(DBT) seed

build: dbt-profile
	$(DBT) build

# Mỗi bài toán thêm target ml-p1 / ml-p2 / ml-p3 vào trước ml-recommendations (đề xuất đọc output của chúng)
ml: ml-recommendations

ml-recommendations:
	$(PYTHON) -m ml.recommendations

meta:
	$(PYTHON) -m ingestion.meta_publish

docs: dbt-profile
	$(DBT) docs generate

docs-serve: docs
	$(DBT) docs serve --port 8081

all: venv up ingest load-raw db-init dbt-deps seed build ml meta docs

replay: dbt-profile
	@test -n "$(MONTH)" || (echo "Thiếu MONTH, ví dụ: make replay MONTH=2017-11" && exit 1)
	$(PYTHON) -m scripts.replay_month --month $(MONTH)
	$(PYTHON) -m ingestion.upload_to_lake
	$(PYTHON) -m ingestion.load_raw
	$(DBT) build --select tag:incremental+

reset-db:
	@read -p "Xoá toàn bộ schema raw/stg/dw/bi/ml/meta trong $(POSTGRES_DB)? Gõ 'yes': " ans && [ "$$ans" = "yes" ]
	$(COMPOSE) exec -T postgres psql -v ON_ERROR_STOP=1 -U $(POSTGRES_USER) -d $(POSTGRES_DB) \
		-c "drop schema if exists raw, stg, dw, bi, ml, meta cascade;"
	$(MAKE) db-init
