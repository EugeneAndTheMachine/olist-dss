# Rebuild Guide: Business Logic from Raw to Dashboard

> Written 2026-11-06 (PR #5, business logic removed); updated 2026-11-07 (PR #6, supporting sources removed).
> Target design (what to build): `docs/refactor_plan.md`. This guide covers **how** to rebuild it, one business
> decision at a time.
> Facts about the data (counts, anomalies) that each decision depends on: `docs/profiling.md`, `docs/profiling.sql`.

---

## 0. What was removed, what was kept

The old dbt models encoded many business decisions that the team had not discussed one by one (what counts as
a sale, what "late" means, which seller owns an order, how to clean geolocation...). They were removed so that
each decision is made explicitly, written down, and then implemented.

| Kept (platform, no business decisions) | Removed (business logic, to rebuild) |
| --- | --- |
| Docker Compose, Makefile, `.env.example`, uv | All dbt models: `staging/stg_*`, `intermediate/int_*`, `warehouse/dims`, `warehouse/facts`, `bi`, `quality` |
| `docker/postgres/init/00`–`02` (databases, schemas `raw stg dw bi ml meta`, `meta.*` tables) | All dbt singular tests (`tests/*.sql`) |
| `ingestion/*`: `data/raw` or Kaggle → landing → Azure Blob → `raw` (all columns text, append-only), `meta_publish.py` | Seeds `order_status_map`, `category_group`, `instalment_band`, `seller_tier_rules` |
| `data/raw/ecom_dataset/` (the only source) | Macros `cleaning.sql`, `haversine.sql` (incl. `lag_days`), `unknown_member.sql`, `tier_sort.sql` |
| dbt skeleton: `dbt_project.yml`, `profiles.example.yml`, `packages.yml` (dbt_utils), `models/staging/_sources.yml` (raw + meta sources) | `dbt_project.yml` vars `date_spine_*`, `scd_*`, `seller_tier_rule_version`; folder config `quality` |
| Macros `generate_schema_name`, `int_sk`, `grant_bi_reader` | ML stubs `ml/late_risk`, `crm_segment_voucher`, `gmv_forecast`, `seller_risk`, `recommendations.py`; DDL `docker/postgres/init/03_ml.sql`; the `ml` source |
| — | Marketing Funnel dataset (`data/raw/marketing_funnel/`, `raw.mql`, `raw.closed_deals`) |
| — | Supporting sources: `data/raw/events_brazilstates/` (`br_states`, `calendar_events`), `gen_holidays.py` (`br_holidays`), `copy_manual.py`, seed `br_state_population` |
| `ml/common/` (db access, `model_run_id`, registry, time split) | Docs `kpi_dictionary.md`, `bi_layer.md`, `implementation_walkthrough.md`, `powerbi_guide.md` |
| Airflow DAG (ingest → load → dbt → meta), `scripts/replay_month.py` | ML tasks in the DAG and in `make ml` |

**Getting old code back for reference.** The last commit that contains everything is `83891b5`
(`docs: refactor plan ... (#4)`):

```bash
git show 83891b5:dbt/olist_dw/models/staging/stg_orders.sql          # read one file
git ls-tree -r --name-only 83891b5 -- dbt/olist_dw/models             # list old models
git checkout 83891b5 -- dbt/olist_dw/macros/cleaning.sql              # restore a file into the working tree
git show 83891b5:docs/kpi_dictionary.md                               # old KPI dictionary
```

Old code is a **reference, not a default**. Restore a file only after the decision it encodes has been agreed.

**State of the pipeline now.** `make up && make ingest && make load-raw` loads the 9 raw tables
of the Olist e-commerce dataset. There are no seeds yet.
`make build` has no models yet. `make meta` and `make docs` still work.

---

## 1. Working method: decide → record → implement → test

For every business rule:

1. **State the question** in one sentence (e.g. "Is an order late when delivered on the promised day?").
2. **Look at the evidence**: the matching row in `docs/profiling.md`, or a new query added to `docs/profiling.sql`.
3. **List the options** and their effect on the numbers (profiling often already gives both numbers).
4. **Decide**, and write the decision in `docs/business_rules.md` (new file, one row per rule, template below).
5. **Implement** it in exactly one place (one staging model, one seed, or one macro), with a YAML description that
   references the rule ID.
6. **Test** it (generic test, singular test or reconciliation) so a later change cannot silently break it.

Template for `docs/business_rules.md`:

```markdown
| ID | Question | Evidence | Options | Decision | Implemented in | Test | Decided by / date |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-01 | What counts as a sale? | profiling A1: 8 statuses | (a) delivered only (b) all except canceled/unavailable | ... | seed order_status_map | accepted_values + reconciliation GMV | ... |
```

Rule IDs are referenced from model YAML (`description: "... (BR-01)"`) so the dbt docs show where each rule lives.
When the decision changes, update the row and the changelog in `implementation.md` §19.

---

## 2. Step 1 — Staging (`stg`): cleaning and typing

**Goal:** one `stg_<source>` model per raw table, typed, deduplicated and cleaned, with data-quality flags.
No joins across sources and no KPIs here, except where a decision says otherwise.

### 2.1 Decisions shared by all staging models

| # | Question | Evidence | Old choice (reference) |
| --- | --- | --- | --- |
| BR-S1 | `raw` is append-only and `load_raw` can load the same file again with a new batch. How to deduplicate? | `load_raw.py` adds `_batch_id`, `_loaded_at`, `_source_file` | Keep the row with the latest `_loaded_at` per natural key (`row_number() over (partition by <key> order by _loaded_at desc)`); geolocation: only the latest batch |
| BR-S2 | Empty strings and whitespace | profiling: empty CSV cells load as `NULL` already | `nullif(trim(col), '')` everywhere (macro `clean_text`) |
| BR-S3 | Zip prefix format | A9: all zips are 5 characters in raw, 23,995 customer zips start with `0` | `lpad(trim(zip), 5, '0')` (macro `zip5`), kept as a safeguard |
| BR-S4 | City names have accents and inconsistent spelling | A3: 8,011 raw city values → 5,969 after `lower(unaccent())`; extension `unaccent` exists in the DB | `regexp_replace(lower(public.unaccent(trim(city))), '\s+', ' ', 'g')` (macro `clean_city`) |
| BR-S5 | State code format | 27 customer states, 23 seller states, all 2-letter codes | `upper(trim(state))` (macro `state_code`) |
| BR-S6 | Bad data: drop, fix or flag? | Profiling finding 2 (timestamps out of order) | Never drop rows; keep the value, add a `_dq_issue` text column, null only values that are impossible |
| BR-S7 | Where are derived flags (`is_delivered`, `is_late`, `delay_days`) computed: staging or fact? | — | Staging (`stg_orders`), reused by facts. Decide again: computing them in the fact keeps staging free of KPI logic |

### 2.2 Decisions per source

| Source → model | Questions to decide | Evidence (`docs/profiling.md`) | Old choice |
| --- | --- | --- | --- |
| `orders` → `stg_orders` | (1) Is an order *delivered* when status = delivered, or when it has a delivery date? (2) Late = compare dates or timestamps? (3) What to do with timestamps out of order? | 8 `delivered` orders without delivery date, 6 `canceled` with one. Late rate by date **6.77%**, by timestamp **8.11%** (estimated date has no time part). 1,359 carrier < approved, 166 carrier < purchase, 23 delivered < carrier, 0 delivered < purchase. 160 orders without `approved_at` | `is_delivered` = status delivered **and** delivery date not null; `is_late` = `delivered::date > estimated::date`; `delay_days` = date difference; delivered < purchase → null; other inversions flagged in `_dq_issue`, negative lags set to null later |
| `order_items` → `stg_order_items` | Out-of-range `shipping_limit_date` | Finding 7: 4 items (3 orders, 2017) with a limit in 2020 | Null + `_dq_issue = shipping_limit_out_of_range` |
| `order_payments` → `stg_order_payments` | (1) `not_defined` payment type (2) instalments = 0 | A1: 3 `not_defined` rows (canceled, value 0); 2 rows with 0 instalments; max 24 | Keep `not_defined` as a type; 0 → 1 |
| `order_reviews` → `stg_order_reviews` | (1) One review_id on several orders (2) Several reviews per order: which one counts? | A2: 789 review_ids on > 1 order; 547 orders with > 1 review (202 with different scores); 768 orders without review | Key = (review_id, order_id); `is_latest_for_order` by `review_answer_timestamp`, then `review_creation_date`, then `review_id`; KPIs use the latest only |
| `customers` → `stg_customers` | Olist issues a new `customer_id` per order: what is a "customer"? | A7: 99,441 customer_id, 96,096 customer_unique_id; 3.12% repeat | Customer = `customer_unique_id`; separate map `customer_id → customer_unique_id` |
| `sellers` → `stg_sellers` | — (zip, city, state cleaning only) | 3,095 sellers, 23 states; 7 seller zips missing from geolocation | Shared rules only |
| `products` → `stg_products` | (1) Missing category (2) Category without translation (3) Weight 0 (4) Typo columns `*_lenght` (5) Size / weight bands | A4: 610 products (1,603 items) without category; 13 products in 2 untranslated categories; 4 products with weight 0; 2 without dimensions | Missing → `unknown`; untranslated → keep PT name; weight 0 → null; rename to `*_length`; `volume_cm3` = L × H × W; bands by CASE |
| `geolocation` → `stg_geolocation` | (1) ~52.6 points per zip: how to reduce to one? (2) Points outside Brazil (3) Zip in several states | A3: 42 points (21 zips) outside the bbox, 5 zips entirely outside; 8 zips in > 1 state | One row per zip: mean lat / lng of points inside bbox lat −34…5.5, lng −74…−34; city / state = most frequent value; zips fully outside → lat / lng null |
| `product_category_name_translation` | — | 71 rows, 2 categories missing | Plain typing |

### 2.3 Definition of done (staging)

- `dbt build --select staging` green.
- Every model has YAML with model + column descriptions and `unique` / `not_null` on the natural key.
- Row counts: `raw` vs `stg` equal per table, or the difference is explained by a rule (dedup) and documented.
- `docs/business_rules.md` has a row for every rule used.

---

## 3. Step 2 — Reference data (seeds) and shared macros

Seeds hold decisions that a business user should be able to read and change without SQL.

| Seed (removed) | Decision it holds | Old content (reference) | Needed by |
| --- | --- | --- | --- |
| `order_status_map` | Which statuses count as a sale; status grouping | `delivered` → Completed, counts; `shipped, invoiced, processing, approved, created` → Open, counts; `canceled, unavailable` → Cancelled, does not count | GMV, Orders, Cancel rate (all problems) |
| `category_group` | Grouping of 73 Olist categories (+ `unknown`) into ~11 groups | 11 groups + Unknown: Home & Furniture (14), Electronics & Tech (10), Fashion & Accessories (9), Construction & Tools (8), Books Media & Stationery (7), Appliances (6), Auto & Industry (5), Sports & Leisure (5), Food & Drinks (3), Health & Beauty (3), Toys Baby & Pets (3) (see `git show 83891b5:dbt/olist_dw/seeds/category_group.csv`) | P3 (category forecast at group level), P2 |
| `instalment_band` | Instalment bands for the payment junk dimension | `1`, `2-3`, `4-6`, `7-10`, `11+` | Only if `fact_payment` is kept (refactor plan Q1) |
| `seller_tier_rules` | Seller tier thresholds (SCD2) | v1: New < 3 months since first order; At-risk late_rate_3m ≥ 0.15 or avg_score_3m < 3.5 (with orders_3m ≥ 5); Gold orders_3m ≥ 50, late < 0.05, score ≥ 4.5; Silver orders_3m ≥ 15, late < 0.08, score ≥ 4.2; Bronze otherwise | Only if the seller tier SCD2 is kept (refactor plan §3.4) |

Macros (removed) that encoded rules. Re-create only the ones whose rule is agreed:

| Macro | What it did | Rule it encodes |
| --- | --- | --- |
| `clean_text`, `zip5`, `clean_city`, `state_code`, `to_bool` | Text cleaning | BR-S2 … BR-S5 |
| `lag_days(from_ts, to_ts)` | Days between two timestamps (with fraction); negative → null | Treatment of out-of-order timestamps (BR-S6) |
| `haversine_km(lat1, lng1, lat2, lng2)` | Great-circle distance in km | Distance as a proxy for shipping distance (P1) |
| `unknown_key`, `coalesce_key`, `date_key` | Unknown member `-1`; date key `YYYYMMDD`, `-1` when null | Warehouse convention (step 3) |
| `tier_sort` | Display order of tiers | Presentation only |

Kept macros: `int_sk(cols)` (bigint surrogate key hashed from the natural key, stable across rebuilds),
`generate_schema_name` (schemas are named exactly `stg`, `dw`, `bi`), `grant_bi_reader` (read-only user for
Power BI on schema `bi`, run on `on-run-end`).

---

## 4. Step 3 — Warehouse (`dw`): dimensions and facts

Follow Kimball's four steps **per problem** (P1, P2, P3 of `docs/refactor_plan.md` §2), then merge the result into
one bus matrix (refactor plan §4.1):

1. **Business process**: delivery (P1), regional market activity (P2), category demand (P3), sales (all).
2. **Grain**: one sentence per fact, e.g. "one row per order". Write it in the fact YAML.
3. **Dimensions**: which conformed dimensions describe the grain.
4. **Facts / measures**: numeric, additive where possible; ratios stored as numerator + denominator.

### 4.1 Warehouse-wide decisions

| # | Question | Evidence / notes | Old choice |
| --- | --- | --- | --- |
| BR-W1 | Surrogate keys: sequence or hash? | Hash is stable across full rebuilds and incremental loads | `int_sk(natural key)` (kept macro) |
| BR-W2 | Missing dimension members | Facts must not lose rows when a lookup fails | Unknown member key `-1` in every dim; date key `-1` when the event has not happened |
| BR-W3 | Date dimension range; holiday / event flags? | Orders 2016-09 → 2018-10. No holiday data in the dataset any more: flags such as Black Friday need a seed (BR-W12) | `dim_date` 2016-01-01 → 2019-12-31 via `dbt_utils.date_spine` (vars `date_spine_start` / `date_spine_end` — re-add to `dbt_project.yml`) |
| BR-W4 | Analysis window for time series / ML | A8: 2016 and 09–10/2018 are almost empty; 2017-01 → 2018-08 holds 99.6% of orders | `ANALYSIS_START = 2017-01-01`, `ANALYSIS_END = 2018-08-31` (still in `.env` and `dbt_project.yml`); all data stays in `dw`, the filter applies to KPIs over time and ML |
| BR-W5 | Orders with several sellers: who owns the order for order-level facts? | Finding 5: 1,278 orders (1.3%) | Primary seller = seller of the highest-price item; tie → smallest `seller_id` |
| BR-W6 | Order value: with or without freight? | A5: Σ payment is +1.0% over Σ item_total (interest, vouchers) | `order_value` = Σ price (same basis as GMV); freight separate |
| BR-W7 | Payment vs item reconciliation tolerance | A5: 99.75% of orders within max(1 BRL, 1%) | Warn-level test with tolerance max(1 BRL, 1% of item_total) |
| BR-W8 | Customer geography: which zip represents a customer who ordered from several zips? | Repeat rate 3.12%, so rare | Order-level facts use the zip of the order; `dim_customer` uses the zip of the first order |
| BR-W9 | Geography grain and hierarchy | ~19k zip prefixes; CEP is hierarchical | Old: zip → city → state → region. New (refactor plan §4.2): add `zip_prefix_3`, `zip_prefix_2`, geo grid cell. Zip set = geolocation ∪ customers ∪ sellers (A3: 157 customer zips and 7 seller zips are missing from geolocation) |
| BR-W10 | Keep the seller tier SCD Type 2? | Course requirement; tier is used in P1 / P2 as a supporting signal | Old rules in `implementation.md` §10 (versions from monthly 3-month rolling metrics, first version valid from 1900-01-01) |
| BR-W11 | Flags in facts: boolean or 0/1? | Power BI sums 0/1 directly | Integer 0/1 |
| BR-W12 | Reference data outside the dataset: state → region (5 regions), holidays / retail events, state population. Needed? | Removed on 2026-11-07 to keep one dataset. Region is needed for P1 / P2 maps; population only for per-capita KPIs | Old: `br_states.csv`, package `holidays`, seed `br_state_population` (restore from `83891b5` as seeds if agreed) |

### 4.2 Models to build (target from `docs/refactor_plan.md` §4)

| Model | Grain | Problem | Key decisions it depends on |
| --- | --- | --- | --- |
| `dim_date` | 1 day | all | BR-W3, BR-W12 |
| `dim_geography` (+ zip_prefix_3 / _2, geo cell) | 1 zip prefix | P1, P2 | BR-S3, BR-S4, geolocation rules, BR-W9, BR-W12 (region) |
| `dim_customer` | 1 `customer_unique_id` | P2 | customer definition, BR-W8 |
| `dim_product`, `dim_category` | 1 product / 1 category | P3 | product rules, `category_group` seed |
| `dim_seller` | 1 seller (or 1 seller version if BR-W10 = yes) | P1, P2, P3 | BR-W10 |
| `dim_order_status` | 1 status | all | `order_status_map` seed |
| `fact_order_item` | 1 order item | P2, P3 | sale definition |
| `fact_order_fulfillment` | 1 order (accumulating snapshot) | P1 | delivered / late definitions, BR-W5, BR-W6, lags, distance |
| `fact_review` | 1 (review_id, order_id) | P1, P3 | latest-review rule |
| `fact_geo_month` | 1 zip prefix × 1 month | P1, P2 | demand vs supply side, local-seller definition |
| `fact_category_month` | 1 category × 1 customer state × 1 month | P3 | category key option (refactor plan Q2) |
| `fact_payment`, `dim_payment_type` | 1 payment / junk | optional | refactor plan Q1 |

Helper models (`models/intermediate/int_*`, schema `stg`) are created when a fact needs a reusable step, e.g. the
customer map, the primary seller per order, items aggregated per order.

### 4.3 Tests and definition of done (warehouse)

- Every key: `unique` + `not_null`; every fact FK: `relationships` to its dim.
- Business-rule tests (`tests/assert_*.sql`): e.g. delivered not before purchase, review score in 1–5, unknown key
  share < 1% (warn), SCD2 checks if BR-W10 = yes (one current version, no overlap, point-in-time lookup).
- Reconciliation: one fulfilment row per order; Σ GMV `stg` = Σ GMV `fact_order_item`; Σ `fact_geo_month` and
  Σ `fact_category_month` = `fact_order_item` for the same month; item vs payment within BR-W7 (warn).
- Optional DQ summary model (old `models/quality/dq_issue_summary.sql` → `meta.dq_issue_summary`): re-add the
  folder config `quality: {+schema: meta, +materialized: table}` in `dbt_project.yml`.

---

## 5. Step 4 — KPI dictionary and `bi` views

Write `docs/kpi_dictionary.md` again **before** the `bi` views and the DAX measures. Each KPI gets: name, business
definition, formula (numerator / denominator), source fact, filters, and the rule IDs it depends on. The KPI list
for the three problems is in `docs/refactor_plan.md` §5. KPI decisions to make explicitly:

| # | Question | Old choice |
| --- | --- | --- |
| BR-K1 | GMV: with or without freight, which statuses? | Σ item price, `counts_as_sale` only |
| BR-K2 | Late rate denominator: all orders or delivered orders? | Σ is_late / Σ is_delivered |
| BR-K3 | Average review score: all reviews or latest per order? | Latest per order |
| BR-K4 | Late density: per grid cell, per zip, per city? per month? | New (refactor plan §5) |
| BR-K5 | Growth: MoM or YoY, over which window? | New: last 3 months vs same 3 months a year earlier |
| BR-K6 | Minimum volume before showing a rate for an area / category | New |

`bi` views (`models/bi/v_*`, materialized as views, read by Power BI user `powerbi_reader`): thin views over `dw`
with friendly column names and no change of grain. Then write `docs/bi_layer.md` (view list, relationships for
Power BI, role-playing dimensions). Old version for reference: `git show 83891b5:docs/bi_layer.md`.

---

## 6. Step 5 — ML and decision support (`ml`)

Modules, inputs and outputs per problem: `docs/refactor_plan.md` §6. To wire a module into the platform:

1. Create the output tables in a new `docker/postgres/init/03_ml.sql` (append-only, every row has `model_run_id uuid`
   and `model_version`). Existing databases do not re-run init scripts: apply it once with
   `docker compose exec -T postgres psql -U olist -d olist_dw < docker/postgres/init/03_ml.sql`, and add it back to the
   `reset-db` loop in the `Makefile`.
2. Add the tables as source `ml` in `models/staging/_sources.yml` and create `bi.v_<table>` views that keep only the
   latest `model_run_id` (join `meta.model_registry` on `trained_at`).
3. Use `ml/common`: `read_sql` / `append_df` (`db.py`), `new_run` / `tag_output` / `register` (`registry.py`),
   `time_split` (`features.py`). Time-based split only; features only known at decision time; always a baseline.
4. Add the commands to `make ml` and as tasks between `dbt_build` and `meta_publish` in
   `airflow/dags/olist_pipeline.py`.

---

## 7. Step 6 — Power BI and documentation

- Power BI connects as `powerbi_reader`, Import mode, schema `bi` only (`powerbi/README.md`).
- Page plan: `docs/refactor_plan.md` §7.2. Every DAX measure follows the KPI dictionary (step 4).
- Rewrite `docs/powerbi_guide.md` once the semantic model exists.
- Update `implementation.md` sections 7–10 and 13–14 to the new design, and add the changelog entries.

---

## 8. Order of work and checklist

Each step depends on the previous one. Steps 1–2 can be split by source table; step 3 by problem.

| Step | Output | Done when |
| --- | --- | --- |
| 0 | `docs/business_rules.md` with BR-S*, then BR-W*, BR-K* filled in as they are decided | Every rule used in code has a row |
| 1 | `stg_*` for the 9 raw tables (+ `int_customer_map` if needed) | §2.3 |
| 2 | Seeds and macros for agreed rules | `dbt seed` green, seeds documented in `_seeds.yml` |
| 3 | Dims and facts of §4.2 | §4.3 |
| 4 | `kpi_dictionary.md`, `bi` views, `bi_layer.md` | Views build; every dashboard KPI is in the dictionary |
| 5 | ML modules + `ml` DDL + `bi` ML views | Each module registered in `meta.model_registry` with baseline vs model metrics |
| 6 | Power BI pages, docs updated | `make all` on a clean machine; dashboard refreshes |
