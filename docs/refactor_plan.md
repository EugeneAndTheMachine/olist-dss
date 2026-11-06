# Refactor Plan: Single Dataset, Three Decision Problems

> Status: **proposed** (2026-11-06). When accepted, the changes below are applied to `implementation.md`
> (sections 1, 2, 7, 8, 9, 13, 14, 15, 17, 18, 19), `PROJECT_PLAN.md`, `docs/kpi_dictionary.md`, `docs/bi_layer.md`
> and `docs/powerbi_guide.md` in the same PR series. Task IDs (P*, S*, F*, M*) keep their meaning; new tasks use the
> `R1-*`, `R2-*`, `R3-*` prefixes described in section 9.

---

## 1. Summary

| | Before | After |
| --- | --- | --- |
| Source data | 2 Kaggle datasets: *Brazilian E-Commerce Public Dataset by Olist* (9 tables) + *Marketing Funnel by Olist* (2 tables) | **1 Kaggle dataset**: *Brazilian E-Commerce Public Dataset by Olist* (9 tables). Supporting files (`br_states.csv`, `calendar_events.csv`, holidays, state population seed) are kept |
| Business scope | 4 decision makers (Commerce, Logistics & CX, Seller Quality, CRM), 8 Power BI pages, 5 ML modules (M3–M7) | **3 decision problems**, each split into a *dashboard* part (what is happening) and an *ML / decision* part (what to do) |
| Problem 1 | — | **Late delivery by area** → where to place warehouses, where to add couriers |
| Problem 2 | — | **Regional market size from customer & seller zip codes** → which areas to develop |
| Problem 3 | — | **Best-selling categories and product demand** → which categories to develop |

The rule for every problem: the part **before the arrow** is descriptive and lives on a dashboard (Simon phase
*Intelligence*); the part **after the arrow** is decision support built with ML / optimisation, shown as scenario
tables and recommendations (Simon phases *Design* and *Choice*).

Why:

- The funnel dataset only joins to 380 of 842 won deals (45.1%, profiling A6), its lead profile exists only for
  won leads, and its 90-day window is truncated for 175 deals. It added 3 dimensions, 1 fact and a lot of special
  cases (`is_from_funnel`, `Unscored` tier, `has_full_90d_window`) for one descriptive page.
- Four decision makers with eight pages is too wide for the remaining time (deadline 2026-11-13). Three focused
  problems make the report, the dashboard and the demo tell one story: **delivery quality → regional demand →
  product demand**.
- All three problems can be answered from the 9 e-commerce tables, mainly through the zip code prefix
  (`customer_zip_code_prefix`, `seller_zip_code_prefix`, `geolocation`), which the current design under-uses.

---

## 2. Decision makers and problems

| # | Decision maker | Dashboard question (Intelligence) | Decision supported by ML (Design / Choice) |
| --- | --- | --- | --- |
| P1 | **Logistics Manager** | What is the late-delivery rate in each area, and where are late deliveries concentrated (late-delivery density)? Which routes, lags and distances drive it? | Where to place warehouses / fulfilment hubs, and how many extra couriers each area needs |
| P2 | **Expansion / Commerce Manager** | For each area (region → state → city → zip prefix): market size, order count, GMV, number of customers, number of sellers, e-commerce adoption trend | Which areas to develop next (recruit local sellers, run marketing, add logistics capacity) |
| P3 | **Category Manager** | Which product categories sell best, how demand changes over time and across areas, and how satisfied customers are with each | Which categories to develop (grow, maintain, fix or deprioritise) |

The problems are linked on purpose and the report should present them in this order:
P1 explains *service quality* per area, P2 explains *demand and supply* per area, P3 explains *what* is demanded.
P2 uses the late rate from P1 as a risk factor; P3 uses the category × area matrix from P2.

Dropped decision makers: **Seller Quality Manager** (lead funnel and channel value) and **CRM Manager** (voucher
allocation). See section 3.3 for what happens to their artefacts.

---

## 3. Data scope change

### 3.1 Sources after the refactor

