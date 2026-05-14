
/*
===============================================================================
Project: Kimball Data Warehouse Design based on Medallion Architecture Sample
Target Platform: SQL Server
Author: OpenAI
Purpose:
    This script creates a complete SQL-first medallion + Kimball architecture
    using the sample sales/customer/product domain from the uploaded project.

Architecture:
    bronze = raw landing tables
    silver = cleansed and conformed integration tables
    gold   = Kimball dimensional warehouse tables

Business Process:
    Sales Order Analytics

Core Dimensions:
    - dim_date
    - dim_customer
    - dim_product
    - dim_location

Core Facts:
    - fact_sales

Design Notes:
    - Bronze keeps source-shaped raw tables
    - Silver standardizes names, datatypes, and business rules
    - Gold contains surrogate keys and star schema design
    - SCD Type 2 is implemented for customer and product dimensions
===============================================================================
*/

USE master;
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'KimballMedallionDW')
BEGIN
    ALTER DATABASE KimballMedallionDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE KimballMedallionDW;
END;
GO

CREATE DATABASE KimballMedallionDW;
GO

USE KimballMedallionDW;
GO

/*=============================================================================
  1) CREATE SCHEMAS
=============================================================================*/
CREATE SCHEMA bronze;
GO
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;
GO
CREATE SCHEMA audit;
GO

/*=============================================================================
  2) AUDIT / ETL CONTROL TABLES
=============================================================================*/
CREATE TABLE audit.etl_batch
(
    batch_id             INT IDENTITY(1,1) PRIMARY KEY,
    batch_name           NVARCHAR(200) NOT NULL,
    source_system        NVARCHAR(100) NOT NULL,
    load_start_dts       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    load_end_dts         DATETIME2 NULL,
    load_status          NVARCHAR(30) NOT NULL DEFAULT 'STARTED',
    rows_inserted        INT NULL,
    rows_updated         INT NULL,
    rows_rejected        INT NULL,
    error_message        NVARCHAR(MAX) NULL
);
GO

