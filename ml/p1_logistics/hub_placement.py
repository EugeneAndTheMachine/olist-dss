"""ML-1b: Tối ưu vị trí đặt kho / hub (Facility Location) cho Logistics Manager (P1).

Thiết kế (docs/refactor_plan.md mục 6.1):
- Điểm cầu (demand points): các ô lưới địa lý 0.5° × 0.5° (geo_cell_id, BR-K4) của khách hàng,
  trọng số theo số đơn đã giao (delivered_orders) hoặc số đơn giao trễ (late_orders).
- Điểm ứng viên đặt kho (candidate sites): top các geo_cell_id có lưu lượng đơn / mật độ trễ cao nhất.
- Phương pháp:
  1. Baseline: Weighted K-Means (k = 1..8), gắn tâm cụm về ô ứng viên gần nhất.
  2. Tối ưu chính: Bài toán quy hoạch nguyên hỗn hợp p-median MILP (PuLP) chọn k vị trí kho
     tối thiểu hoá Σ demand_i × distance(customer_cell_i, hub_j).
- Đánh giá mỗi kịch bản:
  - Khoảng cách chặng cuối trung bình (avg_distance_km) và phân vị 90 (p90_distance_km).
  - Tỷ lệ đơn hàng nằm trong bán kính 300 km quanh kho gần nhất (demand_within_300km).
  - Tỷ lệ giao trễ dự báo (predicted_late_rate): chấm lại bằng mô hình ML-1a khi thay khoảng cách
    seller–customer bằng khoảng cách hub–customer (giả định hàng được lưu kho sẵn tại hub).
"""
from __future__ import annotations

import logging
import sys
from pathlib import Path
from typing import Any

# Cho phép chạy trực tiếp bằng `python3 ml/p1_logistics/hub_placement.py`
_REPO_ROOT = str(Path(__file__).resolve().parents[2])
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

import numpy as np
import pandas as pd
import pulp
from sklearn.cluster import KMeans
from sklearn.pipeline import Pipeline

from ingestion.config import get_settings, setup_logging
from ml.common.db import append_df
from ml.common.registry import new_run, register, tag_output
from ml.p1_logistics import ensure_p1_tables
from ml.p1_logistics.late_risk import ALL_FEATURES, engineer_features, load_order_dataset, run as run_late_risk

logger = logging.getLogger(__name__)

MODEL_NAME = "p1_hub_placement"
MODEL_VERSION = "1.0.0"
K_VALUES = list(range(1, 9))
MAX_CANDIDATE_CELLS = 50


def haversine_matrix_km(lat1: np.ndarray, lng1: np.ndarray, lat2: np.ndarray, lng2: np.ndarray) -> np.ndarray:
    """Tính ma trận khoảng cách Haversine (km) kích thước (N, M)."""
    r_lat1 = np.radians(lat1)[:, None]
    r_lng1 = np.radians(lng1)[:, None]
    r_lat2 = np.radians(lat2)[None, :]
    r_lng2 = np.radians(lng2)[None, :]
    dlat = r_lat2 - r_lat1
    dlng = r_lng2 - r_lng1
    a = np.sin(dlat / 2.0) ** 2 + np.cos(r_lat1) * np.cos(r_lat2) * (np.sin(dlng / 2.0) ** 2)
    return 2.0 * 6371.0 * np.arcsin(np.sqrt(np.clip(a, 0.0, 1.0)))


def build_demand_cells(df_orders: pd.DataFrame) -> pd.DataFrame:
    """Gom đơn hàng theo ô lưới 0.5° × 0.5° (BR-K4)."""
    valid = df_orders.dropna(subset=["customer_lat", "customer_lng"]).copy()
    lat_idx = np.floor(valid["customer_lat"].to_numpy(dtype=float) / 0.5).astype(int)
    lng_idx = np.floor(valid["customer_lng"].to_numpy(dtype=float) / 0.5).astype(int)
    valid["geo_cell_id"] = [f"{a}_{b}" for a, b in zip(lat_idx, lng_idx)]
    valid["cell_lat"] = (lat_idx + 0.5) * 0.5
    valid["cell_lng"] = (lng_idx + 0.5) * 0.5

    cells = (
        valid.groupby(["geo_cell_id", "cell_lat", "cell_lng"], as_index=False)
        .agg(
            delivered_orders=("order_id", "count"),
            late_orders=("is_late", "sum"),
            state_code=("customer_state", lambda s: s.mode().iloc[0] if not s.mode().empty else "SP"),
        )
        .sort_values("delivered_orders", ascending=False)
        .reset_index(drop=True)
    )
    return cells