| Source | Raw tables | Status |
| --- | --- | --- |
| Kaggle `olistbr/brazilian-ecommerce` | orders, order_items, order_payments, order_reviews, customers, sellers, products, geolocation, product_category_name_translation | **kept** (unchanged) |
| Kaggle `olistbr/marketing-funnel-olist` | mql, closed_deals | **removed** |
| `data/raw/events_brazilstates/br_states.csv` | br_states | kept |
| `data/raw/events_brazilstates/calendar_events.csv` | calendar_events | kept |
| Python `holidays` | br_holidays | kept |
| Seed `br_state_population` | — | kept, now central for P2 (orders per 1,000 inhabitants) |

`raw` goes from 14 to **12** tables.

### 3.2 What the zip code prefix gives us

Brazilian postal codes (CEP) are hierarchical: the 1st digit is the postal region, the 2nd the sub-region, the 3rd
the sector, the 4th and 5th the sub-sector. The dataset only exposes the first 5 digits, which is enough to build a
geographic hierarchy without any external API:

```
zip_prefix (5 digits, ~19k)  →  zip_prefix_3 (sector)  →  zip_prefix_2 (sub-region)  →  city  →  state  →  region (5)
```

Together with the mean latitude / longitude per zip prefix (already in `dim_geography`), this supports maps,
density analysis, distance calculation and clustering for P1 and P2. Both customers and sellers carry a zip
prefix, so every area has a **demand side** (customers, orders placed) and a **supply side** (sellers, orders
shipped).

### 3.3 Artefacts removed or changed because of the funnel removal

| Layer | Artefact | Action |
| --- | --- | --- |
| Ingestion | `ingestion/config.py` (`FUNNEL`, 2 `RawSource` entries), `ingestion/download_kaggle.py` (funnel dataset) | remove funnel entries |
| Data | `data/raw/marketing_funnel/` | delete folder |
| Env / docs | `.env.example` comment, `docs/SETUP.md` (Kaggle rules for 2 datasets, 14 raw tables) | update to 1 dataset, 12 tables |
| dbt staging | `stg_mql.sql`, `stg_closed_deals.sql`, entries in `_sources.yml`, `_stg_models.yml` | delete |
| dbt dims | `dim_lead_origin`, `dim_lead_profile`, `dim_sales_rep` (+ YAML) | delete |
| dbt dims | `dim_seller.sql`: `funnel_sellers` CTE, union with closed deals, `is_from_funnel` | remove; seller set = `sellers` only (3,095 instead of 3,557). Tier `Unscored` stays in the accepted values but should now be (almost) empty |
| dbt facts | `fact_lead_funnel` (+ YAML) | delete |
| dbt bi | `v_dim_lead_origin`, `v_dim_lead_profile`, `v_dim_sales_rep`, `v_fact_lead_funnel`; `is_from_funnel` in `v_dim_seller` | delete / remove column |
| dbt tests | `assert_reconcile_funnel_won.sql`; `fact_lead_funnel` entry in `assert_fact_unknown_key_share.sql` | delete / remove entry |
| dbt quality | `dq_issue_summary.sql`: `funnel_issues` CTE, `funnel_seller_not_in_sellers`, row count of `fact_lead_funnel` | remove |
| ML | `ml/seller_risk/` (channel value from `fact_lead_funnel`), `ml.channel_value`, `ml.seller_risk_score` | delete (see 3.4) |
| ML | `ml/crm_segment_voucher/`, `ml.customer_segment_history`, `ml.voucher_allocation` | delete (see 3.4); `v_dim_customer` no longer joins a segment |
| KPI | Lead conversion, Days to close | remove from `implementation.md` §8 and `kpi_dictionary.md` |
| Power BI | page 6 *Lead Funnel & Channel Value*, page 7 *CRM Segments & Voucher Allocation* | remove; new page plan in section 7 |
| Docs | `docs/profiling.md` rows `raw.mql`, `raw.closed_deals`, assumption A6 | mark as *obsolete (funnel removed 2026-11-06)*, keep for history |

### 3.4 What is kept although no problem is built around it

