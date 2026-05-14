-- ReconcileAI Accelerator Schema
-- Client-sellable starter SQL for a reconciliation and reporting project

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;
CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS bronze.employee_source (
    employee_id      INT,
    full_name        VARCHAR(200),
    department       VARCHAR(100),
    city             VARCHAR(100),
    salary           DECIMAL(18,2),
    is_active        INT,
    ingestion_ts     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bronze.employee_target (
    employee_id      INT,
    full_name        VARCHAR(200),
    department       VARCHAR(100),
    city             VARCHAR(100),
    salary           DECIMAL(18,2),
    is_active        INT,
    ingestion_ts     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS silver.employee_source_std AS
SELECT
    employee_id,
    TRIM(full_name) AS full_name,
    CASE WHEN department = 'IT Ops' THEN 'IT' ELSE TRIM(department) END AS department,
    TRIM(city) AS city,
    CAST(salary AS DECIMAL(18,2)) AS salary,
    CAST(COALESCE(is_active, 0) AS INT) AS is_active
FROM bronze.employee_source
WHERE employee_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS silver.employee_target_std AS
SELECT
    employee_id,
    TRIM(full_name) AS full_name,
    CASE WHEN department = 'IT Ops' THEN 'IT' ELSE TRIM(department) END AS department,
    TRIM(city) AS city,
    CAST(salary AS DECIMAL(18,2)) AS salary,
    CAST(COALESCE(is_active, 0) AS INT) AS is_active
FROM bronze.employee_target
WHERE employee_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS audit.employee_missing_in_target AS
SELECT s.*
FROM silver.employee_source_std s
LEFT JOIN silver.employee_target_std t
    ON s.employee_id = t.employee_id
WHERE t.employee_id IS NULL;

CREATE TABLE IF NOT EXISTS audit.employee_missing_in_source AS
SELECT t.*
FROM silver.employee_target_std t
LEFT JOIN silver.employee_source_std s
    ON t.employee_id = s.employee_id
WHERE s.employee_id IS NULL;

CREATE TABLE IF NOT EXISTS audit.employee_mismatch_detail AS
SELECT
    s.employee_id,
    'full_name' AS column_name,
    s.full_name AS source_value,
    t.full_name AS target_value,
    CURRENT_TIMESTAMP AS audit_ts
FROM silver.employee_source_std s
JOIN silver.employee_target_std t
    ON s.employee_id = t.employee_id
WHERE COALESCE(s.full_name, '') <> COALESCE(t.full_name, '')

UNION ALL

SELECT
    s.employee_id,
    'department' AS column_name,
    s.department AS source_value,
    t.department AS target_value,
    CURRENT_TIMESTAMP AS audit_ts
FROM silver.employee_source_std s
JOIN silver.employee_target_std t
    ON s.employee_id = t.employee_id
WHERE COALESCE(s.department, '') <> COALESCE(t.department, '')

UNION ALL

SELECT
    s.employee_id,
    'city' AS column_name,
    s.city AS source_value,
    t.city AS target_value,
    CURRENT_TIMESTAMP AS audit_ts
FROM silver.employee_source_std s
JOIN silver.employee_target_std t
    ON s.employee_id = t.employee_id
WHERE COALESCE(s.city, '') <> COALESCE(t.city, '')

UNION ALL

SELECT
    s.employee_id,
    'salary' AS column_name,
    CAST(s.salary AS VARCHAR(100)) AS source_value,
    CAST(t.salary AS VARCHAR(100)) AS target_value,
    CURRENT_TIMESTAMP AS audit_ts
FROM silver.employee_source_std s
JOIN silver.employee_target_std t
    ON s.employee_id = t.employee_id
WHERE COALESCE(s.salary, 0) <> COALESCE(t.salary, 0)

UNION ALL

SELECT
    s.employee_id,
    'is_active' AS column_name,
    CAST(s.is_active AS VARCHAR(100)) AS source_value,
    CAST(t.is_active AS VARCHAR(100)) AS target_value,
    CURRENT_TIMESTAMP AS audit_ts
FROM silver.employee_source_std s
JOIN silver.employee_target_std t
    ON s.employee_id = t.employee_id
WHERE COALESCE(s.is_active, 0) <> COALESCE(t.is_active, 0);

CREATE TABLE IF NOT EXISTS gold.employee_quality_summary AS
SELECT
    CURRENT_DATE AS run_date,
    (SELECT COUNT(*) FROM silver.employee_source_std) AS source_count,
    (SELECT COUNT(*) FROM silver.employee_target_std) AS target_count,
    (SELECT COUNT(*) FROM audit.employee_missing_in_target) AS missing_in_target_count,
    (SELECT COUNT(*) FROM audit.employee_missing_in_source) AS missing_in_source_count,
    (SELECT COUNT(*) FROM audit.employee_mismatch_detail) AS field_mismatch_count;

CREATE TABLE IF NOT EXISTS gold.employee_feature_base AS
SELECT
    employee_id,
    department,
    city,
    salary,
    is_active,
    CASE WHEN salary >= 50000 THEN 1 ELSE 0 END AS high_salary_flag
FROM silver.employee_source_std;