def solve_kmeans_hubs(cells: pd.DataFrame, candidates: pd.DataFrame, weights: np.ndarray, k: int) -> list[int]:
    """Baseline: Weighted K-Means trên toạ độ cầu, chiếu tâm cụm về ô ứng viên gần nhất."""
    coords = cells[["cell_lat", "cell_lng"]].to_numpy(dtype=float)
    w = np.maximum(weights, 1e-3)
    km = KMeans(n_clusters=k, random_state=42, n_init=10)
    km.fit(coords, sample_weight=w)
    cand_coords = candidates[["cell_lat", "cell_lng"]].to_numpy(dtype=float)
    dist_to_cand = haversine_matrix_km(km.cluster_centers_[:, 0], km.cluster_centers_[:, 1], cand_coords[:, 0], cand_coords[:, 1])

    chosen: list[int] = []
    for row in dist_to_cand:
        for idx in np.argsort(row):
            if int(idx) not in chosen:
                chosen.append(int(idx))
                break
    return sorted(chosen)


def solve_p_median_milp(dist_matrix: np.ndarray, weights: np.ndarray, k: int) -> list[int]:
    """Bài toán quy hoạch nguyên p-median (PuLP) chọn đúng k hub tối thiểu hoá tổng khoảng cách có trọng số."""
    n_demand, n_cand = dist_matrix.shape
    prob = pulp.LpProblem(f"p_median_k{k}", pulp.LpMinimize)

    y = [pulp.LpVariable(f"y_{j}", cat="Binary") for j in range(n_cand)]
    x = [[pulp.LpVariable(f"x_{i}_{j}", lowBound=0, upBound=1, cat="Continuous") for j in range(n_cand)] for i in range(n_demand)]

    # Hàm mục tiêu: min Σ_i Σ_j w_i * d_ij * x_ij
    prob += pulp.lpSum(float(weights[i]) * float(dist_matrix[i, j]) * x[i][j] for i in range(n_demand) for j in range(n_cand))

    # Mở đúng k kho
    prob += pulp.lpSum(y) == k

    # Mỗi vùng cầu i được gán cho 1 kho đã mở
    for i in range(n_demand):
        prob += pulp.lpSum(x[i][j] for j in range(n_cand)) == 1
        for j in range(n_cand):
            prob += x[i][j] <= y[j]

    solver = pulp.PULP_CBC_CMD(msg=False, timeLimit=30)
    prob.solve(solver)
    chosen = [j for j in range(n_cand) if (pulp.value(y[j]) or 0.0) > 0.5]
    if len(chosen) != k:
        # Phòng trường hợp solver dừng sớm: lấy top k theo giá trị y_j
        vals = [float(pulp.value(y[j]) or 0.0) for j in range(n_cand)]
        chosen = [int(idx) for idx in np.argsort(vals)[::-1][:k]]
    return sorted(chosen)


def weighted_percentile(values: np.ndarray, weights: np.ndarray, q: float = 0.90) -> float:
    order = np.argsort(values)
    v = values[order]
    w = weights[order]
    cum = np.cumsum(w)
    cutoff = q * float(cum[-1])
    idx = int(np.searchsorted(cum, cutoff))
    return float(v[min(idx, len(v) - 1)])


def predict_scenario_late_rate(
    lgbm_model: Pipeline,
    df_sample: pd.DataFrame,
    hub_lats: np.ndarray,
    hub_lngs: np.ndarray,
    hub_states: list[str],
) -> float:
    """Chấm lại xác suất giao trễ khi thay khoảng cách seller–customer bằng khoảng cách từ hub gần nhất."""
    cust_lat = df_sample["customer_lat"].to_numpy(dtype=float)
    cust_lng = df_sample["customer_lng"].to_numpy(dtype=float)
    dmat = haversine_matrix_km(cust_lat, cust_lng, hub_lats, hub_lngs)
    nearest_idx = np.argmin(dmat, axis=1)
    min_dist = dmat[np.arange(len(df_sample)), nearest_idx]
    nearest_state = pd.Series([hub_states[i] for i in nearest_idx], index=df_sample.index)

    sim_df = df_sample[ALL_FEATURES].copy()
    sim_df["seller_customer_distance_km"] = min_dist
    sim_df["seller_state"] = nearest_state
    sim_df["same_state"] = (sim_df["seller_state"] == sim_df["customer_state"]).astype(int)
    probs = lgbm_model.predict_proba(sim_df)[:, 1]
    return float(np.mean(probs))