| Artefact | Why it stays |
| --- | --- |
| `fact_review` | Late delivery is the main driver of low review scores; P1 shows the cost of being late (score by late / on-time), P3 uses satisfaction per category |
| `fact_payment`, `dim_payment_type` | Cheap to keep (already built and tested); P2 can show instalment usage per area as an adoption signal. Not required by any ML module |
| `dim_seller` SCD Type 2 (seller tier) + `fact_seller_month` | Required for the course (SCD2 is a graded concept). In P1 the tier explains part of the dispatch delay (late sellers vs late carriers); in P2 the count of Silver/Gold sellers per area is a supply-quality signal |
| `fact_seller_product_activity` | Factless fact, course concept; P3 uses it to count active sellers per category |
| M3 late-delivery risk model (design) | Reused as the core of P1 ML (section 6.1) |
| M5 GMV forecast (design) | Generalised into the area forecast (P2) and the category forecast (P3) |
| M7 recommendations (`ml.recommendations`) | Kept as the *Choice* output for all three problems, with new `decision_maker` values |

---

## 4. Warehouse changes (Kimball)

### 4.1 Bus matrix after the refactor

| Fact | dim_date (roles) | dim_customer | dim_product | dim_seller | dim_geography (roles) | dim_payment_type | dim_order_status | Used by |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fact_order_item | purchase, shipping_limit | ✔ | ✔ | ✔ | customer, seller | | ✔ | P2, P3 |
| fact_order_fulfillment | purchase, approved, carrier, delivered, estimated | ✔ | | primary seller | customer, seller | | ✔ | P1 |
| fact_review | review_creation, review_answer | ✔ | | primary seller | customer | | ✔ | P1, P3 |
| fact_payment | purchase | ✔ | | | | ✔ | ✔ | P2 (optional) |
| fact_seller_month | month | | | ✔ | seller | | | P1, P2 |
| fact_seller_product_activity | month | | ✔ | ✔ | | | | P3 |
| **fact_geo_month** (new) | month | | | | geography | | | P1, P2 |
| **fact_category_month** (new) | month | | ✔ (category level) | | customer (state level) | | | P3 |

6 → **8 facts** (removed 1, added 2). 10 → **7 dimensions** (removed the 3 lead dimensions).

### 4.2 `dim_geography` — new columns

| Column | Definition | Purpose |
| --- | --- | --- |
| `zip_prefix_3` | `left(zip_prefix, 3)` | CEP sector, mid-level map aggregation (P1, P2) |
| `zip_prefix_2` | `left(zip_prefix, 2)` | CEP sub-region |
| `geo_cell_id` | Grid cell of 0.5° × 0.5° from `latitude`, `longitude` (`floor(lat / 0.5) || '_' || floor(lng / 0.5)`); null when coordinates are null | Equal-area-ish unit for **late-delivery density** maps and for hub-placement candidates (P1) |
| `geo_cell_lat`, `geo_cell_lng` | Centre of the grid cell | Map plotting, distance to hub |

Hierarchy becomes `zip_prefix → zip_prefix_3 → zip_prefix_2 → state → region`, plus `city` as a browse attribute
(city names do not nest cleanly inside zip_prefix_3). Type 1, unchanged role-playing (customer geo, seller geo).

### 4.3 New fact: `fact_geo_month` (periodic snapshot)

| | |
| --- | --- |
| Business process | Regional market activity |
| Grain | 1 zip prefix × 1 month (sparse: only zip × month pairs with at least one customer-side or seller-side event) |
| Keys | `month_date_key` (first day of month), `geo_key` |
| Source | `stg` models (same pattern as `int_seller_month_metrics`, to avoid fact-on-fact dependencies), reconciled against `fact_order_item` and `fact_order_fulfillment` |

| Measure | Side | Definition | Additivity |
| --- | --- | --- | --- |
| `orders_placed` | demand | Orders (`counts_as_sale`) whose customer zip is this zip | additive |
| `gmv_placed` | demand | Σ item_price of those orders | additive |
| `freight_placed` | demand | Σ freight_value of those orders | additive |
| `customers_active` | demand | Distinct `customer_unique_id` ordering in the month | additive across zips (one zip per order), **not** across months |
| `customers_new` | demand | Customers whose first order falls in this month | additive |
| `delivered_orders`, `late_orders` | demand | Delivered / late orders delivered to this zip | additive (late rate = late / delivered) |
| `delay_days_sum`, `delivery_lag_sum` | demand | Σ delay_days, Σ delivery_lag of delivered orders | additive (report as Σ / delivered) |
| `orders_local` | demand | Orders whose primary seller is in the same state as the customer | additive (local fulfilment share = local / placed) |
| `orders_shipped` | supply | Orders whose primary seller zip is this zip | additive |
| `gmv_sold` | supply | Σ item_price of items sold by sellers in this zip | additive |
| `sellers_active` | supply | Distinct sellers in this zip with ≥ 1 item sold in the month | additive across zips, not across months |
| `sellers_registered` | supply | Sellers located in this zip that have sold at least once up to this month (cumulative) | semi-additive (latest month only) |

