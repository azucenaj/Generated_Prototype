
/*
===============================================================================
ADVANCED KIMBALL DATA WAREHOUSE DESIGN
Based on a Medallion-style Sales Domain
Target Platform: SQL Server

PURPOSE
-------
This script shows a more advanced Kimball design than a basic star schema.

It includes:
1. Bronze / Silver / Gold logical layering
2. Standard dimensions and transaction fact
3. SCD Type 2 dimensions
4. Degenerate dimension example
5. Junk dimension
6. Bridge table
7. Factless fact table
8. Accumulating snapshot fact
9. Periodic snapshot fact

WHY THIS IS "ADVANCED"
----------------------
A simple Kimball model usually has:
- a few dimensions
- one main fact table

This advanced version adds specialized structures for real business scenarios:
- process tracking
- many-to-many relationships
- event tracking without measures
- grouped low-cardinality flags
- daily/monthly snapshots

BUSINESS DOMAIN
---------------
The sample domain is sales analytics.

We assume:
- customers place orders
- orders contain products
- products belong to categories
- customers may belong to multiple segments
- orders move through stages (ordered, shipped, delivered)
- products may be active in different periods
===============================================================================
*/

USE master;
GO

/*=============================================================================
  1) CREATE A CLEAN DATABASE FOR THE DEMO
=============================================================================*/
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'AdvancedKimballDW')
BEGIN
    ALTER DATABASE AdvancedKimballDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE AdvancedKimballDW;
END;
GO

CREATE DATABASE AdvancedKimballDW;
GO

USE AdvancedKimballDW;
GO

/*=============================================================================
  2) CREATE SCHEMAS
     bronze = raw source-shaped landing
     silver = cleansed / conformed business layer
     gold   = Kimball dimensional warehouse
=============================================================================*/
CREATE SCHEMA bronze;
GO
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;
GO