def run(lgbm_model: Pipeline | None = None, df_orders: pd.DataFrame | None = None) -> dict[str, Any]:
    ensure_p1_tables()
    if lgbm_model is None or df_orders is None:
        lgbm_model, df_orders, _ = run_late_risk()
    elif "seller_hist_late_rate" not in df_orders.columns:
        df_orders = engineer_features(df_orders)

    cells = build_demand_cells(df_orders)
    # Gộp top ô theo delivered_orders và late_orders làm tập ứng viên đặt kho
    top_deliv = cells.nlargest(MAX_CANDIDATE_CELLS, "delivered_orders")
    top_late = cells.nlargest(MAX_CANDIDATE_CELLS, "late_orders")
    candidates = (
        pd.concat([top_deliv, top_late], ignore_index=True)
        .drop_duplicates(subset=["geo_cell_id"])
        .reset_index(drop=True)
    )

    dist_matrix = haversine_matrix_km(
        cells["cell_lat"].to_numpy(dtype=float),
        cells["cell_lng"].to_numpy(dtype=float),
        candidates["cell_lat"].to_numpy(dtype=float),
        candidates["cell_lng"].to_numpy(dtype=float),
    )

    # Lấy mẫu đại diện các đơn có toạ độ để chấm lại predicted_late_rate nhanh và chính xác
    valid_orders = df_orders.dropna(subset=["customer_lat", "customer_lng"]).copy()
    if len(valid_orders) > 20000:
        sample_orders = valid_orders.sample(n=20000, random_state=42).reset_index(drop=True)
    else:
        sample_orders = valid_orders.reset_index(drop=True)

    scenario_rows: list[dict[str, Any]] = []
    location_rows: list[dict[str, Any]] = []

    for weight_basis in ["delivered_orders", "late_orders"]:
        weights = cells[weight_basis].to_numpy(dtype=float)
        deliv_counts = cells["delivered_orders"].to_numpy(dtype=float)
        late_counts = cells["late_orders"].to_numpy(dtype=float)

        for k in K_VALUES:
            for method in ["p_median_milp", "weighted_kmeans"]:
                if method == "p_median_milp":
                    chosen_cand_idx = solve_p_median_milp(dist_matrix, weights, k)
                else:
                    chosen_cand_idx = solve_kmeans_hubs(cells, candidates, weights, k)

                sub_dist = dist_matrix[:, chosen_cand_idx]
                nearest_local = np.argmin(sub_dist, axis=1)
                min_dist = sub_dist[np.arange(len(cells)), nearest_local]

                avg_dist = float(np.average(min_dist, weights=deliv_counts))
                p90_dist = weighted_percentile(min_dist, deliv_counts, 0.90)
                within_300 = float(np.sum(deliv_counts[min_dist <= 300.0]) / np.sum(deliv_counts))

                hub_df = candidates.iloc[chosen_cand_idx].reset_index(drop=True)
                pred_late = predict_scenario_late_rate(
                    lgbm_model,
                    sample_orders,
                    hub_df["cell_lat"].to_numpy(dtype=float),
                    hub_df["cell_lng"].to_numpy(dtype=float),
                    hub_df["state_code"].astype(str).tolist(),
                )

                scenario_id = f"{method}_{weight_basis}_k{k}"
                scenario_rows.append(
                    {
                        "scenario_id": scenario_id,
                        "k": k,
                        "weight_basis": weight_basis,
                        "method": method,
                        "avg_distance_km": round(avg_dist, 2),
                        "p90_distance_km": round(p90_dist, 2),
                        "demand_within_300km": round(within_300, 5),
                        "predicted_late_rate": round(pred_late, 5),
                    }
                )

                # Chỉ lưu chi tiết vị trí hub cho phương pháp tối ưu chính p_median_milp (và kmeans để so sánh)
                hub_stats: list[dict[str, Any]] = []
                for h_idx, cand_i in enumerate(chosen_cand_idx):
                    mask = nearest_local == h_idx
                    assigned_ord = int(np.sum(deliv_counts[mask]))
                    assigned_late = int(np.sum(late_counts[mask]))
                    avg_assigned_dist = (
                        float(np.average(min_dist[mask], weights=deliv_counts[mask]))
                        if assigned_ord > 0
                        else 0.0
                    )
                    cand_row = candidates.iloc[cand_i]
                    hub_stats.append(
                        {
                            "scenario_id": scenario_id,
                            "k": k,
                            "weight_basis": weight_basis,
                            "geo_cell_id": str(cand_row["geo_cell_id"]),
                            "lat": round(float(cand_row["cell_lat"]), 5),
                            "lng": round(float(cand_row["cell_lng"]), 5),
                            "state_code": str(cand_row["state_code"]),
                            "assigned_orders": assigned_ord,
                            "assigned_late_orders": assigned_late,
                            "avg_assigned_distance_km": round(avg_assigned_dist, 2),
                        }
                    )
                hub_stats.sort(key=lambda r: r["assigned_orders"], reverse=True)
                for rank_no, item in enumerate(hub_stats, start=1):
                    item["hub_rank"] = rank_no
                    location_rows.append(item)

    scenarios_df = pd.DataFrame(scenario_rows)
    locations_df = pd.DataFrame(location_rows)

    milp_k1 = scenarios_df.query("method == 'p_median_milp' and weight_basis == 'delivered_orders' and k == 1").iloc[0]
    milp_k5 = scenarios_df.query("method == 'p_median_milp' and weight_basis == 'delivered_orders' and k == 5").iloc[0]
    km_k5 = scenarios_df.query("method == 'weighted_kmeans' and weight_basis == 'delivered_orders' and k == 5").iloc[0]

    metrics = {
        "n_demand_cells": int(len(cells)),
        "n_candidate_cells": int(len(candidates)),
        "k1_avg_distance_km": float(milp_k1["avg_distance_km"]),
        "k5_milp_avg_distance_km": float(milp_k5["avg_distance_km"]),
        "k5_kmeans_avg_distance_km": float(km_k5["avg_distance_km"]),
        "k5_milp_within_300km": float(milp_k5["demand_within_300km"]),
        "k5_milp_predicted_late_rate": float(milp_k5["predicted_late_rate"]),
    }
    logger.info("ML-1b metrics: %s", metrics)

    model_run = new_run(MODEL_NAME, MODEL_VERSION)
    append_df(tag_output(scenarios_df, model_run), "hub_scenario")
    append_df(tag_output(locations_df, model_run), "hub_location")
    register(
        model_run,
        train_window=f"{get_settings().analysis_start}..{get_settings().analysis_end}",
        params={"k_values": K_VALUES, "max_candidate_cells": MAX_CANDIDATE_CELLS},
        metrics=metrics,
    )

    print("\n" + "=" * 86)
    print(" [ML-1b] BENCHMARK ĐẶT KHO / HUB: p-median MILP (PuLP) vs Weighted K-Means")
    print("=" * 86)
    sub_scen = scenarios_df.query("weight_basis == 'late_orders'").sort_values(["k", "method"])
    print(sub_scen[["k", "method", "avg_distance_km", "p90_distance_km", "demand_within_300km", "predicted_late_rate"]].to_string(index=False))
    print("-" * 86)
    print(" Toạ độ 5 kho tối ưu (k=5, p_median_milp, trọng số late_orders):")
    sub_loc = locations_df.query("scenario_id == 'p_median_milp_late_orders_k5'").sort_values("hub_rank")
    print(sub_loc[["hub_rank", "state_code", "geo_cell_id", "lat", "lng", "assigned_orders", "assigned_late_orders", "avg_assigned_distance_km"]].to_string(index=False))
    print("=" * 86 + "\n")
    return metrics


def main() -> None:
    setup_logging()
    run()


if __name__ == "__main__":
    main()