Why a separate fact instead of aggregating `fact_order_item` in Power BI: distinct customer / seller counts and
the demand-vs-supply join per area are awkward in DAX, and the ML modules in P1 and P2 need exactly this table as
feature input.

### 4.4 New fact: `fact_category_month` (periodic snapshot)

| | |
| --- | --- |
| Business process | Category demand |
| Grain | 1 product category × 1 customer state × 1 month (sparse) |
| Keys | `month_date_key`, `category_key` (= category-level row of `dim_product`, see note), `customer_state_code` (degenerate, joins `dim_geography` at state level through a bi view) |

| Measure | Definition | Additivity |
| --- | --- | --- |
| `orders` | Distinct orders containing the category | additive across states and months, **not** across categories (an order can hold 2 categories; profiling: 1.14 items / order, so the overlap is small but real) |
| `items`, `gmv`, `freight` | Σ over items of the category | additive |
| `customers` | Distinct `customer_unique_id` | non-additive |
| `sellers_active` | Distinct sellers selling the category | non-additive |
| `delivered_orders`, `late_orders` | For orders containing the category | additive across states / months |
| `review_count`, `score_sum`, `low_score_count` | Latest review per order (`is_latest_for_order`) | additive |
| `price_sum`, `weight_g_sum` | For average price and weight per item | additive |

Note on `category_key`: `dim_product` is at product grain. Two options — (a) add a small conformed
`dim_category` (category_pt, category_en, category_group) and let `dim_product` reference it (snowflake for one
level), or (b) keep `category_en` as a degenerate text key in the fact. **Recommendation: (a)**, it also gives the
report a concrete star-vs-snowflake example (previously only discussed for `dim_geography`).

### 4.5 Unchanged

`fact_order_item`, `fact_order_fulfillment`, `fact_review`, `fact_payment`, all surrogate-key, unknown-member and
ratio conventions (`implementation.md` §7.3), staging rules (§9, minus the funnel bullet), SCD2 rules (§10),
incremental load design (§12).

---

## 5. KPI dictionary changes

Removed: **Lead conversion**, **Days to close**.

Added (definitions follow the existing rule: store numerator and denominator, never a stored percentage):

| KPI | Problem | Definition | Formula |
| --- | --- | --- | --- |
| Late rate (area) | P1 | Late rate of orders delivered to customers in the area | Σ late_orders / Σ delivered_orders (fact_geo_month) |
| Late volume | P1 | Absolute number of late deliveries in the area | Σ late_orders |
| Late density | P1 | Late deliveries per grid cell per month (spatial concentration; complements late rate, which can be high in areas with tiny volume) | Σ late_orders / number of months, grouped by `geo_cell_id` |
| Avg delay of late orders | P1 | How late the late orders are | Σ delay_days (late only) / Σ late_orders |
| Transit share of delivery time | P1 | Part of delivery time spent with the carrier (vs seller dispatch) | Σ transit_lag / Σ delivery_lag |
| Avg seller–customer distance | P1 | | Σ distance_km / orders with distance |
| Review gap late vs on-time | P1 | Avg score on-time − avg score late | from fact_review joined to fulfilment flag |
| Market size (GMV) | P2 | GMV placed by customers in the area | Σ gmv_placed |
| Orders per 1,000 inhabitants | P2 | E-commerce adoption, state level only (population seed) | Σ orders_placed / state_population × 1,000 |
| Active customers | P2 | | Σ customers_active (one month) |
| Active sellers | P2 | | Σ sellers_active (one month) |
| Customers per seller | P2 | Demand pressure on local supply | active customers / active sellers |
| Local fulfilment share | P2 | Share of orders served by a seller in the same state | Σ orders_local / Σ orders_placed |
| Supply gap (BRL) | P2 | GMV bought by the area from sellers outside its state | Σ gmv_placed − Σ gmv_placed with local seller |
| Area growth | P2, P3 | GMV of the last 3 months vs the same 3 months one year earlier (YoY; MoM is too noisy) | (GMV_3m − GMV_3m_ly) / GMV_3m_ly |
| Category GMV share | P3 | | category GMV / total GMV |
| Category growth | P3 | Same as area growth, per category | |
| Category satisfaction | P3 | | Σ score_sum / Σ review_count (fact_category_month) |
| Category late rate | P3 | | Σ late_orders / Σ delivered_orders |
| Seller concentration (HHI) | P3 | Σ (seller share of category GMV)² — high = few sellers dominate, risky and a recruiting opportunity | computed in bi view or ML |

