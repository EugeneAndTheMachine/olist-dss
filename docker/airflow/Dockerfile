ARG AIRFLOW_VERSION=2.10.5
ARG PYTHON_VERSION=3.11
FROM apache/airflow:${AIRFLOW_VERSION}-python${PYTHON_VERSION}

ARG AIRFLOW_VERSION=2.10.5
ARG PYTHON_VERSION=3.11
ARG DBT_CORE_VERSION=1.9.*
ARG DBT_POSTGRES_VERSION=1.9.*

# Thư viện cho ingestion + ML, cài theo constraint của Airflow để không phá dependency của Airflow
COPY requirements-airflow.txt /tmp/requirements-airflow.txt
RUN pip install --no-cache-dir "apache-airflow==${AIRFLOW_VERSION}" -r /tmp/requirements-airflow.txt \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"

# dbt trong venv riêng: tránh xung đột dependency với Airflow. Task dbt gọi /opt/airflow/dbt_venv/bin/dbt
RUN python -m venv /opt/airflow/dbt_venv \
    && /opt/airflow/dbt_venv/bin/pip install --no-cache-dir \
       "dbt-core==${DBT_CORE_VERSION}" "dbt-postgres==${DBT_POSTGRES_VERSION}"

WORKDIR /opt/olist
