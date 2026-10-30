-- Chạy một lần khi volume pgdata trống (docker-entrypoint-initdb.d), kết nối vào POSTGRES_DB = olist_dw.
-- DB metadata cho Airflow. Tên cố định "airflow" (khớp AIRFLOW_DB trong .env).
create database airflow;