The existing KPIs (GMV, Orders, AOV, Late rate, Avg delivery days, Dispatch late rate, Avg review score, Low-score
rate, Cancel rate, Seller late rate, Active sellers) are unchanged.

---

## 6. ML and decision support (schema `ml`)

General rules from `implementation.md` §13 still apply: read from `dw` / `bi`, write to `ml` append-only with
`model_run_id` + `model_version`, register in `meta.model_registry`, time-based split, no leakage, always a
baseline. Training window: 2017-01 → 2018-05, test: 2018-06 → 2018-08 (20 monthly points, profiling A8).

The current ML code (`ml/*/train.py`) is still stubs, so the modules below replace M3–M7 rather than modify them.

### 6.1 P1 — Warehouse placement and courier allocation (Logistics Manager)

**ML-1a. Late-delivery risk model** (reuses the M3 design)

- Target: `is_late` at purchase time. Features: seller–customer distance, seller state → customer state, seller
  historical late rate (before the purchase date), seller tier at purchase (SCD2 point-in-time), category group,
  weight / volume, freight value, promised lag, month, Black Friday week.
- Model: LightGBM; baseline logistic regression. Metrics: ROC-AUC, PR-AUC, recall at top 10%.
- Role in the decision: (1) quantifies **how much distance and route explain lateness** (SHAP / feature
  importance) — the argument for or against new warehouses; (2) used as the simulator in ML-1b.
- Output: `ml.order_late_risk` (unchanged DDL), `ml.late_risk_drivers(feature, importance, model_run_id)`.

**ML-1b. Hub (warehouse) placement — facility location**

- Demand points: customer zip prefixes weighted by delivered orders (or by late orders, as a scenario switch).
- Candidate sites: centres of `geo_cell_id` cells that contain sellers or high demand (keeps the problem small,
  ~a few hundred candidates).
- Method: **weighted k-means** on demand points as a fast baseline, then a **p-median MILP** (PuLP) that picks
  `k` sites minimising Σ demand × distance(customer, nearest hub), for `k = 1 … 8`.
- Evaluation per scenario: average and p90 last-mile distance, share of demand within 300 km, and the **predicted
  late rate** obtained by re-scoring orders with ML-1a after replacing the seller–customer distance with the
  hub–customer distance. This substitution is an explicit assumption (goods are pre-positioned at the hub) and is
  shown as such on the dashboard.
- Output: `ml.hub_scenario(scenario_id, k, weight_basis, avg_distance_km, p90_distance_km, demand_within_300km,
  predicted_late_rate, model_run_id)`, `ml.hub_location(scenario_id, hub_rank, geo_cell_id, lat, lng, state_code,
  assigned_orders, model_run_id)`.

**ML-1c. Courier capacity per area**

- Forecast delivered orders per state (or region) for the next 3 months (same forecasting component as ML-2a).
- Required couriers = forecast daily deliveries / deliveries per courier per day. Deliveries per courier per day
  is a **what-if parameter** (no courier data exists in the dataset).
- Priority: rank areas by expected late orders = forecast orders × current late rate, adjusted by the transit
  share (areas where lateness happens in transit benefit from couriers; areas where it happens at dispatch need
  seller action instead — this distinction comes from the dashboard lags).
- Output: `ml.courier_plan(month, state_code, forecast_orders, forecast_late_orders, transit_share,
  priority_rank, model_run_id)`; Power BI computes couriers from the what-if parameter.