/*=============================================================================
  3) BRONZE TABLES
     These are simple raw landing tables.
     In a real project, these normally come from files, ERP, CRM, APIs, etc.
=============================================================================*/
CREATE TABLE bronze.customer_raw
(
    customer_id            INT NULL,
    customer_code          NVARCHAR(50) NULL,
    first_name             NVARCHAR(100) NULL,
    last_name              NVARCHAR(100) NULL,
    gender                 NVARCHAR(50) NULL,
    country                NVARCHAR(100) NULL,
    birth_date             NVARCHAR(50) NULL,
    create_date            NVARCHAR(50) NULL,
    load_dts               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE bronze.product_raw
(
    product_id             INT NULL,
    product_code           NVARCHAR(50) NULL,
    product_name           NVARCHAR(200) NULL,
    category_name          NVARCHAR(100) NULL,
    subcategory_name       NVARCHAR(100) NULL,
    product_line           NVARCHAR(50) NULL,
    cost_amount            NVARCHAR(50) NULL,
    start_date             NVARCHAR(50) NULL,
    end_date               NVARCHAR(50) NULL,
    load_dts               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE bronze.sales_order_raw
(
    order_number           NVARCHAR(50) NULL,
    customer_id            INT NULL,
    product_code           NVARCHAR(50) NULL,
    order_date             NVARCHAR(50) NULL,
    ship_date              NVARCHAR(50) NULL,
    due_date               NVARCHAR(50) NULL,
    delivered_date         NVARCHAR(50) NULL,
    sales_amount           NVARCHAR(50) NULL,
    quantity               NVARCHAR(50) NULL,
    unit_price             NVARCHAR(50) NULL,
    is_promo               NVARCHAR(10) NULL,
    is_online              NVARCHAR(10) NULL,
    is_returned            NVARCHAR(10) NULL,
    payment_status         NVARCHAR(30) NULL,
    load_dts               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE bronze.customer_segment_raw
(
    customer_id            INT NULL,
    segment_name           NVARCHAR(100) NULL,
    segment_weight         DECIMAL(9,4) NULL,
    load_dts               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE bronze.product_listing_raw
(
    product_code           NVARCHAR(50) NULL,
    listing_date           NVARCHAR(50) NULL,
    channel_name           NVARCHAR(100) NULL,
    load_dts               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/*=============================================================================
  4) SILVER TABLES
     These hold cleansed and conformed entities.
=============================================================================*/
CREATE TABLE silver.customer_master
(
    customer_id            INT NOT NULL PRIMARY KEY,
    customer_code          NVARCHAR(50) NOT NULL,
    first_name             NVARCHAR(100) NULL,
    last_name              NVARCHAR(100) NULL,
    full_name              NVARCHAR(250) NULL,
    gender                 NVARCHAR(50) NULL,
    country                NVARCHAR(100) NULL,
    birth_date             DATE NULL,
    create_date            DATE NULL,
    record_hash            VARBINARY(32) NULL,
    dwh_insert_dts         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    dwh_update_dts         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE silver.product_master
(
    product_id             INT NOT NULL,
    product_code           NVARCHAR(50) NOT NULL,
    product_name           NVARCHAR(200) NULL,
    category_name          NVARCHAR(100) NULL,
    subcategory_name       NVARCHAR(100) NULL,
    product_line           NVARCHAR(50) NULL,
    cost_amount            DECIMAL(18,2) NULL,
    start_date             DATE NOT NULL,
    end_date               DATE NULL,
    is_current             BIT NOT NULL DEFAULT 1,
    record_hash            VARBINARY(32) NULL,
    dwh_insert_dts         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    dwh_update_dts         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_silver_product_master PRIMARY KEY (product_id, start_date)
);
GO

CREATE TABLE silver.sales_order
(
    order_number           NVARCHAR(50) NOT NULL,
    customer_id            INT NOT NULL,
    product_code           NVARCHAR(50) NOT NULL,
    order_date             DATE NULL,
    ship_date              DATE NULL,
    due_date               DATE NULL,
    delivered_date         DATE NULL,
    sales_amount           DECIMAL(18,2) NULL,
    quantity               INT NULL,
    unit_price             DECIMAL(18,2) NULL,
    is_promo               BIT NULL,
    is_online              BIT NULL,
    is_returned            BIT NULL,
    payment_status         NVARCHAR(30) NULL,
    dwh_insert_dts         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    dwh_update_dts         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_silver_sales_order PRIMARY KEY (order_number, product_code, customer_id)
);
GO

CREATE TABLE silver.customer_segment_map
(
    customer_id            INT NOT NULL,
    segment_name           NVARCHAR(100) NOT NULL,
    segment_weight         DECIMAL(9,4) NULL,
    CONSTRAINT PK_silver_customer_segment_map PRIMARY KEY (customer_id, segment_name)
);
GO

CREATE TABLE silver.product_listing_event
(
    product_code           NVARCHAR(50) NOT NULL,
    listing_date           DATE NOT NULL,
    channel_name           NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_silver_product_listing_event PRIMARY KEY (product_code, listing_date, channel_name)
);
GO

/*=============================================================================
  5) GOLD DIMENSIONS
=============================================================================*/

/*--------------------------------------------------------------------------
  5.1 DATE DIMENSION
  Standard Kimball date dimension.
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_date
(
    date_key               INT NOT NULL PRIMARY KEY,    -- Example: 20260115
    full_date              DATE NOT NULL,
    day_number_of_month    TINYINT NOT NULL,
    day_name               NVARCHAR(20) NOT NULL,
    day_number_of_week     TINYINT NOT NULL,
    week_number_of_year    TINYINT NOT NULL,
    month_number           TINYINT NOT NULL,
    month_name             NVARCHAR(20) NOT NULL,
    quarter_number         TINYINT NOT NULL,
    year_number            SMALLINT NOT NULL,
    is_weekend             BIT NOT NULL
);
GO

/*--------------------------------------------------------------------------
  5.2 CUSTOMER DIMENSION (SCD TYPE 2)
  Tracks historical changes in customer attributes over time.
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_customer
(
    customer_key           INT IDENTITY(1,1) PRIMARY KEY,
    customer_id            INT NOT NULL,
    customer_code          NVARCHAR(50) NOT NULL,
    first_name             NVARCHAR(100) NULL,
    last_name              NVARCHAR(100) NULL,
    full_name              NVARCHAR(250) NULL,
    gender                 NVARCHAR(50) NULL,
    country                NVARCHAR(100) NULL,
    birth_date             DATE NULL,
    create_date            DATE NULL,
    effective_start_date   DATE NOT NULL,
    effective_end_date     DATE NOT NULL,
    is_current             BIT NOT NULL,
    record_hash            VARBINARY(32) NULL,
    CONSTRAINT UX_dim_customer UNIQUE (customer_id, effective_start_date)
);
GO

/*--------------------------------------------------------------------------
  5.3 PRODUCT DIMENSION (SCD TYPE 2)
  Tracks historical product attribute changes over time.
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_product
(
    product_key            INT IDENTITY(1,1) PRIMARY KEY,
    product_id             INT NOT NULL,
    product_code           NVARCHAR(50) NOT NULL,
    product_name           NVARCHAR(200) NULL,
    category_name          NVARCHAR(100) NULL,
    subcategory_name       NVARCHAR(100) NULL,
    product_line           NVARCHAR(50) NULL,
    cost_amount            DECIMAL(18,2) NULL,
    effective_start_date   DATE NOT NULL,
    effective_end_date     DATE NOT NULL,
    is_current             BIT NOT NULL,
    record_hash            VARBINARY(32) NULL,
    CONSTRAINT UX_dim_product UNIQUE (product_id, effective_start_date)
);
GO

/*--------------------------------------------------------------------------
  5.4 LOCATION DIMENSION
  Basic location dimension for country-level analytics.
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_location
(
    location_key           INT IDENTITY(1,1) PRIMARY KEY,
    country                NVARCHAR(100) NOT NULL,
    effective_start_date   DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    effective_end_date     DATE NOT NULL DEFAULT CONVERT(DATE, '9999-12-31'),
    is_current             BIT NOT NULL DEFAULT 1,
    CONSTRAINT UX_dim_location UNIQUE (country, effective_start_date)
);
GO

/*--------------------------------------------------------------------------
  5.5 JUNK DIMENSION
  Groups several low-cardinality flags into one dimension.

  WHY:
  Instead of storing many tiny Yes/No columns directly in the fact table,
  Kimball often groups them into a junk dimension.
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_order_flags
(
    order_flags_key        INT IDENTITY(1,1) PRIMARY KEY,
    is_promo               BIT NOT NULL,
    is_online              BIT NOT NULL,
    is_returned            BIT NOT NULL,
    payment_status         NVARCHAR(30) NOT NULL,
    CONSTRAINT UX_dim_order_flags UNIQUE (is_promo, is_online, is_returned, payment_status)
);
GO

/*--------------------------------------------------------------------------
  5.6 SEGMENT DIMENSION
  Used together with a bridge table for many-to-many customer segmentation.
--------------------------------------------------------------------------*/
CREATE TABLE gold.dim_segment
(
    segment_key            INT IDENTITY(1,1) PRIMARY KEY,
    segment_name           NVARCHAR(100) NOT NULL UNIQUE
);
GO

/*=============================================================================
  6) GOLD BRIDGE TABLE
=============================================================================*/

/*--------------------------------------------------------------------------
  6.1 CUSTOMER-SEGMENT BRIDGE
  A bridge table models many-to-many relationships.

  WHY:
  One customer can belong to multiple segments at the same time.
  Example:
  - High Value
  - Promo Sensitive
  - Repeat Buyer
--------------------------------------------------------------------------*/
CREATE TABLE gold.bridge_customer_segment
(
    customer_key           INT NOT NULL,
    segment_key            INT NOT NULL,
    segment_weight         DECIMAL(9,4) NULL,
    CONSTRAINT PK_bridge_customer_segment PRIMARY KEY (customer_key, segment_key),
    CONSTRAINT FK_bridge_customer_segment_customer FOREIGN KEY (customer_key) REFERENCES gold.dim_customer(customer_key),
    CONSTRAINT FK_bridge_customer_segment_segment  FOREIGN KEY (segment_key)  REFERENCES gold.dim_segment(segment_key)
);
GO

/*=============================================================================
  7) GOLD FACT TABLES
=============================================================================*/

/*--------------------------------------------------------------------------
  7.1 TRANSACTION FACT TABLE
  This is the main sales transaction fact.

  GRAIN:
  One row per order number + product + customer.

  ADVANCED NOTE:
  order_number is a degenerate dimension:
  - it is a business key
  - stored directly in the fact
  - no separate dimension table is needed
--------------------------------------------------------------------------*/
CREATE TABLE gold.fact_sales
(
    sales_fact_key         BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_number           NVARCHAR(50) NOT NULL,   -- degenerate dimension
    order_date_key         INT NULL,
    ship_date_key          INT NULL,
    due_date_key           INT NULL,
    delivered_date_key     INT NULL,
    customer_key           INT NOT NULL,
    product_key            INT NOT NULL,
    location_key           INT NOT NULL,
    order_flags_key        INT NOT NULL,
    sales_amount           DECIMAL(18,2) NULL,
    quantity               INT NULL,
    unit_price             DECIMAL(18,2) NULL,
    extended_cost_amount   DECIMAL(18,2) NULL,
    gross_profit_amount    DECIMAL(18,2) NULL,
    gross_margin_pct       DECIMAL(9,4) NULL,
    load_dts               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_fact_sales_order_date FOREIGN KEY (order_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_sales_ship_date FOREIGN KEY (ship_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_sales_due_date FOREIGN KEY (due_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_sales_delivered_date FOREIGN KEY (delivered_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_sales_customer FOREIGN KEY (customer_key) REFERENCES gold.dim_customer(customer_key),
    CONSTRAINT FK_fact_sales_product FOREIGN KEY (product_key) REFERENCES gold.dim_product(product_key),
    CONSTRAINT FK_fact_sales_location FOREIGN KEY (location_key) REFERENCES gold.dim_location(location_key),
    CONSTRAINT FK_fact_sales_order_flags FOREIGN KEY (order_flags_key) REFERENCES gold.dim_order_flags(order_flags_key)
);
GO

/*--------------------------------------------------------------------------
  7.2 FACTLESS FACT TABLE
  This table records events but no numeric measures.

  EXAMPLE:
  Product listing / product coverage event.

  WHY:
  Sometimes the important question is simply:
  - Did this event happen?
  - Was the product active in this channel on this date?
--------------------------------------------------------------------------*/
CREATE TABLE gold.fact_product_listing_event
(
    listing_event_key      BIGINT IDENTITY(1,1) PRIMARY KEY,
    listing_date_key       INT NOT NULL,
    product_key            INT NOT NULL,
    channel_name           NVARCHAR(100) NOT NULL,
    event_count            INT NOT NULL DEFAULT 1,
    load_dts               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_fact_product_listing_event_date FOREIGN KEY (listing_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_product_listing_event_product FOREIGN KEY (product_key) REFERENCES gold.dim_product(product_key)
);
GO

/*--------------------------------------------------------------------------
  7.3 ACCUMULATING SNAPSHOT FACT
  Tracks process milestones on a single row as an order moves through stages.

  EXAMPLE:
  order created -> shipped -> delivered

  WHY:
  This is useful for SLA and process duration analytics.
--------------------------------------------------------------------------*/
CREATE TABLE gold.fact_order_pipeline
(
    order_pipeline_key     BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_number           NVARCHAR(50) NOT NULL UNIQUE,
    customer_key           INT NOT NULL,
    product_key            INT NOT NULL,
    order_date_key         INT NULL,
    ship_date_key          INT NULL,
    delivered_date_key     INT NULL,
    current_status         NVARCHAR(50) NULL,
    days_to_ship           INT NULL,
    days_to_deliver        INT NULL,
    load_dts               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_fact_order_pipeline_customer FOREIGN KEY (customer_key) REFERENCES gold.dim_customer(customer_key),
    CONSTRAINT FK_fact_order_pipeline_product FOREIGN KEY (product_key) REFERENCES gold.dim_product(product_key),
    CONSTRAINT FK_fact_order_pipeline_order_date FOREIGN KEY (order_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_order_pipeline_ship_date FOREIGN KEY (ship_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_order_pipeline_delivered_date FOREIGN KEY (delivered_date_key) REFERENCES gold.dim_date(date_key)
);
GO

/*--------------------------------------------------------------------------
  7.4 PERIODIC SNAPSHOT FACT
  Captures daily rolled-up metrics at a fixed interval.

  EXAMPLE:
  Daily sales by product and country.

  WHY:
  This is ideal for trend reporting and performance snapshots.
--------------------------------------------------------------------------*/
CREATE TABLE gold.fact_daily_sales_snapshot
(
    snapshot_date_key      INT NOT NULL,
    product_key            INT NOT NULL,
    location_key           INT NOT NULL,
    daily_order_count      INT NOT NULL,
    daily_quantity         INT NOT NULL,
    daily_sales_amount     DECIMAL(18,2) NOT NULL,
    daily_profit_amount    DECIMAL(18,2) NOT NULL,
    load_dts               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_fact_daily_sales_snapshot PRIMARY KEY (snapshot_date_key, product_key, location_key),
    CONSTRAINT FK_fact_daily_sales_snapshot_date FOREIGN KEY (snapshot_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_fact_daily_sales_snapshot_product FOREIGN KEY (product_key) REFERENCES gold.dim_product(product_key),
    CONSTRAINT FK_fact_daily_sales_snapshot_location FOREIGN KEY (location_key) REFERENCES gold.dim_location(location_key)
);
GO

/*=============================================================================
  8) DEFAULT / UNKNOWN RECORDS
  These are useful so fact rows still load even if a dimension lookup fails.
=============================================================================*/
SET IDENTITY_INSERT gold.dim_customer ON;
INSERT INTO gold.dim_customer
(
    customer_key, customer_id, customer_code, first_name, last_name, full_name,
    gender, country, birth_date, create_date,
    effective_start_date, effective_end_date, is_current, record_hash
)
VALUES
(
    0, -1, 'UNK', 'Unknown', 'Unknown', 'Unknown',
    'Unknown', 'Unknown', NULL, NULL,
    '1900-01-01', '9999-12-31', 1, NULL
);
SET IDENTITY_INSERT gold.dim_customer OFF;
GO

SET IDENTITY_INSERT gold.dim_product ON;
INSERT INTO gold.dim_product
(
    product_key, product_id, product_code, product_name, category_name, subcategory_name,
    product_line, cost_amount, effective_start_date, effective_end_date, is_current, record_hash
)
VALUES
(
    0, -1, 'UNK', 'Unknown', 'Unknown', 'Unknown',
    'Unknown', 0, '1900-01-01', '9999-12-31', 1, NULL
);
SET IDENTITY_INSERT gold.dim_product OFF;
GO

SET IDENTITY_INSERT gold.dim_location ON;
INSERT INTO gold.dim_location
(
    location_key, country, effective_start_date, effective_end_date, is_current
)
VALUES
(
    0, 'Unknown', '1900-01-01', '9999-12-31', 1
);
SET IDENTITY_INSERT gold.dim_location OFF;
GO

SET IDENTITY_INSERT gold.dim_segment ON;
INSERT INTO gold.dim_segment (segment_key, segment_name)
VALUES (0, 'Unknown');
SET IDENTITY_INSERT gold.dim_segment OFF;
GO

SET IDENTITY_INSERT gold.dim_order_flags ON;
INSERT INTO gold.dim_order_flags
(
    order_flags_key, is_promo, is_online, is_returned, payment_status
)
VALUES
(
    0, 0, 0, 0, 'Unknown'
);
SET IDENTITY_INSERT gold.dim_order_flags OFF;
GO

/*=============================================================================
  9) DATE DIMENSION LOAD PROCEDURE
=============================================================================*/
CREATE OR ALTER PROCEDURE gold.usp_load_dim_date
    @start_date DATE,
    @end_date DATE
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
        CAST(CONVERT(CHAR(8), dt, 112) AS INT),
        dt,
        DATEPART(DAY, dt),
        DATENAME(WEEKDAY, dt),
        DATEPART(WEEKDAY, dt),
        DATEPART(WEEK, dt),
        DATEPART(MONTH, dt),
        DATENAME(MONTH, dt),
        DATEPART(QUARTER, dt),
        DATEPART(YEAR, dt),
        CASE WHEN DATENAME(WEEKDAY, dt) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END
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
  10) SIMPLE LOAD VIEWS FROM BRONZE TO SILVER
  These views show how to cleanse raw data before warehouse loading.
=============================================================================*/
CREATE OR ALTER VIEW silver.vw_customer_master_src
AS
SELECT
    customer_id,
    LTRIM(RTRIM(customer_code)) AS customer_code,
    NULLIF(LTRIM(RTRIM(first_name)), '') AS first_name,
    NULLIF(LTRIM(RTRIM(last_name)), '') AS last_name,
    CONCAT(
        ISNULL(NULLIF(LTRIM(RTRIM(first_name)), ''), ''),
        CASE WHEN NULLIF(LTRIM(RTRIM(first_name)), '') IS NOT NULL AND NULLIF(LTRIM(RTRIM(last_name)), '') IS NOT NULL THEN ' ' ELSE '' END,
        ISNULL(NULLIF(LTRIM(RTRIM(last_name)), ''), '')
    ) AS full_name,
    CASE
        WHEN LOWER(LTRIM(RTRIM(gender))) IN ('m', 'male') THEN 'Male'
        WHEN LOWER(LTRIM(RTRIM(gender))) IN ('f', 'female') THEN 'Female'
        ELSE 'Unknown'
    END AS gender,
    ISNULL(NULLIF(LTRIM(RTRIM(country)), ''), 'Unknown') AS country,
    TRY_CAST(birth_date AS DATE) AS birth_date,
    TRY_CAST(create_date AS DATE) AS create_date,
    HASHBYTES
    (
        'SHA2_256',
        CONCAT
        (
            ISNULL(CAST(customer_id AS NVARCHAR(50)), ''),
            '|', ISNULL(LTRIM(RTRIM(customer_code)), ''),
            '|', ISNULL(LTRIM(RTRIM(first_name)), ''),
            '|', ISNULL(LTRIM(RTRIM(last_name)), ''),
            '|', ISNULL(LTRIM(RTRIM(gender)), ''),
            '|', ISNULL(LTRIM(RTRIM(country)), '')
        )
    ) AS record_hash
FROM bronze.customer_raw;
GO

CREATE OR ALTER VIEW silver.vw_product_master_src
AS
SELECT
    product_id,
    LTRIM(RTRIM(product_code)) AS product_code,
    NULLIF(LTRIM(RTRIM(product_name)), '') AS product_name,
    NULLIF(LTRIM(RTRIM(category_name)), '') AS category_name,
    NULLIF(LTRIM(RTRIM(subcategory_name)), '') AS subcategory_name,
    NULLIF(LTRIM(RTRIM(product_line)), '') AS product_line,
    TRY_CAST(cost_amount AS DECIMAL(18,2)) AS cost_amount,
    ISNULL(TRY_CAST(start_date AS DATE), CAST(GETDATE() AS DATE)) AS start_date,
    TRY_CAST(end_date AS DATE) AS end_date,
    CASE WHEN TRY_CAST(end_date AS DATE) IS NULL THEN 1 ELSE 0 END AS is_current,
    HASHBYTES
    (
        'SHA2_256',
        CONCAT
        (
            ISNULL(CAST(product_id AS NVARCHAR(50)), ''),
            '|', ISNULL(LTRIM(RTRIM(product_code)), ''),
            '|', ISNULL(LTRIM(RTRIM(product_name)), ''),
            '|', ISNULL(LTRIM(RTRIM(category_name)), ''),
            '|', ISNULL(LTRIM(RTRIM(subcategory_name)), ''),
            '|', ISNULL(LTRIM(RTRIM(product_line)), '')
        )
    ) AS record_hash
FROM bronze.product_raw;
GO

CREATE OR ALTER VIEW silver.vw_sales_order_src
AS
SELECT
    LTRIM(RTRIM(order_number)) AS order_number,
    customer_id,
    LTRIM(RTRIM(product_code)) AS product_code,
    TRY_CAST(order_date AS DATE) AS order_date,
    TRY_CAST(ship_date AS DATE) AS ship_date,
    TRY_CAST(due_date AS DATE) AS due_date,
    TRY_CAST(delivered_date AS DATE) AS delivered_date,
    TRY_CAST(sales_amount AS DECIMAL(18,2)) AS sales_amount,
    TRY_CAST(quantity AS INT) AS quantity,
    TRY_CAST(unit_price AS DECIMAL(18,2)) AS unit_price,
    CASE WHEN LOWER(LTRIM(RTRIM(is_promo))) IN ('1', 'y', 'yes', 'true') THEN 1 ELSE 0 END AS is_promo,
    CASE WHEN LOWER(LTRIM(RTRIM(is_online))) IN ('1', 'y', 'yes', 'true') THEN 1 ELSE 0 END AS is_online,
    CASE WHEN LOWER(LTRIM(RTRIM(is_returned))) IN ('1', 'y', 'yes', 'true') THEN 1 ELSE 0 END AS is_returned,
    ISNULL(NULLIF(LTRIM(RTRIM(payment_status)), ''), 'Unknown') AS payment_status
FROM bronze.sales_order_raw;
GO

/*=============================================================================
  11) EXAMPLE SILVER MERGE LOADS
=============================================================================*/
MERGE silver.customer_master AS tgt
USING silver.vw_customer_master_src AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED AND ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0)
THEN UPDATE SET
    tgt.customer_code = src.customer_code,
    tgt.first_name = src.first_name,
    tgt.last_name = src.last_name,
    tgt.full_name = src.full_name,
    tgt.gender = src.gender,
    tgt.country = src.country,
    tgt.birth_date = src.birth_date,
    tgt.create_date = src.create_date,
    tgt.record_hash = src.record_hash,
    tgt.dwh_update_dts = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET
THEN INSERT
(
    customer_id, customer_code, first_name, last_name, full_name,
    gender, country, birth_date, create_date, record_hash
)
VALUES
(
    src.customer_id, src.customer_code, src.first_name, src.last_name, src.full_name,
    src.gender, src.country, src.birth_date, src.create_date, src.record_hash
);
GO

MERGE silver.product_master AS tgt
USING silver.vw_product_master_src AS src
ON tgt.product_id = src.product_id
AND tgt.start_date = src.start_date
WHEN MATCHED AND ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0)
THEN UPDATE SET
    tgt.product_code = src.product_code,
    tgt.product_name = src.product_name,
    tgt.category_name = src.category_name,
    tgt.subcategory_name = src.subcategory_name,
    tgt.product_line = src.product_line,
    tgt.cost_amount = src.cost_amount,
    tgt.end_date = src.end_date,
    tgt.is_current = src.is_current,
    tgt.record_hash = src.record_hash,
    tgt.dwh_update_dts = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET
THEN INSERT
(
    product_id, product_code, product_name, category_name, subcategory_name,
    product_line, cost_amount, start_date, end_date, is_current, record_hash
)
VALUES
(
    src.product_id, src.product_code, src.product_name, src.category_name, src.subcategory_name,
    src.product_line, src.cost_amount, src.start_date, src.end_date, src.is_current, src.record_hash
);
GO

MERGE silver.sales_order AS tgt
USING silver.vw_sales_order_src AS src
ON tgt.order_number = src.order_number
AND tgt.product_code = src.product_code
AND tgt.customer_id = src.customer_id
WHEN MATCHED
THEN UPDATE SET
    tgt.order_date = src.order_date,
    tgt.ship_date = src.ship_date,
    tgt.due_date = src.due_date,
    tgt.delivered_date = src.delivered_date,
    tgt.sales_amount = src.sales_amount,
    tgt.quantity = src.quantity,
    tgt.unit_price = src.unit_price,
    tgt.is_promo = src.is_promo,
    tgt.is_online = src.is_online,
    tgt.is_returned = src.is_returned,
    tgt.payment_status = src.payment_status,
    tgt.dwh_update_dts = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET
THEN INSERT
(
    order_number, customer_id, product_code, order_date, ship_date, due_date, delivered_date,
    sales_amount, quantity, unit_price, is_promo, is_online, is_returned, payment_status
)
VALUES
(
    src.order_number, src.customer_id, src.product_code, src.order_date, src.ship_date, src.due_date, src.delivered_date,
    src.sales_amount, src.quantity, src.unit_price, src.is_promo, src.is_online, src.is_returned, src.payment_status
);
GO

/*=============================================================================
  12) GOLD LOAD PROCEDURES
=============================================================================*/

/*--------------------------------------------------------------------------
  12.1 LOAD CUSTOMER DIMENSION (SCD TYPE 2)
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_dim_customer
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE tgt
       SET tgt.effective_end_date = DATEADD(DAY, -1, CAST(GETDATE() AS DATE)),
           tgt.is_current = 0
    FROM gold.dim_customer tgt
    INNER JOIN silver.customer_master src
        ON tgt.customer_id = src.customer_id
       AND tgt.is_current = 1
    WHERE ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0);

    INSERT INTO gold.dim_customer
    (
        customer_id, customer_code, first_name, last_name, full_name,
        gender, country, birth_date, create_date,
        effective_start_date, effective_end_date, is_current, record_hash
    )
    SELECT
        src.customer_id, src.customer_code, src.first_name, src.last_name, src.full_name,
        src.gender, src.country, src.birth_date, src.create_date,
        CAST(GETDATE() AS DATE),
        CONVERT(DATE, '9999-12-31'),
        1,
        src.record_hash
    FROM silver.customer_master src
    LEFT JOIN gold.dim_customer tgt
        ON src.customer_id = tgt.customer_id
       AND tgt.is_current = 1
    WHERE tgt.customer_id IS NULL
       OR ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0);
END;
GO

/*--------------------------------------------------------------------------
  12.2 LOAD PRODUCT DIMENSION (SCD TYPE 2)
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
        product_id, product_code, product_name, category_name, subcategory_name,
        product_line, cost_amount, effective_start_date, effective_end_date, is_current, record_hash
    )
    SELECT
        src.product_id, src.product_code, src.product_name, src.category_name, src.subcategory_name,
        src.product_line, src.cost_amount,
        CAST(GETDATE() AS DATE),
        CONVERT(DATE, '9999-12-31'),
        1,
        src.record_hash
    FROM silver.product_master src
    LEFT JOIN gold.dim_product tgt
        ON src.product_id = tgt.product_id
       AND tgt.is_current = 1
    WHERE tgt.product_id IS NULL
       OR ISNULL(tgt.record_hash, 0x0) <> ISNULL(src.record_hash, 0x0);
END;
GO

/*--------------------------------------------------------------------------
  12.3 LOAD LOCATION DIMENSION
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_dim_location
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO gold.dim_location (country)
    SELECT DISTINCT ISNULL(country, 'Unknown')
    FROM gold.dim_customer c
    WHERE c.is_current = 1
      AND NOT EXISTS
      (
          SELECT 1
          FROM gold.dim_location l
          WHERE l.country = ISNULL(c.country, 'Unknown')
            AND l.is_current = 1
      );
END;
GO

/*--------------------------------------------------------------------------
  12.4 LOAD JUNK DIMENSION
  Each unique combination of flags gets one surrogate key.
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_dim_order_flags
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO gold.dim_order_flags
    (
        is_promo, is_online, is_returned, payment_status
    )
    SELECT DISTINCT
        ISNULL(is_promo, 0),
        ISNULL(is_online, 0),
        ISNULL(is_returned, 0),
        ISNULL(payment_status, 'Unknown')
    FROM silver.sales_order s
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.dim_order_flags f
        WHERE f.is_promo = ISNULL(s.is_promo, 0)
          AND f.is_online = ISNULL(s.is_online, 0)
          AND f.is_returned = ISNULL(s.is_returned, 0)
          AND f.payment_status = ISNULL(s.payment_status, 'Unknown')
    );
END;
GO

/*--------------------------------------------------------------------------
  12.5 LOAD SEGMENT DIMENSION
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_dim_segment
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO gold.dim_segment (segment_name)
    SELECT DISTINCT segment_name
    FROM silver.customer_segment_map s
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.dim_segment d
        WHERE d.segment_name = s.segment_name
    );
END;
GO

/*--------------------------------------------------------------------------
  12.6 LOAD CUSTOMER-SEGMENT BRIDGE
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_bridge_customer_segment
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO gold.bridge_customer_segment
    (
        customer_key,
        segment_key,
        segment_weight
    )
    SELECT
        c.customer_key,
        s.segment_key,
        m.segment_weight
    FROM silver.customer_segment_map m
    INNER JOIN gold.dim_customer c
        ON c.customer_id = m.customer_id
       AND c.is_current = 1
    INNER JOIN gold.dim_segment s
        ON s.segment_name = m.segment_name
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.bridge_customer_segment b
        WHERE b.customer_key = c.customer_key
          AND b.segment_key = s.segment_key
    );
END;
GO

/*--------------------------------------------------------------------------
  12.7 LOAD MAIN TRANSACTION FACT
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
        delivered_date_key,
        customer_key,
        product_key,
        location_key,
        order_flags_key,
        sales_amount,
        quantity,
        unit_price,
        extended_cost_amount,
        gross_profit_amount,
        gross_margin_pct
    )
    SELECT
        s.order_number,
        od.date_key,
        sd.date_key,
        dd.date_key,
        ld.date_key,
        ISNULL(c.customer_key, 0),
        ISNULL(p.product_key, 0),
        ISNULL(l.location_key, 0),
        ISNULL(f.order_flags_key, 0),
        s.sales_amount,
        s.quantity,
        s.unit_price,
        CAST(ISNULL(p.cost_amount, 0) * ISNULL(s.quantity, 0) AS DECIMAL(18,2)),
        CAST(ISNULL(s.sales_amount, 0) - (ISNULL(p.cost_amount, 0) * ISNULL(s.quantity, 0)) AS DECIMAL(18,2)),
        CASE
            WHEN ISNULL(s.sales_amount, 0) = 0 THEN NULL
            ELSE CAST((ISNULL(s.sales_amount, 0) - (ISNULL(p.cost_amount, 0) * ISNULL(s.quantity, 0))) / NULLIF(s.sales_amount, 0) AS DECIMAL(9,4))
        END
    FROM silver.sales_order s
    LEFT JOIN gold.dim_date od ON od.full_date = s.order_date
    LEFT JOIN gold.dim_date sd ON sd.full_date = s.ship_date
    LEFT JOIN gold.dim_date dd ON dd.full_date = s.due_date
    LEFT JOIN gold.dim_date ld ON ld.full_date = s.delivered_date
    LEFT JOIN gold.dim_customer c
        ON c.customer_id = s.customer_id
       AND c.is_current = 1
    LEFT JOIN gold.dim_product p
        ON p.product_code = s.product_code
       AND p.is_current = 1
    LEFT JOIN gold.dim_location l
        ON l.country = ISNULL(c.country, 'Unknown')
       AND l.is_current = 1
    LEFT JOIN gold.dim_order_flags f
        ON f.is_promo = ISNULL(s.is_promo, 0)
       AND f.is_online = ISNULL(s.is_online, 0)
       AND f.is_returned = ISNULL(s.is_returned, 0)
       AND f.payment_status = ISNULL(s.payment_status, 'Unknown')
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.fact_sales x
        WHERE x.order_number = s.order_number
          AND x.customer_key = ISNULL(c.customer_key, 0)
          AND x.product_key = ISNULL(p.product_key, 0)
    );
END;
GO

/*--------------------------------------------------------------------------
  12.8 LOAD FACTLESS FACT TABLE
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_fact_product_listing_event
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO gold.fact_product_listing_event
    (
        listing_date_key,
        product_key,
        channel_name,
        event_count
    )
    SELECT
        d.date_key,
        ISNULL(p.product_key, 0),
        e.channel_name,
        1
    FROM silver.product_listing_event e
    LEFT JOIN gold.dim_date d
        ON d.full_date = e.listing_date
    LEFT JOIN gold.dim_product p
        ON p.product_code = e.product_code
       AND p.is_current = 1
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.fact_product_listing_event x
        WHERE x.listing_date_key = d.date_key
          AND x.product_key = ISNULL(p.product_key, 0)
          AND x.channel_name = e.channel_name
    );
END;
GO

/*--------------------------------------------------------------------------
  12.9 LOAD ACCUMULATING SNAPSHOT FACT
  One row per order pipeline.
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_fact_order_pipeline
AS
BEGIN
    SET NOCOUNT ON;

    MERGE gold.fact_order_pipeline AS tgt
    USING
    (
        SELECT
            s.order_number,
            ISNULL(c.customer_key, 0) AS customer_key,
            ISNULL(p.product_key, 0) AS product_key,
            od.date_key AS order_date_key,
            sd.date_key AS ship_date_key,
            ld.date_key AS delivered_date_key,
            CASE
                WHEN s.delivered_date IS NOT NULL THEN 'Delivered'
                WHEN s.ship_date IS NOT NULL THEN 'Shipped'
                WHEN s.order_date IS NOT NULL THEN 'Ordered'
                ELSE 'Unknown'
            END AS current_status,
            CASE
                WHEN s.order_date IS NOT NULL AND s.ship_date IS NOT NULL THEN DATEDIFF(DAY, s.order_date, s.ship_date)
                ELSE NULL
            END AS days_to_ship,
            CASE
                WHEN s.order_date IS NOT NULL AND s.delivered_date IS NOT NULL THEN DATEDIFF(DAY, s.order_date, s.delivered_date)
                ELSE NULL
            END AS days_to_deliver
        FROM silver.sales_order s
        LEFT JOIN gold.dim_date od ON od.full_date = s.order_date
        LEFT JOIN gold.dim_date sd ON sd.full_date = s.ship_date
        LEFT JOIN gold.dim_date ld ON ld.full_date = s.delivered_date
        LEFT JOIN gold.dim_customer c
            ON c.customer_id = s.customer_id
           AND c.is_current = 1
        LEFT JOIN gold.dim_product p
            ON p.product_code = s.product_code
           AND p.is_current = 1
    ) AS src
    ON tgt.order_number = src.order_number
    WHEN MATCHED THEN
        UPDATE SET
            tgt.customer_key = src.customer_key,
            tgt.product_key = src.product_key,
            tgt.order_date_key = src.order_date_key,
            tgt.ship_date_key = src.ship_date_key,
            tgt.delivered_date_key = src.delivered_date_key,
            tgt.current_status = src.current_status,
            tgt.days_to_ship = src.days_to_ship,
            tgt.days_to_deliver = src.days_to_deliver
    WHEN NOT MATCHED BY TARGET THEN
        INSERT
        (
            order_number, customer_key, product_key,
            order_date_key, ship_date_key, delivered_date_key,
            current_status, days_to_ship, days_to_deliver
        )
        VALUES
        (
            src.order_number, src.customer_key, src.product_key,
            src.order_date_key, src.ship_date_key, src.delivered_date_key,
            src.current_status, src.days_to_ship, src.days_to_deliver
        );
END;
GO

/*--------------------------------------------------------------------------
  12.10 LOAD PERIODIC SNAPSHOT FACT
  Here we aggregate daily sales by product and location.
--------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE gold.usp_load_fact_daily_sales_snapshot
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM gold.fact_daily_sales_snapshot;

    INSERT INTO gold.fact_daily_sales_snapshot
    (
        snapshot_date_key,
        product_key,
        location_key,
        daily_order_count,
        daily_quantity,
        daily_sales_amount,
        daily_profit_amount
    )
    SELECT
        f.order_date_key AS snapshot_date_key,
        f.product_key,
        f.location_key,
        COUNT(DISTINCT f.order_number) AS daily_order_count,
        SUM(ISNULL(f.quantity, 0)) AS daily_quantity,
        SUM(ISNULL(f.sales_amount, 0)) AS daily_sales_amount,
        SUM(ISNULL(f.gross_profit_amount, 0)) AS daily_profit_amount
    FROM gold.fact_sales f
    WHERE f.order_date_key IS NOT NULL
    GROUP BY
        f.order_date_key,
        f.product_key,
        f.location_key;
END;
GO

/*=============================================================================
  13) SAMPLE LOAD ORDER
=============================================================================*/
EXEC gold.usp_load_dim_date @start_date = '2020-01-01', @end_date = '2030-12-31';
GO
EXEC gold.usp_load_dim_customer;
GO
EXEC gold.usp_load_dim_product;
GO
EXEC gold.usp_load_dim_location;
GO
EXEC gold.usp_load_dim_order_flags;
GO
EXEC gold.usp_load_dim_segment;
GO
EXEC gold.usp_load_bridge_customer_segment;
GO
EXEC gold.usp_load_fact_sales;
GO
EXEC gold.usp_load_fact_product_listing_event;
GO
EXEC gold.usp_load_fact_order_pipeline;
GO
EXEC gold.usp_load_fact_daily_sales_snapshot;
GO

/*=============================================================================
  14) SIMPLE REPORTING VIEWS
=============================================================================*/

/*--------------------------------------------------------------------------
  Main transaction reporting view
--------------------------------------------------------------------------*/
CREATE OR ALTER VIEW gold.vw_sales_analytics
AS
SELECT
    f.sales_fact_key,
    f.order_number,
    od.full_date AS order_date,
    sd.full_date AS ship_date,
    dd.full_date AS due_date,
    ld.full_date AS delivered_date,
    c.customer_id,
    c.customer_code,
    c.full_name,
    c.country,
    p.product_id,
    p.product_code,
    p.product_name,
    p.category_name,
    p.subcategory_name,
    p.product_line,
    flg.is_promo,
    flg.is_online,
    flg.is_returned,
    flg.payment_status,
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
LEFT JOIN gold.dim_date ld ON f.delivered_date_key = ld.date_key
LEFT JOIN gold.dim_customer c ON f.customer_key = c.customer_key
LEFT JOIN gold.dim_product p ON f.product_key = p.product_key
LEFT JOIN gold.dim_order_flags flg ON f.order_flags_key = flg.order_flags_key;
GO

/*--------------------------------------------------------------------------
  Pipeline reporting view
--------------------------------------------------------------------------*/
CREATE OR ALTER VIEW gold.vw_order_pipeline
AS
SELECT
    fp.order_number,
    c.full_name,
    p.product_name,
    od.full_date AS order_date,
    sd.full_date AS ship_date,
    ld.full_date AS delivered_date,
    fp.current_status,
    fp.days_to_ship,
    fp.days_to_deliver
FROM gold.fact_order_pipeline fp
LEFT JOIN gold.dim_customer c ON fp.customer_key = c.customer_key
LEFT JOIN gold.dim_product p ON fp.product_key = p.product_key
LEFT JOIN gold.dim_date od ON fp.order_date_key = od.date_key
LEFT JOIN gold.dim_date sd ON fp.ship_date_key = sd.date_key
LEFT JOIN gold.dim_date ld ON fp.delivered_date_key = ld.date_key;
GO