/*=============================================================================
  3) BRONZE LAYER (RAW LANDING TABLES)
     These closely follow the source structures from the sample medallion project.
=============================================================================*/
CREATE TABLE bronze.crm_cust_info
(
    cst_id               INT NULL,
    cst_key              NVARCHAR(50) NULL,
    cst_firstname        NVARCHAR(100) NULL,
    cst_lastname         NVARCHAR(100) NULL,
    cst_marital_status   NVARCHAR(50) NULL,
    cst_gndr             NVARCHAR(50) NULL,
    cst_create_date      NVARCHAR(50) NULL,
    src_file_name        NVARCHAR(260) NULL,
    load_dts             DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE bronze.crm_prd_info
(
    prd_id               INT NULL,
    prd_key              NVARCHAR(50) NULL,
    prd_nm               NVARCHAR(200) NULL,
    prd_cost             NVARCHAR(50) NULL,
    prd_line             NVARCHAR(50) NULL,
    prd_start_dt         NVARCHAR(50) NULL,
    prd_end_dt           NVARCHAR(50) NULL,
    src_file_name        NVARCHAR(260) NULL,
    load_dts             DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE bronze.crm_sales_details
(
    sls_ord_num          NVARCHAR(50) NULL,
    sls_prd_key          NVARCHAR(50) NULL,
    sls_cust_id          INT NULL,
    sls_order_dt         NVARCHAR(50) NULL,
    sls_ship_dt          NVARCHAR(50) NULL,
    sls_due_dt           NVARCHAR(50) NULL,
    sls_sales            NVARCHAR(50) NULL,
    sls_quantity         NVARCHAR(50) NULL,
    sls_price            NVARCHAR(50) NULL,
    src_file_name        NVARCHAR(260) NULL,
    load_dts             DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE bronze.erp_loc_a101
(
    cid                  NVARCHAR(50) NULL,
    cntry                NVARCHAR(100) NULL,
    src_file_name        NVARCHAR(260) NULL,
    load_dts             DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE bronze.erp_cust_az12
(
    cid                  NVARCHAR(50) NULL,
    bdate                NVARCHAR(50) NULL,
    gen                  NVARCHAR(50) NULL,
    src_file_name        NVARCHAR(260) NULL,
    load_dts             DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE bronze.erp_px_cat_g1v2
(
    id                   NVARCHAR(50) NULL,
    cat                  NVARCHAR(100) NULL,
    subcat               NVARCHAR(100) NULL,
    maintenance          NVARCHAR(100) NULL,
    src_file_name        NVARCHAR(260) NULL,
    load_dts             DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/*=============================================================================
  4) SILVER LAYER (CLEANSED + CONFORMED TABLES)
=============================================================================*/
CREATE TABLE silver.customer_master
(
    customer_id              INT NOT NULL,
    customer_number          NVARCHAR(50) NOT NULL,
    first_name               NVARCHAR(100) NULL,
    last_name                NVARCHAR(100) NULL,
    marital_status           NVARCHAR(50) NULL,
    gender                   NVARCHAR(50) NULL,
    birthdate                DATE NULL,
    country                  NVARCHAR(100) NULL,
    customer_create_date     DATE NULL,
    record_source            NVARCHAR(30) NOT NULL,
    record_hash              VARBINARY(32) NULL,
    dwh_insert_dts           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    dwh_update_dts           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_silver_customer_master PRIMARY KEY (customer_id)
);
GO

CREATE TABLE silver.product_master
(
    product_id               INT NOT NULL,
    product_number           NVARCHAR(50) NOT NULL,
    product_name             NVARCHAR(200) NULL,
    category_id              NVARCHAR(50) NULL,
    category                 NVARCHAR(100) NULL,
    subcategory              NVARCHAR(100) NULL,
    maintenance              NVARCHAR(100) NULL,
    cost_amount              DECIMAL(18,2) NULL,
    product_line             NVARCHAR(50) NULL,
    product_start_date       DATE NULL,
    product_end_date         DATE NULL,
    is_current               BIT NOT NULL DEFAULT 1,
    record_source            NVARCHAR(30) NOT NULL,
    record_hash              VARBINARY(32) NULL,
    dwh_insert_dts           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    dwh_update_dts           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_silver_product_master PRIMARY KEY (product_id, product_start_date)
);
GO

CREATE TABLE silver.sales_order
(
    order_number             NVARCHAR(50) NOT NULL,
    product_number           NVARCHAR(50) NOT NULL,
    customer_id              INT NOT NULL,
    order_date               DATE NULL,
    ship_date                DATE NULL,
    due_date                 DATE NULL,
    sales_amount             DECIMAL(18,2) NULL,
    quantity                 INT NULL,
    unit_price               DECIMAL(18,2) NULL,
    record_source            NVARCHAR(30) NOT NULL,
    dwh_insert_dts           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    dwh_update_dts           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_silver_sales_order PRIMARY KEY (order_number, product_number, customer_id)
);
GO

/*=============================================================================
  5) GOLD LAYER (KIMBALL STAR SCHEMA TABLES)
=============================================================================*/

/*--------------------------------------------------------------------------
  5.1 DATE DIMENSION
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_date
(
    date_key                 INT NOT NULL PRIMARY KEY,        -- YYYYMMDD
    full_date                DATE NOT NULL,
    day_number_of_month      TINYINT NOT NULL,
    day_name                 NVARCHAR(20) NOT NULL,
    day_number_of_week       TINYINT NOT NULL,
    week_number_of_year      TINYINT NOT NULL,
    month_number             TINYINT NOT NULL,
    month_name               NVARCHAR(20) NOT NULL,
    quarter_number           TINYINT NOT NULL,
    year_number              SMALLINT NOT NULL,
    is_weekend               BIT NOT NULL
);
GO

/*--------------------------------------------------------------------------
  5.2 CUSTOMER DIMENSION (SCD TYPE 2)
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_customer
(
    customer_key             INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    customer_id              INT NOT NULL,
    customer_number          NVARCHAR(50) NOT NULL,
    first_name               NVARCHAR(100) NULL,
    last_name                NVARCHAR(100) NULL,
    full_name                NVARCHAR(250) NULL,
    marital_status           NVARCHAR(50) NULL,
    gender                   NVARCHAR(50) NULL,
    birthdate                DATE NULL,
    country                  NVARCHAR(100) NULL,
    customer_create_date     DATE NULL,
    effective_start_date     DATE NOT NULL,
    effective_end_date       DATE NOT NULL,
    is_current               BIT NOT NULL,
    record_hash              VARBINARY(32) NULL,
    source_system            NVARCHAR(30) NOT NULL,
    CONSTRAINT UX_dim_customer UNIQUE (customer_id, effective_start_date)
);
GO

/*--------------------------------------------------------------------------
  5.3 PRODUCT DIMENSION (SCD TYPE 2)
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_product
(
    product_key              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    product_id               INT NOT NULL,
    product_number           NVARCHAR(50) NOT NULL,
    product_name             NVARCHAR(200) NULL,
    category_id              NVARCHAR(50) NULL,
    category                 NVARCHAR(100) NULL,
    subcategory              NVARCHAR(100) NULL,
    maintenance              NVARCHAR(100) NULL,
    cost_amount              DECIMAL(18,2) NULL,
    product_line             NVARCHAR(50) NULL,
    effective_start_date     DATE NOT NULL,
    effective_end_date       DATE NOT NULL,
    is_current               BIT NOT NULL,
    record_hash              VARBINARY(32) NULL,
    source_system            NVARCHAR(30) NOT NULL,
    CONSTRAINT UX_dim_product UNIQUE (product_id, effective_start_date)
);
GO

/*--------------------------------------------------------------------------
  5.4 LOCATION DIMENSION
     Broken out for analytics flexibility even though the sample source is simple.
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_location
(
    location_key             INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    country                  NVARCHAR(100) NOT NULL,
    region_name              NVARCHAR(100) NULL,
    city_name                NVARCHAR(100) NULL,
    is_current               BIT NOT NULL DEFAULT 1,
    effective_start_date     DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    effective_end_date       DATE NOT NULL DEFAULT CONVERT(DATE, '9999-12-31'),
    CONSTRAINT UX_dim_location UNIQUE (country, effective_start_date)
);
GO

/*--------------------------------------------------------------------------
  5.5 SALES FACT TABLE
--------------------------------------------------------------------------*/
CREATE TABLE gold.fact_sales
(
    sales_fact_key           BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    order_number             NVARCHAR(50) NOT NULL,
    order_date_key           INT NULL,
    ship_date_key            INT NULL,
    due_date_key             INT NULL,
    customer_key             INT NOT NULL,
    product_key              INT NOT NULL,
    location_key             INT NULL,
    sales_amount             DECIMAL(18,2) NULL,
    quantity                 INT NULL,
    unit_price               DECIMAL(18,2) NULL,
    extended_cost_amount     DECIMAL(18,2) NULL,
    gross_profit_amount      DECIMAL(18,2) NULL,
    gross_margin_pct         DECIMAL(9,4) NULL,
    source_system            NVARCHAR(30) NOT NULL,
    load_dts                 DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_fact_sales_order_date FOREIGN KEY (order_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_sales_ship_date  FOREIGN KEY (ship_date_key)  REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_sales_due_date   FOREIGN KEY (due_date_key)   REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_sales_customer   FOREIGN KEY (customer_key)   REFERENCES gold.dim_customer(customer_key),
    CONSTRAINT FK_fact_sales_product    FOREIGN KEY (product_key)    REFERENCES gold.dim_product(product_key),
    CONSTRAINT FK_fact_sales_location   FOREIGN KEY (location_key)   REFERENCES gold.dim_location(location_key)
);
GO

CREATE INDEX IX_fact_sales_order_date_key ON gold.fact_sales(order_date_key);
GO
CREATE INDEX IX_fact_sales_customer_key ON gold.fact_sales(customer_key);
GO
CREATE INDEX IX_fact_sales_product_key ON gold.fact_sales(product_key);
GO

/*=============================================================================
  6) UNKNOWN / DEFAULT DIMENSION ROWS
=============================================================================*/
SET IDENTITY_INSERT gold.dim_location ON;
INSERT INTO gold.dim_location
(
    location_key,
    country,
    region_name,
    city_name,
    is_current,
    effective_start_date,
    effective_end_date
)
VALUES
(
    0,
    'Unknown',
    'Unknown',
    'Unknown',
    1,
    '1900-01-01',
    '9999-12-31'
);
SET IDENTITY_INSERT gold.dim_location OFF;
GO

SET IDENTITY_INSERT gold.dim_customer ON;
INSERT INTO gold.dim_customer
(
    customer_key,
    customer_id,
    customer_number,
    first_name,
    last_name,
    full_name,
    marital_status,
    gender,
    birthdate,
    country,
    customer_create_date,
    effective_start_date,
    effective_end_date,
    is_current,
    record_hash,
    source_system
)
VALUES
(
    0,
    -1,
    'UNK',
    'Unknown',
    'Unknown',
    'Unknown',
    'Unknown',
    'Unknown',
    NULL,
    'Unknown',
    NULL,
    '1900-01-01',
    '9999-12-31',
    1,
    NULL,
    'SYSTEM'
);
SET IDENTITY_INSERT gold.dim_customer OFF;
GO

SET IDENTITY_INSERT gold.dim_product ON;
INSERT INTO gold.dim_product
(
    product_key,
    product_id,
    product_number,
    product_name,
    category_id,
    category,
    subcategory,
    maintenance,
    cost_amount,
    product_line,
    effective_start_date,
    effective_end_date,
    is_current,
    record_hash,
    source_system
)
VALUES
(
    0,
    -1,
    'UNK',
    'Unknown',
    'UNK',
    'Unknown',
    'Unknown',
    'Unknown',
    0,
    'Unknown',
    '1900-01-01',
    '9999-12-31',
    1,
    NULL,
    'SYSTEM'
);
SET IDENTITY_INSERT gold.dim_product OFF;
GO

/*=============================================================================
  7) DATE DIMENSION POPULATION PROCEDURE
=============================================================================*/
CREATE OR ALTER PROCEDURE gold.usp_load_dim_date
    @start_date DATE,
    @end_date   DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH d AS
    (
        SELECT @start_date AS dt
        UNION ALL
        SELECT DATEADD(DAY, 1, dt)
        FROM d
        WHERE dt < @end_date
    )
    INSERT INTO gold.dim_date
    (
        date_key,
        full_date,
        day_number_of_month,
        day_name,
        day_number_of_week,
        week_number_of_year,
        month_number,
        month_name,
        quarter_number,
        year_number,
        is_weekend
    )
    SELECT
        CAST(CONVERT(CHAR(8), dt, 112) AS INT) AS date_key,
        dt AS full_date,
        DATEPART(DAY, dt) AS day_number_of_month,
        DATENAME(WEEKDAY, dt) AS day_name,
        DATEPART(WEEKDAY, dt) AS day_number_of_week,
        DATEPART(WEEK, dt) AS week_number_of_year,
        DATEPART(MONTH, dt) AS month_number,
        DATENAME(MONTH, dt) AS month_name,
        DATEPART(QUARTER, dt) AS quarter_number,
        DATEPART(YEAR, dt) AS year_number,
        CASE WHEN DATENAME(WEEKDAY, dt) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END AS is_weekend
    FROM d
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.dim_date x
        WHERE x.full_date = d.dt
    )
    OPTION (MAXRECURSION 32767);
END;
GO

/*=============================================================================
  8) SILVER LOAD EXAMPLES
     These are transformation examples from bronze to silver.
=============================================================================*/
CREATE OR ALTER VIEW silver.vw_customer_master_src
AS
SELECT
    c.cst_id AS customer_id,
    LTRIM(RTRIM(c.cst_key)) AS customer_number,
    NULLIF(LTRIM(RTRIM(c.cst_firstname)), '') AS first_name,
    NULLIF(LTRIM(RTRIM(c.cst_lastname)), '') AS last_name,
    CASE
        WHEN LOWER(LTRIM(RTRIM(c.cst_marital_status))) IN ('m', 'married') THEN 'Married'
        WHEN LOWER(LTRIM(RTRIM(c.cst_marital_status))) IN ('s', 'single') THEN 'Single'
        ELSE 'Unknown'
    END AS marital_status,
    CASE
        WHEN LOWER(LTRIM(RTRIM(c.cst_gndr))) IN ('m', 'male') THEN 'Male'
        WHEN LOWER(LTRIM(RTRIM(c.cst_gndr))) IN ('f', 'female') THEN 'Female'
        WHEN LOWER(LTRIM(RTRIM(c.cst_gndr))) = 'n/a' AND LOWER(LTRIM(RTRIM(e.gen))) IN ('m', 'male') THEN 'Male'
        WHEN LOWER(LTRIM(RTRIM(c.cst_gndr))) = 'n/a' AND LOWER(LTRIM(RTRIM(e.gen))) IN ('f', 'female') THEN 'Female'
        ELSE 'Unknown'
    END AS gender,
    TRY_CAST(e.bdate AS DATE) AS birthdate,
    NULLIF(LTRIM(RTRIM(l.cntry)), '') AS country,
    TRY_CAST(c.cst_create_date AS DATE) AS customer_create_date,
    'CRM_ERP' AS record_source,
    HASHBYTES
    (
        'SHA2_256',
        CONCAT
        (
            ISNULL(CAST(c.cst_id AS NVARCHAR(50)), ''),
            '|', ISNULL(LTRIM(RTRIM(c.cst_key)), ''),
            '|', ISNULL(LTRIM(RTRIM(c.cst_firstname)), ''),
            '|', ISNULL(LTRIM(RTRIM(c.cst_lastname)), ''),
            '|', ISNULL(LTRIM(RTRIM(l.cntry)), ''),
            '|', ISNULL(LTRIM(RTRIM(e.gen)), '')
        )
    ) AS record_hash
FROM bronze.crm_cust_info c
LEFT JOIN bronze.erp_cust_az12 e
    ON LTRIM(RTRIM(c.cst_key)) = LTRIM(RTRIM(e.cid))
LEFT JOIN bronze.erp_loc_a101 l
    ON LTRIM(RTRIM(c.cst_key)) = LTRIM(RTRIM(l.cid));
GO

CREATE OR ALTER VIEW silver.vw_product_master_src
AS
SELECT
    p.prd_id AS product_id,
    LTRIM(RTRIM(p.prd_key)) AS product_number,
    NULLIF(LTRIM(RTRIM(p.prd_nm)), '') AS product_name,
    x.id AS category_id,
    x.cat AS category,
    x.subcat AS subcategory,
    x.maintenance AS maintenance,
    TRY_CAST(p.prd_cost AS DECIMAL(18,2)) AS cost_amount,
    p.prd_line AS product_line,
    TRY_CAST(p.prd_start_dt AS DATE) AS product_start_date,
    TRY_CAST(p.prd_end_dt AS DATE) AS product_end_date,
    CASE WHEN TRY_CAST(p.prd_end_dt AS DATE) IS NULL THEN 1 ELSE 0 END AS is_current,
    'CRM_ERP' AS record_source,
    HASHBYTES
    (
        'SHA2_256',
        CONCAT
        (
            ISNULL(CAST(p.prd_id AS NVARCHAR(50)), ''),
            '|', ISNULL(LTRIM(RTRIM(p.prd_key)), ''),
            '|', ISNULL(LTRIM(RTRIM(p.prd_nm)), ''),
            '|', ISNULL(LTRIM(RTRIM(x.cat)), ''),
            '|', ISNULL(LTRIM(RTRIM(x.subcat)), ''),
            '|', ISNULL(LTRIM(RTRIM(x.maintenance)), '')
        )
    ) AS record_hash
FROM bronze.crm_prd_info p
LEFT JOIN bronze.erp_px_cat_g1v2 x
    ON LEFT(LTRIM(RTRIM(p.prd_key)), 5) = LTRIM(RTRIM(x.id));
GO

CREATE OR ALTER VIEW silver.vw_sales_order_src
AS
SELECT
    LTRIM(RTRIM(s.sls_ord_num)) AS order_number,
    LTRIM(RTRIM(s.sls_prd_key)) AS product_number,
    s.sls_cust_id AS customer_id,
    TRY_CONVERT(DATE, CAST(s.sls_order_dt AS CHAR(8)), 112) AS order_date,
    TRY_CONVERT(DATE, CAST(s.sls_ship_dt AS CHAR(8)), 112) AS ship_date,
    TRY_CONVERT(DATE, CAST(s.sls_due_dt AS CHAR(8)), 112) AS due_date,
    TRY_CAST(s.sls_sales AS DECIMAL(18,2)) AS sales_amount,
    TRY_CAST(s.sls_quantity AS INT) AS quantity,
    TRY_CAST(s.sls_price AS DECIMAL(18,2)) AS unit_price,
    'CRM' AS record_source
FROM bronze.crm_sales_details s;
GO

/*=============================================================================
  9) GOLD LOAD PROCEDURES (KIMBALL)
=============================================================================*/

/*--------------------------------------------------------------------------
  9.1 LOAD DIMENSION CUSTOMER (SCD TYPE 2)
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_dim_customer
AS
BEGIN
    SET NOCOUNT ON;

    /* Close out changed current rows */
    UPDATE tgt
       SET tgt.effective_end_date = DATEADD(DAY, -1, CAST(GETDATE() AS DATE)),
           tgt.is_current = 0
    FROM gold.dim_customer tgt
    INNER JOIN silver.customer_master src
        ON tgt.customer_id = src.customer_id
       AND tgt.is_current = 1
    WHERE ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0);

    /* Insert new or changed rows */
    INSERT INTO gold.dim_customer
    (
        customer_id,
        customer_number,
        first_name,
        last_name,
        full_name,
        marital_status,
        gender,
        birthdate,
        country,
        customer_create_date,
        effective_start_date,
        effective_end_date,
        is_current,
        record_hash,
        source_system
    )
    SELECT
        src.customer_id,
        src.customer_number,
        src.first_name,
        src.last_name,
        CONCAT(ISNULL(src.first_name, ''), CASE WHEN src.first_name IS NOT NULL AND src.last_name IS NOT NULL THEN ' ' ELSE '' END, ISNULL(src.last_name, '')) AS full_name,
        src.marital_status,
        src.gender,
        src.birthdate,
        src.country,
        src.customer_create_date,
        CAST(GETDATE() AS DATE) AS effective_start_date,
        CONVERT(DATE, '9999-12-31') AS effective_end_date,
        1 AS is_current,
        src.record_hash,
        src.record_source
    FROM silver.customer_master src
    LEFT JOIN gold.dim_customer tgt
        ON src.customer_id = tgt.customer_id
       AND tgt.is_current = 1
    WHERE tgt.customer_id IS NULL
       OR ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0);
END;
GO

/*--------------------------------------------------------------------------
  9.2 LOAD DIMENSION PRODUCT (SCD TYPE 2)
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_dim_product
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE tgt
       SET tgt.effective_end_date = DATEADD(DAY, -1, CAST(GETDATE() AS DATE)),
           tgt.is_current = 0
    FROM gold.dim_product tgt
    INNER JOIN silver.product_master src
        ON tgt.product_id = src.product_id
       AND tgt.is_current = 1
    WHERE ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0);

    INSERT INTO gold.dim_product
    (
        product_id,
        product_number,
        product_name,
        category_id,
        category,
        subcategory,
        maintenance,
        cost_amount,
        product_line,
        effective_start_date,
        effective_end_date,
        is_current,
        record_hash,
        source_system
    )
    SELECT
        src.product_id,
        src.product_number,
        src.product_name,
        src.category_id,
        src.category,
        src.subcategory,
        src.maintenance,
        src.cost_amount,
        src.product_line,
        CAST(GETDATE() AS DATE) AS effective_start_date,
        CONVERT(DATE, '9999-12-31') AS effective_end_date,
        1 AS is_current,
        src.record_hash,
        src.record_source
    FROM silver.product_master src
    LEFT JOIN gold.dim_product tgt
        ON src.product_id = tgt.product_id
       AND tgt.is_current = 1
    WHERE tgt.product_id IS NULL
       OR ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0);
END;
GO

/*--------------------------------------------------------------------------
  9.3 LOAD LOCATION DIMENSION
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_dim_location
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO gold.dim_location
    (
        country,
        region_name,
        city_name,
        is_current,
        effective_start_date,
        effective_end_date
    )
    SELECT DISTINCT
        ISNULL(country, 'Unknown') AS country,
        NULL AS region_name,
        NULL AS city_name,
        1 AS is_current,
        CAST(GETDATE() AS DATE) AS effective_start_date,
        CONVERT(DATE, '9999-12-31') AS effective_end_date
    FROM silver.customer_master src
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.dim_location d
        WHERE d.country = ISNULL(src.country, 'Unknown')
          AND d.is_current = 1
    );
END;
GO

/*--------------------------------------------------------------------------
  9.4 LOAD FACT SALES
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_fact_sales
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO gold.fact_sales
    (
        order_number,
        order_date_key,
        ship_date_key,
        due_date_key,
        customer_key,
        product_key,
        location_key,
        sales_amount,
        quantity,
        unit_price,
        extended_cost_amount,
        gross_profit_amount,
        gross_margin_pct,
        source_system
    )
    SELECT
        s.order_number,
        od.date_key AS order_date_key,
        sd.date_key AS ship_date_key,
        dd.date_key AS due_date_key,
        ISNULL(c.customer_key, 0) AS customer_key,
        ISNULL(p.product_key, 0) AS product_key,
        ISNULL(l.location_key, 0) AS location_key,
        s.sales_amount,
        s.quantity,
        s.unit_price,
        CAST(ISNULL(p.cost_amount, 0) * ISNULL(s.quantity, 0) AS DECIMAL(18,2)) AS extended_cost_amount,
        CAST(ISNULL(s.sales_amount, 0) - (ISNULL(p.cost_amount, 0) * ISNULL(s.quantity, 0)) AS DECIMAL(18,2)) AS gross_profit_amount,
        CASE
            WHEN ISNULL(s.sales_amount, 0) = 0 THEN NULL
            ELSE CAST((ISNULL(s.sales_amount, 0) - (ISNULL(p.cost_amount, 0) * ISNULL(s.quantity, 0))) / NULLIF(s.sales_amount, 0) AS DECIMAL(9,4))
        END AS gross_margin_pct,
        s.record_source
    FROM silver.sales_order s
    LEFT JOIN gold.dim_date od
        ON od.full_date = s.order_date
    LEFT JOIN gold.dim_date sd
        ON sd.full_date = s.ship_date
    LEFT JOIN gold.dim_date dd
        ON dd.full_date = s.due_date
    LEFT JOIN gold.dim_customer c
        ON c.customer_id = s.customer_id
       AND c.is_current = 1
    LEFT JOIN gold.dim_product p
        ON p.product_number = s.product_number
       AND p.is_current = 1
    LEFT JOIN gold.dim_location l
        ON l.country = ISNULL(c.country, 'Unknown')
       AND l.is_current = 1
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.fact_sales f
        WHERE f.order_number = s.order_number
          AND f.customer_key = ISNULL(c.customer_key, 0)
          AND f.product_key = ISNULL(p.product_key, 0)
    );
END;
GO

/*=============================================================================
  10) SAMPLE SILVER LOAD STATEMENTS
=============================================================================*/

/* Load silver.customer_master */
MERGE silver.customer_master AS tgt
USING silver.vw_customer_master_src AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED AND ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0)
THEN UPDATE SET
    tgt.customer_number = src.customer_number,
    tgt.first_name = src.first_name,
    tgt.last_name = src.last_name,
    tgt.marital_status = src.marital_status,
    tgt.gender = src.gender,
    tgt.birthdate = src.birthdate,
    tgt.country = src.country,
    tgt.customer_create_date = src.customer_create_date,
    tgt.record_source = src.record_source,
    tgt.record_hash = src.record_hash,
    tgt.dwh_update_dts = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET
THEN INSERT
(
    customer_id,
    customer_number,
    first_name,
    last_name,
    marital_status,
    gender,
    birthdate,
    country,
    customer_create_date,
    record_source,
    record_hash
)
VALUES
(
    src.customer_id,
    src.customer_number,
    src.first_name,
    src.last_name,
    src.marital_status,
    src.gender,
    src.birthdate,
    src.country,
    src.customer_create_date,
    src.record_source,
    src.record_hash
);
GO

/* Load silver.product_master */
MERGE silver.product_master AS tgt
USING silver.vw_product_master_src AS src
ON tgt.product_id = src.product_id
AND tgt.product_start_date = src.product_start_date
WHEN MATCHED AND ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0)
THEN UPDATE SET
    tgt.product_number = src.product_number,
    tgt.product_name = src.product_name,
    tgt.category_id = src.category_id,
    tgt.category = src.category,
    tgt.subcategory = src.subcategory,
    tgt.maintenance = src.maintenance,
    tgt.cost_amount = src.cost_amount,
    tgt.product_line = src.product_line,
    tgt.product_end_date = src.product_end_date,
    tgt.is_current = src.is_current,
    tgt.record_source = src.record_source,
    tgt.record_hash = src.record_hash,
    tgt.dwh_update_dts = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET
THEN INSERT
(
    product_id,
    product_number,
    product_name,
    category_id,
    category,
    subcategory,
    maintenance,
    cost_amount,
    product_line,
    product_start_date,
    product_end_date,
    is_current,
    record_source,
    record_hash
)
VALUES
(
    src.product_id,
    src.product_number,
    src.product_name,
    src.category_id,
    src.category,
    src.subcategory,
    src.maintenance,
    src.cost_amount,
    src.product_line,
    src.product_start_date,
    src.product_end_date,
    src.is_current,
    src.record_source,
    src.record_hash
);
GO

/* Load silver.sales_order */
MERGE silver.sales_order AS tgt
USING silver.vw_sales_order_src AS src
ON tgt.order_number = src.order_number
AND tgt.product_number = src.product_number
AND tgt.customer_id = src.customer_id
WHEN MATCHED
THEN UPDATE SET
    tgt.order_date = src.order_date,
    tgt.ship_date = src.ship_date,
    tgt.due_date = src.due_date,
    tgt.sales_amount = src.sales_amount,
    tgt.quantity = src.quantity,
    tgt.unit_price = src.unit_price,
    tgt.record_source = src.record_source,
    tgt.dwh_update_dts = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET
THEN INSERT
(
    order_number,
    product_number,
    customer_id,
    order_date,
    ship_date,
    due_date,
    sales_amount,
    quantity,
    unit_price,
    record_source
)
VALUES
(
    src.order_number,
    src.product_number,
    src.customer_id,
    src.order_date,
    src.ship_date,
    src.due_date,
    src.sales_amount,
    src.quantity,
    src.unit_price,
    src.record_source
);
GO

/*=============================================================================
  11) SAMPLE EXECUTION ORDER
=============================================================================*/
EXEC gold.usp_load_dim_date @start_date = '2010-01-01', @end_date = '2035-12-31';
GO
EXEC gold.usp_load_dim_customer;
GO
EXEC gold.usp_load_dim_product;
GO
EXEC gold.usp_load_dim_location;
GO
EXEC gold.usp_load_fact_sales;
GO

/*=============================================================================
  12) ANALYTICS VIEW FOR CONSUMERS
=============================================================================*/
CREATE OR ALTER VIEW gold.vw_sales_analytics
AS
SELECT
    f.sales_fact_key,
    f.order_number,
    od.full_date AS order_date,
    sd.full_date AS ship_date,
    dd.full_date AS due_date,
    c.customer_id,
    c.customer_number,
    c.full_name,
    c.gender,
    c.country,
    p.product_id,
    p.product_number,
    p.product_name,
    p.category,
    p.subcategory,
    p.product_line,
    l.country AS location_country,
    f.sales_amount,
    f.quantity,
    f.unit_price,
    f.extended_cost_amount,
    f.gross_profit_amount,
    f.gross_margin_pct
FROM gold.fact_sales f
LEFT JOIN gold.dim_date od ON f.order_date_key = od.date_key
LEFT JOIN gold.dim_date sd ON f.ship_date_key = sd.date_key
LEFT JOIN gold.dim_date dd ON f.due_date_key = dd.date_key
LEFT JOIN gold.dim_customer c ON f.customer_key = c.customer_key
LEFT JOIN gold.dim_product p ON f.product_key = p.product_key
LEFT JOIN gold.dim_location l ON f.location_key = l.location_key;
GO