### 6.2 P2 — Which areas to develop (Expansion / Commerce Manager)

**ML-2a. Area demand forecast**

- Monthly GMV and orders per state (27 series) and per region (5 series); per zip_prefix_2 only if the series are
  dense enough (decide during EDA).
- Models: seasonal-naive and moving-average baselines vs ETS (statsmodels). Metric: MAPE / sMAPE on the 3 test
  months. With 20 points, simple models are the honest choice; the report states this.
- Output: `ml.area_forecast(month, geo_level, geo_code, metric, yhat, yhat_lower, yhat_upper, model_run_id)`
  (generalises the old `ml.gmv_forecast`).

**ML-2b. Area segmentation**

- Unit: state (and zip_prefix_2 as a second level). Features from `fact_geo_month` over the last 12 months:
  orders per 1,000 inhabitants (state level), GMV, YoY growth, AOV, customers per seller, local fulfilment share,
  late rate, average delivery days.
- Method: standardise → K-means (k chosen by silhouette, expected 4–5) with a rule-based labelling of clusters,
  e.g. *Core market*, *Underserved high demand* (high demand, low local supply, high late rate), *Emerging*
  (low size, high growth), *Low priority*.
- Output: `ml.area_segment(geo_level, geo_code, segment, cluster_id, features_json, model_run_id)`.

**ML-2c. Area opportunity score and recommendation**

- Score = weighted sum of normalised forecast growth, market size, supply gap and (inverse) late rate. Weights
  are what-if parameters in Power BI so the manager can see how the ranking changes; default weights are
  documented.
- The recommended action follows from the segment: *recruit local sellers* (supply gap), *add logistics
  capacity* (late rate, links to P1), *marketing push* (low penetration, good service).
- Output: `ml.area_opportunity(geo_level, geo_code, opportunity_score, rank, recommended_action, top_drivers,
  model_run_id)` + rows in `ml.recommendations`.

### 6.3 P3 — Which categories to develop (Category Manager)

**ML-3a. Category demand forecast**

- Monthly orders / GMV per category group (~10 series, dense) and per category for the top categories (the long
  tail is too sparse; categories under a minimum monthly volume use the group forecast).
- Same model set and metrics as ML-2a. Output: `ml.category_forecast(month, category_level, category_code,
  metric, yhat, yhat_lower, yhat_upper, model_run_id)`.

**ML-3b. Category portfolio classification**

- Growth–share matrix: x = GMV share, y = forecast growth (ML-3a), adjusted by satisfaction and late rate. Four
  classes: *Grow* (high growth, high share), *Invest selectively* (high growth, low share), *Maintain* (low
  growth, high share), *Review / deprioritise* (low growth, low share). Categories with low satisfaction or high
  late rate get a *Fix quality first* flag regardless of quadrant.
- Seller concentration (HHI) marks categories where recruiting sellers lowers dependency risk.
- Output: `ml.category_opportunity(category_code, gmv_share, forecast_growth, avg_score, late_rate, hhi,
  portfolio_class, quality_flag, opportunity_score, rank, model_run_id)` + rows in `ml.recommendations`.

Not planned: market-basket / association rules — orders average 1.14 items (profiling), too few multi-category
baskets for stable rules.

### 6.4 `ml.recommendations`

Unchanged DDL. `decision_maker` ∈ {`logistics`, `expansion`, `category`}; `subject_type` ∈ {`hub_scenario`,
`state`, `zip_prefix_2`, `category`}. Each row keeps `action`, `rationale`, `score`, `status = 'proposed'`, and can
be accepted / rejected through `meta.decision_log` (COULD).

### 6.5 DDL changes (`docker/postgres/init/03_ml.sql`)

| Action | Tables |
| --- | --- |
| Keep | `order_late_risk`, `recommendations` |
| Remove | `promise_whatif`, `customer_segment_history`, `voucher_allocation`, `seller_risk_score`, `channel_value` |
| Rename / generalise | `gmv_forecast` → `area_forecast` |
| Add | `late_risk_drivers`, `hub_scenario`, `hub_location`, `courier_plan`, `area_segment`, `area_opportunity`, `category_forecast`, `category_opportunity` |

`promise_whatif` (promise-date buffer) is dropped from the core scope; it can come back as a COULD on the P1 page
if time allows, since the data shows Olist promises ~23.7 days for a ~12.6-day average delivery.

### 6.6 Code layout

```
ml/
├── common/                 # db.py, registry.py, features.py (unchanged)
├── forecasting.py          # shared baselines + ETS, used by ML-1c, ML-2a, ML-3a
├── p1_logistics/           # late_risk.py (ML-1a), hub_placement.py (ML-1b), courier_plan.py (ML-1c)
├── p2_regional/            # area_forecast.py, area_segment.py, area_opportunity.py
├── p3_category/            # category_forecast.py, category_portfolio.py
└── recommendations.py      # reads the three problems' outputs → ml.recommendations
```

`ml/crm_segment_voucher/`, `ml/seller_risk/`, `ml/gmv_forecast/`, `ml/late_risk/` are removed (their content moves
into the folders above). `make ml` and the Airflow DAG run `p1_logistics`, `p2_regional`, `p3_category` in parallel,
then `recommendations`.

---

## 7. Serving layer and Power BI

### 7.1 `bi` views

| Action | Views |
| --- | --- |
| Remove | `v_dim_lead_origin`, `v_dim_lead_profile`, `v_dim_sales_rep`, `v_fact_lead_funnel` |
| Change | `v_dim_seller` (drop `is_from_funnel`), `v_dim_customer` (no segment join), `v_dim_customer_geo` / `v_dim_seller_geo` (new zip_prefix_3 / zip_prefix_2 / geo_cell columns) |
| Add (dw) | `v_fact_geo_month`, `v_fact_category_month`, `v_dim_category` (if option 4.4 a), `v_dim_state` (state-level geography + population, for `fact_category_month` and per-capita KPIs) |
| Add (ml, latest `model_run_id` only) | `v_order_late_risk`, `v_late_risk_drivers`, `v_hub_scenario`, `v_hub_location`, `v_courier_plan`, `v_area_forecast`, `v_area_segment`, `v_area_opportunity`, `v_category_forecast`, `v_category_opportunity`, `v_recommendations` |

### 7.2 Power BI pages (replaces the 8-page plan in `implementation.md` §14.2)

| # | Page | Problem | Simon phase | Main visuals |
| --- | --- | --- | --- | --- |
| 1 | Executive Overview | all | Intelligence | GMV, orders, late rate, avg score trend; one KPI tile per problem linking to its pages |
| 2 | Late Delivery by Area | P1 | Intelligence | Filled map by state (late rate), bubble / heat map by geo cell (late density), route matrix seller state × customer state, lag decomposition (approval / dispatch / transit), score on-time vs late |
| 3 | Hub & Courier Planning | P1 | Design / Choice | Slider `k` hubs → map of proposed hubs and assigned areas, distance and predicted late rate per scenario; courier table with what-if *deliveries per courier per day*; drivers chart from ML-1a |
| 4 | Regional Market | P2 | Intelligence | Drill region → state → zip_prefix_2 → zip_prefix_3: GMV, orders, customers, sellers, customers per seller, orders per 1,000 inhabitants, local fulfilment share, YoY trend |
| 5 | Expansion Opportunities | P2 | Design / Choice | Area segments on a map, opportunity ranking with weight sliders, forecast with interval, recommended action per area |
| 6 | Category Performance | P3 | Intelligence | Top categories by GMV / orders / growth, seasonality, category × region matrix, satisfaction and late rate per category, price and freight share |
| 7 | Category Opportunities | P3 | Design / Choice | Growth–share matrix (scatter), category forecast, quality flags, HHI, recommended action per category |
| 8 | Data Quality & Pipeline Health | all | Trust | Unchanged |

Owners are reassigned in `PROJECT_PLAN.md` (open question Q4).

---

## 8. Orchestration and Makefile

```
[download_kaggle, copy_manual, gen_holidays] → upload_to_lake → load_raw
  → dbt_deps → dbt_seed → dbt_build (stg, dw, bi)
  → [ml_p1_logistics, ml_p2_regional, ml_p3_category] → ml_recommendations
  → meta_publish → dbt_docs_generate
```

`download_kaggle` downloads one dataset. `make ml` calls the three problem packages then `recommendations`.
No other target changes.

---

## 9. Migration plan

Work is split into three PRs so each one keeps `dbt build` green. Branch names follow `feat/<task-id>-<desc>`.

| PR | Task IDs | Content | Done when |
| --- | --- | --- | --- |
| 1. Remove funnel | R0-1 … R0-4 | Section 3.3 in full: ingestion, `data/raw/marketing_funnel/`, staging, lead dims, `fact_lead_funnel`, `dim_seller` funnel union, bi views, tests, `dq_issue_summary`, ML stubs and DDL for CRM / seller risk / channel value | `make all` from a clean DB passes; `raw` has 12 tables; no reference to `mql`, `closed_deals`, `lead_`, `funnel` outside `docs/profiling.md` history and the changelog |
| 2. Warehouse for the three problems | R1-1 (`dim_geography` columns), R2-1 (`fact_geo_month`), R3-1 (`dim_category`, `fact_category_month`), R-T (tests), R-BI (bi views) | Section 4 and 7.1 (dw part) | New facts have YAML + key tests; reconciliation: Σ `gmv_placed` = Σ `gmv_sold` = Σ GMV of `fact_order_item`; Σ `late_orders` of `fact_geo_month` = Σ `is_late` of `fact_order_fulfillment`; Σ `items` of `fact_category_month` = item count of `fact_order_item` |
| 3. ML and Power BI | R1-2 … R1-4 (ML-1a/b/c), R2-2 … R2-4 (ML-2a/b/c), R3-2, R3-3 (ML-3a/b), R-REC, R-PBI | Section 6, 7.1 (ml part), 7.2 | Each module registered in `meta.model_registry` with baseline vs model metrics; pages 2–7 built |

Documentation updates go with PR 1 (scope, sources, changelog) and PR 2 (warehouse, KPI dictionary), so the
design document never describes something that does not exist yet.

Suggested order given the deadline (2026-11-13): PR 1 on 06–07/11, PR 2 on 07–09/11, PR 3 on 08–12/11 (ML and
Power BI start on 08/11 against stub tables with the final schema, as in the original plan), report and demo
rehearsal on 12–13/11.

---

## 10. Risks and limitations (to state in the report)

| Risk | Impact | Mitigation |
| --- | --- | --- |
| No warehouse, carrier or courier data in the dataset | Hub placement and courier numbers cannot be validated against reality | Present them as scenarios driven by explicit assumptions (pre-positioned stock, deliveries per courier per day), with sliders; validate only the late-risk model and the forecasts, which have ground truth |
| Distance substitution in ML-1b (hub–customer instead of seller–customer) | Predicted late rate per scenario is an extrapolation | Label it *indicative*; show distance metrics, which need no model, next to it |
| Short time series (20 months), Olist growth phase in 2017 | YoY growth in early 2017 and forecasts are noisy; growth partly reflects Olist's own expansion | Use the last 12 months for growth features, compare against simple baselines, show intervals |
| Sparse zip prefixes (~19k zips, ~99k orders) | Zip-level rates are unstable | Rates only at zip_prefix_2 / state / geo cell with a minimum-volume filter; zip level used for maps of counts only |
| Population only at state level | Per-capita adoption only for 27 states | Use customers per seller and growth at lower levels |
| Category = Olist taxonomy (73 categories, 610 products `unknown`) | Some categories are thin or ambiguous | Forecast at category-group level for the long tail; keep `unknown` visible as its own row |

---

## 11. Open questions

| # | Question | Default if no answer |
| --- | --- | --- |
| Q1 | Keep `fact_payment` and the payment views, or drop them to shrink scope? | Keep (already built, no extra work) |
| Q2 | `fact_category_month`: add `dim_category` (option a) or keep the category as a degenerate key (option b)? | Option a |
| Q3 | Bring back the promise-date what-if (`ml.promise_whatif`) on page 3? | COULD, only after pages 2–7 are done |
| Q4 | New ownership: one member per problem (P1 / P2 / P3) end to end, or keep the layer split (platform / dims / facts / ML)? | Keep the layer split for PR 1–2; split PR 3 by problem |
| Q5 | Rename the decision-maker roles in the report (Logistics Manager, Expansion Manager, Category Manager)? | Use these names |
