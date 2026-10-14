-- =============================================================================
-- Cortex AI Gateway + LangChain + MCP: Setup Script
-- =============================================================================
-- Run this script before starting the notebook.
-- Creates: database, retail-athletic tables and synthetic data (Oct 2024 - Sep 2025),
--          two semantic views, churn predictions table, Cortex Agent, MCP server,
--          AI Gateway configuration, eval set, app access and cost demo quota.
-- Takes about 2 minutes on an XS warehouse (data generation).
--
-- Prerequisites:
--   - ACCOUNTADMIN or a role with CREATE DATABASE, CREATE WAREHOUSE
--   - Cross-region inference enabled (for Claude model access)
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS CORTEX_GATEWAY_RETAIL_LAB;
USE DATABASE CORTEX_GATEWAY_RETAIL_LAB;
CREATE SCHEMA IF NOT EXISTS PUBLIC;
USE SCHEMA PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS GATEWAY_RETAIL_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE GATEWAY_RETAIL_WH;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RETAIL TABLES (13 tables: product, store, customer, sales, inventory, forecast, KPI, campaigns, ML features)
-- ─────────────────────────────────────────────────────────────────────────────

-- ---------------------------------------------------------------- dimensions
CREATE OR REPLACE TABLE DIM_PRODUCT (
    PRODUCT_ID          VARCHAR(12)   PRIMARY KEY,
    PRODUCT_NAME        VARCHAR(200),
    PRODUCT_LINE        VARCHAR(50),
    CATEGORY            VARCHAR(80),
    SUBCATEGORY         VARCHAR(80),
    MATERIAL            VARCHAR(100),
    COLOR               VARCHAR(50),
    SIZE                VARCHAR(10),
    SEASON              VARCHAR(30),
    LAUNCH_DATE         DATE,
    LIFECYCLE_STAGE     VARCHAR(30),
    UNIT_COST           NUMBER(10,2),
    MSRP                NUMBER(10,2),
    WHOLESALE_PRICE     NUMBER(10,2),
    IS_SUSTAINABLE      BOOLEAN,
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE DIM_STORE (
    STORE_ID            VARCHAR(12)   PRIMARY KEY,
    STORE_NAME          VARCHAR(100),
    CITY                VARCHAR(60),
    STATE               VARCHAR(40),
    REGION              VARCHAR(30),
    CHANNEL             VARCHAR(40),
    OPEN_DATE           DATE,
    SQUARE_FEET         NUMBER(8),
    IS_ACTIVE           BOOLEAN DEFAULT TRUE
);

CREATE OR REPLACE TABLE DIM_CUSTOMER (
    CUSTOMER_ID         VARCHAR(12)   PRIMARY KEY,
    FIRST_NAME          VARCHAR(60),
    LAST_NAME           VARCHAR(60),
    EMAIL               VARCHAR(200),
    PHONE               VARCHAR(30),
    CITY                VARCHAR(60),
    STATE               VARCHAR(40),
    REGION              VARCHAR(30),
    SEGMENT             VARCHAR(40),
    LIFETIME_VALUE      NUMBER(12,2),
    FIRST_PURCHASE_DATE DATE,
    LAST_PURCHASE_DATE  DATE,
    TOTAL_ORDERS        NUMBER(6),
    PREFERRED_CHANNEL   VARCHAR(40),
    OPT_IN_EMAIL        BOOLEAN,
    OPT_IN_SMS          BOOLEAN,
    CHURN_RISK_SCORE    NUMBER(5,4),
    NPS_SCORE           NUMBER(3),
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE DIM_MARKETING_CAMPAIGN (
    CAMPAIGN_ID         VARCHAR(12)   PRIMARY KEY,
    CAMPAIGN_NAME       VARCHAR(200),
    CAMPAIGN_TYPE       VARCHAR(40),
    CHANNEL             VARCHAR(40),
    START_DATE          DATE,
    END_DATE            DATE,
    BUDGET              NUMBER(12,2),
    TARGET_SEGMENT      VARCHAR(40),
    PRODUCT_LINE        VARCHAR(50),
    STATUS              VARCHAR(20)
);

-- --------------------------------------------------------------------- facts
CREATE OR REPLACE TABLE FACT_DAILY_SALES (
    SALE_ID             VARCHAR(12)   PRIMARY KEY,
    SALE_DATE           DATE,
    PRODUCT_ID          VARCHAR(12),
    STORE_ID            VARCHAR(12),
    CUSTOMER_ID         VARCHAR(12),
    CHANNEL             VARCHAR(40),
    QUANTITY            NUMBER(6),
    UNIT_PRICE          NUMBER(10,2),
    DISCOUNT_PCT        NUMBER(5,2),
    GROSS_REVENUE       NUMBER(12,2),
    NET_REVENUE         NUMBER(12,2),
    COST_OF_GOODS       NUMBER(12,2),
    RETURN_FLAG         BOOLEAN DEFAULT FALSE
);

CREATE OR REPLACE TABLE FACT_INVENTORY_SNAPSHOT (
    SNAPSHOT_DATE       DATE,
    PRODUCT_ID          VARCHAR(12),
    STORE_ID            VARCHAR(12),
    ON_HAND_QTY         NUMBER(8),
    IN_TRANSIT_QTY      NUMBER(8),
    ALLOCATED_QTY       NUMBER(8),
    WEEKS_OF_SUPPLY     NUMBER(5,1),
    REORDER_POINT       NUMBER(8),
    STOCKOUT_FLAG       BOOLEAN DEFAULT FALSE
);

CREATE OR REPLACE TABLE FACT_DEMAND_FORECAST (
    FORECAST_ID         VARCHAR(12)   PRIMARY KEY,
    FORECAST_DATE       DATE,
    PRODUCT_ID          VARCHAR(12),
    STORE_ID            VARCHAR(12),
    SEASON              VARCHAR(30),
    FORECAST_QTY        NUMBER(8),
    ACTUAL_QTY          NUMBER(8),
    FORECAST_REVENUE    NUMBER(12,2),
    ACTUAL_REVENUE      NUMBER(12,2),
    MODEL_VERSION       VARCHAR(20),
    MAPE                NUMBER(6,4),
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE PRODUCT_DEVELOPMENT_PIPELINE (
    PIPELINE_ID         VARCHAR(12)   PRIMARY KEY,
    PRODUCT_NAME        VARCHAR(200),
    PRODUCT_LINE        VARCHAR(50),
    CATEGORY            VARCHAR(80),
    DESIGNER            VARCHAR(100),
    TARGET_SEASON       VARCHAR(30),
    CURRENT_STAGE       VARCHAR(40),
    STAGE_ENTRY_DATE    DATE,
    TARGET_LAUNCH_DATE  DATE,
    ESTIMATED_COST      NUMBER(10,2),
    SUSTAINABILITY_CERT VARCHAR(60),
    MATERIAL_INNOVATION VARCHAR(200),
    RISK_LEVEL          VARCHAR(20),
    NOTES               VARCHAR(500),
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE FACT_CUSTOMER_INTERACTIONS (
    INTERACTION_ID       VARCHAR(12)   PRIMARY KEY,
    CUSTOMER_ID          VARCHAR(12),
    INTERACTION_DATE     TIMESTAMP_NTZ,
    CHANNEL              VARCHAR(40),
    INTERACTION_TYPE     VARCHAR(40),
    PRODUCT_ID           VARCHAR(12),
    PAGE_VIEWS           NUMBER(5),
    SESSION_DURATION_SEC NUMBER(8),
    ADDED_TO_CART        BOOLEAN,
    PURCHASED            BOOLEAN,
    RETURNED             BOOLEAN,
    RATING               NUMBER(2,1),
    REVIEW_TEXT          VARCHAR(1000),
    SENTIMENT_SCORE      NUMBER(5,4),
    DEVICE_TYPE          VARCHAR(20),
    REFERRAL_SOURCE      VARCHAR(60)
);

CREATE OR REPLACE TABLE FACT_CAMPAIGN_PERFORMANCE (
    PERF_ID             VARCHAR(12)   PRIMARY KEY,
    CAMPAIGN_ID         VARCHAR(12),
    PERF_DATE           DATE,
    IMPRESSIONS         NUMBER(10),
    CLICKS              NUMBER(8),
    CONVERSIONS         NUMBER(6),
    REVENUE_ATTRIBUTED  NUMBER(12,2),
    COST                NUMBER(12,2),
    ROAS                NUMBER(8,2)
);

CREATE OR REPLACE TABLE FACT_DAILY_KPI (
    KPI_DATE            DATE,
    CHANNEL             VARCHAR(40),
    REGION              VARCHAR(30),
    GROSS_REVENUE       NUMBER(14,2),
    NET_REVENUE         NUMBER(14,2),
    ORDERS              NUMBER(8),
    UNITS_SOLD          NUMBER(8),
    AVG_ORDER_VALUE     NUMBER(10,2),
    RETURN_RATE         NUMBER(5,4),
    CONVERSION_RATE     NUMBER(5,4),
    NEW_CUSTOMERS       NUMBER(6),
    REPEAT_CUSTOMERS    NUMBER(6),
    INVENTORY_TURNS     NUMBER(5,2),
    GROSS_MARGIN_PCT    NUMBER(5,4),
    COGS                NUMBER(14,2),
    MARKETING_SPEND     NUMBER(12,2),
    CAC                 NUMBER(10,2),
    LTV_TO_CAC_RATIO    NUMBER(6,2)
);

CREATE OR REPLACE TABLE ML_CUSTOMER_FEATURES (
    CUSTOMER_ID               VARCHAR(12)   PRIMARY KEY,
    FEATURE_DATE              DATE,
    DAYS_SINCE_LAST_PURCHASE  NUMBER(6),
    PURCHASE_FREQUENCY        NUMBER(6,2),
    AVG_ORDER_VALUE           NUMBER(10,2),
    TOTAL_SPEND_12M           NUMBER(12,2),
    PRODUCT_DIVERSITY_SCORE   NUMBER(5,4),
    CHANNEL_DIVERSITY_SCORE   NUMBER(5,4),
    RETURN_RATE               NUMBER(5,4),
    EMAIL_ENGAGEMENT_RATE     NUMBER(5,4),
    WEB_VISITS_30D            NUMBER(6),
    CHURN_PROBABILITY         NUMBER(5,4),
    PREDICTED_NEXT_PURCHASE   DATE,
    RECOMMENDED_PRODUCTS      VARCHAR(500),
    CLV_PREDICTED_12M         NUMBER(12,2),
    SEGMENT_PREDICTED         VARCHAR(40)
);

CREATE OR REPLACE TABLE ASSORTMENT_PLAN (
    PLAN_ID             VARCHAR(12)   PRIMARY KEY,
    SEASON              VARCHAR(30),
    STORE_ID            VARCHAR(12),
    CATEGORY            VARCHAR(80),
    PRODUCT_LINE        VARCHAR(50),
    PLANNED_STYLES      NUMBER(4),
    PLANNED_UNITS       NUMBER(8),
    PLANNED_REVENUE     NUMBER(12,2),
    ACTUAL_STYLES       NUMBER(4),
    ACTUAL_UNITS        NUMBER(8),
    ACTUAL_REVENUE      NUMBER(12,2),
    SELL_THROUGH_PCT    NUMBER(5,4),
    MARKDOWN_PCT        NUMBER(5,4),
    PLAN_STATUS         VARCHAR(20),
    LAST_UPDATED        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3b. SYNTHETIC DATA (deterministic: HASH-derived, identical on every run)
-- ─────────────────────────────────────────────────────────────────────────────

-- ============================================================ DIM_PRODUCT (500)
INSERT INTO DIM_PRODUCT (PRODUCT_ID, PRODUCT_NAME, PRODUCT_LINE, CATEGORY, SUBCATEGORY, MATERIAL,
    COLOR, SIZE, SEASON, LAUNCH_DATE, LIFECYCLE_STAGE, UNIT_COST, MSRP, WHOLESALE_PRICE, IS_SUSTAINABLE)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 500))
), p AS (
    SELECT n,
        'P' || LPAD(n, 5, '0') AS product_id,
        GET(ARRAY_CONSTRUCT('Performance','Everyday','Sunday','Banks','Ponto','Clementine',
                            'Riviera','Halo','DreamKnit','BlueLine'), UNIFORM(0, 9, HASH(n, 'line')))::STRING AS line,
        IFF(UNIFORM(0, 99, HASH(n, 'gender')) < 50, 'Men''s', 'Women''s') AS gender,
        UNIFORM(0, 99, HASH(n, 'type')) AS type_roll,
        UNIFORM(0, 99, HASH(n, 'stage')) AS stage_roll,
        UNIFORM(12::FLOAT, 55::FLOAT, HASH(n, 'cost')) AS cost,
        UNIFORM(2.8::FLOAT, 4.2::FLOAT, HASH(n, 'markup')) AS markup,
        GET(ARRAY_CONSTRUCT('Azure Blue','Cloud Grey','Night Black','Pacific Green','Desert Sand','Coastline Navy',
                            'Dusk Rose','Stone','Linen White','Redwood','Sage','Carbon'), UNIFORM(0, 11, HASH(n, 'color')))::STRING AS color
    FROM base
), p2 AS (
    SELECT *,
        CASE WHEN type_roll < 35 THEN 'Tops'
             WHEN type_roll < 70 THEN 'Bottoms'
             WHEN type_roll < 82 THEN 'Outerwear'
             WHEN type_roll < 92 OR gender = 'Men''s' THEN 'Accessories'
             ELSE 'Dresses & Jumpsuits' END AS ptype,
        CASE WHEN stage_roll < 55 THEN 'In Market'
             WHEN stage_roll < 70 THEN 'Markdown'
             WHEN stage_roll < 78 THEN 'Retired'
             WHEN stage_roll < 86 THEN 'Production'
             WHEN stage_roll < 91 THEN 'Pre-Production'
             WHEN stage_roll < 94 THEN 'Tech Pack Review'
             WHEN stage_roll < 97 THEN 'Sampling'
             WHEN stage_roll < 99 THEN 'Design'
             ELSE 'Concept' END AS stage
    FROM p
), p3 AS (
    SELECT *,
        CASE ptype
            WHEN 'Tops'        THEN GET(ARRAY_CONSTRUCT('Tees','Long Sleeves','Tanks','Hoodies','Polos'), UNIFORM(0, 4, HASH(n, 'sub')))::STRING
            WHEN 'Bottoms'     THEN GET(ARRAY_CONSTRUCT('Joggers','Shorts','Leggings','Pants'), UNIFORM(0, 3, HASH(n, 'sub')))::STRING
            WHEN 'Outerwear'   THEN GET(ARRAY_CONSTRUCT('Jackets','Vests','Pullovers'), UNIFORM(0, 2, HASH(n, 'sub')))::STRING
            WHEN 'Accessories' THEN GET(ARRAY_CONSTRUCT('Hats','Socks','Bags'), UNIFORM(0, 2, HASH(n, 'sub')))::STRING
            ELSE                    GET(ARRAY_CONSTRUCT('Dresses','Jumpsuits'), UNIFORM(0, 1, HASH(n, 'sub')))::STRING
        END AS subcat,
        -- pre-market products launch in the future; everything else already launched
        IFF(stage IN ('Production','Pre-Production','Tech Pack Review','Sampling','Design','Concept'),
            DATEADD('day', UNIFORM(10, 180, HASH(n, 'launch')), '2025-09-30'::DATE),
            DATEADD('day', UNIFORM(0, 790, HASH(n, 'launch')), '2023-06-01'::DATE)) AS launch_date
    FROM p2
)
SELECT
    product_id,
    line || ' ' || subcat || ' - ' || color,
    line,
    gender || ' ' || ptype,
    subcat,
    GET(ARRAY_CONSTRUCT('Recycled Polyester','Organic Cotton','Tencel Lyocell','Nylon','Merino Wool Blend',
                        'Repreve Fiber','Bamboo Blend','Linen Blend'), UNIFORM(0, 7, HASH(n, 'material')))::STRING,
    color,
    GET(ARRAY_CONSTRUCT('XS','S','M','L','XL','XXL'), UNIFORM(0, 5, HASH(n, 'size')))::STRING,
    CASE WHEN MONTH(launch_date) <= 4 THEN 'Spring' WHEN MONTH(launch_date) <= 8 THEN 'Summer'
         WHEN MONTH(launch_date) <= 10 THEN 'Fall' ELSE 'Holiday' END || ' ' || YEAR(launch_date),
    launch_date,
    stage,
    ROUND(cost, 2),
    ROUND(cost * markup, 0) - 0.01,                 -- e.g. 88.00 -> 87.99
    ROUND((ROUND(cost * markup, 0) - 0.01) * 0.5, 2),
    UNIFORM(0, 99, HASH(n, 'sustainable')) < 70
FROM p3;

-- ============================================================== DIM_STORE (25)
-- 20 retail doors, 3 wholesale partners, 2 e-commerce "stores" (DTC fulfilment)
INSERT INTO DIM_STORE (STORE_ID, STORE_NAME, CITY, STATE, REGION, CHANNEL, OPEN_DATE, SQUARE_FEET, IS_ACTIVE)
SELECT 'S' || LPAD(column1, 5, '0'), column2, column3, column4, column5, column6,
       column7::DATE, column8, TRUE
FROM VALUES
    ( 1, 'Store - Carlsbad',             'Carlsbad',        'CA', 'West',          'Retail Store',      '2019-03-15', 3200),
    ( 2, 'Store - Encinitas',            'Encinitas',       'CA', 'West',          'Retail Store',      '2019-09-01', 2400),
    ( 3, 'Store - Manhattan Beach',      'Manhattan Beach', 'CA', 'West',          'Retail Store',      '2020-05-20', 2800),
    ( 4, 'Store - Santa Monica',         'Santa Monica',    'CA', 'West',          'Retail Store',      '2020-11-10', 3500),
    ( 5, 'Store - San Francisco',        'San Francisco',   'CA', 'West',          'Retail Store',      '2021-04-02', 4100),
    ( 6, 'Store - Seattle',              'Seattle',         'WA', 'West',          'Retail Store',      '2021-08-14', 3300),
    ( 7, 'Store - Portland',             'Portland',        'OR', 'West',          'Retail Store',      '2022-02-25', 2700),
    ( 8, 'Store - Denver',               'Denver',          'CO', 'West',          'Retail Store',      '2022-06-11', 3000),
    ( 9, 'Store - Scottsdale',           'Scottsdale',      'AZ', 'West',          'Retail Store',      '2022-10-07', 2600),
    (10, 'Store - Austin',               'Austin',          'TX', 'South',         'Retail Store',      '2021-12-03', 3400),
    (11, 'Store - Dallas',               'Dallas',          'TX', 'South',         'Retail Store',      '2023-03-18', 3100),
    (12, 'Store - Miami',                'Miami',           'FL', 'South',         'Retail Store',      '2022-11-19', 2900),
    (13, 'Store - Atlanta',              'Atlanta',         'GA', 'South',         'Retail Store',      '2023-05-06', 2800),
    (14, 'Store - Nashville',            'Nashville',       'TN', 'South',         'Retail Store',      '2023-09-09', 2500),
    (15, 'Store - New York SoHo',        'New York',        'NY', 'East',          'Retail Store',      '2021-06-26', 5200),
    (16, 'Store - Boston',               'Boston',          'MA', 'East',          'Retail Store',      '2022-08-20', 3000),
    (17, 'Store - Philadelphia',         'Philadelphia',    'PA', 'East',          'Retail Store',      '2024-02-10', 2700),
    (18, 'Store - Chicago',              'Chicago',         'IL', 'Midwest',       'Retail Store',      '2022-04-30', 3600),
    (19, 'Store - Minneapolis',          'Minneapolis',     'MN', 'Midwest',       'Retail Store',      '2024-04-13', 2400),
    (20, 'Store - Honolulu',             'Honolulu',        'HI', 'West',          'Retail Store',      '2023-12-01', 2200),
    (21, 'Wholesale - Outdoor Partner',  'Denver',          'CO', 'West',          'Wholesale',         '2020-01-15', 0),
    (22, 'Wholesale - Department Store', 'New York',        'NY', 'East',          'Wholesale',         '2020-07-01', 0),
    (23, 'Wholesale - Specialty Run',    'Chicago',         'IL', 'Midwest',       'Wholesale',         '2021-03-01', 0),
    (24, 'E-Commerce - US',              'Carlsbad',        'CA', 'West',          'DTC Website',       '2015-06-01', 0),
    (25, 'E-Commerce - International',   'Carlsbad',        'CA', 'International', 'International DTC', '2019-01-01', 0);

-- ======================================= Customers: shared base (temp table)
-- A latent "engagement" score drives behaviour; churn risk is a logistic
-- function of that behaviour plus noise, so the ML model has real signal.
CREATE OR REPLACE TEMPORARY TABLE _CUSTOMER_BASE AS
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 5000))
), lat AS (
    SELECT n,
        'C' || LPAD(n, 6, '0') AS customer_id,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'eng')) AS e,
        IFF(UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'intl')) < 0.08,
            20 + UNIFORM(0, 3, HASH(n, 'city')), UNIFORM(0, 19, HASH(n, 'city'))) AS city_idx
    FROM base
), feat AS (
    SELECT lat.*,
        GREATEST(0, LEAST(365, ROUND(120 - 70 * e + 60 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'dsl')))))  AS days_since,
        GREATEST(0.1, LEAST(5, 1.5 + 0.7 * e + 0.5 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'freq'))))     AS freq,   -- purchases / quarter
        UNIFORM(60::FLOAT, 220::FLOAT, HASH(n, 'aov'))                                                  AS aov,
        GREATEST(0, LEAST(0.9, 0.25 + 0.12 * e + 0.08 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'email')))) AS email_eng,
        GREATEST(0, ROUND(12 + 7 * e + 5 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'web'))))                 AS web_visits,
        GREATEST(0, LEAST(0.4, 0.08 - 0.03 * e + 0.04 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'ret'))))   AS return_rate,
        GREATEST(0.05, LEAST(1, 0.5 + 0.15 * e + 0.15 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'pdiv'))))  AS prod_div,
        GREATEST(0.05, LEAST(1, 0.45 + 0.12 * e + 0.18 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'cdiv')))) AS chan_div,
        GREATEST(0, LEAST(10, ROUND(7 + 1.5 * e + 1.5 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'nps')))))   AS nps,
        UNIFORM(30, 2000, HASH(n, 'tenure'))                                                            AS tenure_raw
    FROM lat
), risk AS (
    SELECT feat.*,
        GREATEST(tenure_raw, days_since + 30) AS tenure_days,
        1 / (1 + EXP(-(-1.1
            + 0.012 * (days_since - 120)
            - 0.6   * (freq - 1.5)
            - 4.0   * (email_eng - 0.25)
            - 0.05  * (web_visits - 12)
            + 6.0   * (return_rate - 0.08)
            - 0.15  * (nps - 7)
            + 0.6   * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'noise'))))) AS churn_risk
    FROM feat
), derived AS (
    SELECT risk.*,
        GREATEST(1, LEAST(60, ROUND(freq * 4 * tenure_days / 365))) AS total_orders,
        ROUND(aov * freq * 4 * GREATEST(0.1, 1 - days_since / 365), 2) AS spend_12m
    FROM risk
)
SELECT derived.*,
    ROUND(aov * total_orders, 2) AS lifetime_value,
    CASE WHEN total_orders <= 2 AND tenure_days < 150                 THEN 'New Customer'
         WHEN days_since > 270                                         THEN 'Lapsed'
         WHEN days_since > 180                                         THEN 'Win-Back Target'
         WHEN aov * total_orders >= 2500 AND churn_risk >= 0.5         THEN 'High-Value At-Risk'
         WHEN total_orders >= 12 AND churn_risk < 0.35                 THEN 'Loyal VIP'
         WHEN web_visits >= 15 AND total_orders <= 3                   THEN 'Browser'
         ELSE 'Active Regular' END AS segment
FROM derived;

-- ======================================================= ML_CUSTOMER_FEATURES
INSERT INTO ML_CUSTOMER_FEATURES (CUSTOMER_ID, FEATURE_DATE, DAYS_SINCE_LAST_PURCHASE, PURCHASE_FREQUENCY,
    AVG_ORDER_VALUE, TOTAL_SPEND_12M, PRODUCT_DIVERSITY_SCORE, CHANNEL_DIVERSITY_SCORE, RETURN_RATE,
    EMAIL_ENGAGEMENT_RATE, WEB_VISITS_30D, CHURN_PROBABILITY, PREDICTED_NEXT_PURCHASE,
    RECOMMENDED_PRODUCTS, CLV_PREDICTED_12M, SEGMENT_PREDICTED)
SELECT
    customer_id,
    '2025-09-30'::DATE,
    days_since,
    ROUND(freq, 2),
    ROUND(aov, 2),
    spend_12m,
    ROUND(prod_div, 4),
    ROUND(chan_div, 4),
    ROUND(return_rate, 4),
    ROUND(email_eng, 4),
    web_visits,
    -- a legacy rule-based score: correlated with true risk but noisy
    ROUND(GREATEST(0.01, LEAST(0.99, churn_risk + 0.15 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'legacy')))), 4),
    DATEADD('day', LEAST(365, ROUND(90 / freq * (1 + churn_risk))), '2025-09-30'::DATE),
    GET(ARRAY_CONSTRUCT(
        'Performance Joggers;Everyday Tees;DreamKnit Hoodies',
        'Banks Shorts;Ponto Pants;Sunday Pullovers',
        'Halo Leggings;Clementine Dresses;Riviera Tanks',
        'DreamKnit Joggers;Performance Shorts;BlueLine Jackets',
        'Everyday Long Sleeves;Sunday Joggers;Ponto Hoodies',
        'Riviera Polos;Halo Tanks;Banks Hats'), UNIFORM(0, 5, HASH(n, 'reco')))::STRING,
    ROUND(spend_12m * (1 - churn_risk) * 1.15, 2),
    IFF(UNIFORM(0, 99, HASH(n, 'pseg')) < 90, segment, 'Active Regular')
FROM _CUSTOMER_BASE;

-- ================================================================ DIM_CUSTOMER
INSERT INTO DIM_CUSTOMER (CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, CITY, STATE, REGION, SEGMENT,
    LIFETIME_VALUE, FIRST_PURCHASE_DATE, LAST_PURCHASE_DATE, TOTAL_ORDERS, PREFERRED_CHANNEL,
    OPT_IN_EMAIL, OPT_IN_SMS, CHURN_RISK_SCORE, NPS_SCORE)
WITH named AS (
    SELECT b.*,
        GET(ARRAY_CONSTRUCT('James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda','David','Elizabeth',
            'William','Barbara','Richard','Susan','Joseph','Jessica','Thomas','Sarah','Chris','Karen','Daniel','Lisa',
            'Matthew','Nancy','Anthony','Maya','Mark','Margaret','Andrew','Sandra','Joshua','Ashley','Steven','Kim',
            'Ryan','Emily','Brandon','Priya','Brian','Michelle'), UNIFORM(0, 39, HASH(n, 'fn')))::STRING AS first_name,
        GET(ARRAY_CONSTRUCT('Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez',
            'Martinez','Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin',
            'Lee','Perez','Thompson','White','Harris','Sanchez','Clark','Ramirez','Lewis','Nguyen'),
            UNIFORM(0, 29, HASH(n, 'ln')))::STRING AS last_name,
        GET(ARRAY_CONSTRUCT('San Diego','Los Angeles','San Francisco','Seattle','Portland','Denver','Phoenix',
            'Salt Lake City','Austin','Dallas','Houston','Miami','Atlanta','Nashville','Charlotte','New York','Boston',
            'Philadelphia','Chicago','Minneapolis','Toronto','Vancouver','London','Sydney'), city_idx)::STRING AS city,
        GET(ARRAY_CONSTRUCT('CA','CA','CA','WA','OR','CO','AZ','UT','TX','TX','TX','FL','GA','TN','NC','NY','MA',
            'PA','IL','MN','ON','BC','ENG','NSW'), city_idx)::STRING AS state,
        GET(ARRAY_CONSTRUCT('West','West','West','West','West','West','West','West','South','South','South',
            'South','South','South','East','East','East','East','Midwest','Midwest','International','International',
            'International','International'), city_idx)::STRING AS region
    FROM _CUSTOMER_BASE b
)
SELECT
    customer_id,
    first_name,
    last_name,
    LOWER(first_name) || '.' || LOWER(last_name) || n || '@' ||
        GET(ARRAY_CONSTRUCT('gmail.com','yahoo.com','outlook.com','icloud.com','hotmail.com'), UNIFORM(0, 4, HASH(n, 'dom')))::STRING,
    '+1-' || UNIFORM(201, 989, HASH(n, 'area')) || '-555-' || LPAD(UNIFORM(0, 9999, HASH(n, 'phone')), 4, '0'),
    city,
    state,
    region,
    segment,
    lifetime_value,
    DATEADD('day', -tenure_days, '2025-09-30'::DATE),
    DATEADD('day', -days_since, '2025-09-30'::DATE),
    total_orders,
    CASE WHEN region = 'International' THEN 'International DTC'
         WHEN UNIFORM(0, 99, HASH(n, 'pchan')) < 55 THEN 'DTC Website'
         WHEN UNIFORM(0, 99, HASH(n, 'pchan')) < 90 THEN 'Retail Store'
         ELSE 'Wholesale' END,
    UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'optemail')) < 0.55 + 0.4 * email_eng,
    UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'optsms')) < 0.45,
    ROUND(churn_risk, 4),
    nps
FROM named;

-- ===================================================== DIM_MARKETING_CAMPAIGN (40)
INSERT INTO DIM_MARKETING_CAMPAIGN (CAMPAIGN_ID, CAMPAIGN_NAME, CAMPAIGN_TYPE, CHANNEL, START_DATE, END_DATE,
    BUDGET, TARGET_SEGMENT, PRODUCT_LINE, STATUS)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 40))
), c AS (
    SELECT n,
        'CMP' || LPAD(n, 4, '0') AS campaign_id,
        GET(ARRAY_CONSTRUCT('Email Blast','Social Ads','Influencer','Retargeting','Loyalty Program',
                            'Seasonal Sale','New Launch','Brand Awareness'), MOD(n - 1, 8))::STRING AS ctype,
        GET(ARRAY_CONSTRUCT('Performance','Everyday','Sunday','Banks','Ponto','DreamKnit'),
            UNIFORM(0, 5, HASH(n, 'line')))::STRING AS line,
        DATEADD('day', UNIFORM(0, 320, HASH(n, 'start')), '2024-10-01'::DATE) AS start_date,
        UNIFORM(14, 45, HASH(n, 'len')) AS len_days,
        ROUND(UNIFORM(15000, 150000, HASH(n, 'budget')), -3) AS budget
    FROM base
)
SELECT
    campaign_id,
    ctype || ' - ' || line || ' ' || TO_CHAR(start_date, 'Mon YYYY'),
    ctype,
    IFF(ctype IN ('Seasonal Sale', 'Loyalty Program'), 'Retail Store', 'DTC Website'),
    start_date,
    LEAST(DATEADD('day', len_days, start_date), '2025-09-30'::DATE),
    budget,
    CASE ctype WHEN 'Retargeting'     THEN 'Browser'
               WHEN 'Loyalty Program' THEN 'Loyal VIP'
               WHEN 'Email Blast'     THEN 'Win-Back Target'
               WHEN 'Seasonal Sale'   THEN 'Lapsed'
               WHEN 'New Launch'      THEN 'Active Regular'
               ELSE 'New Customer' END,
    line,
    IFF(DATEADD('day', len_days, start_date) < '2025-09-30'::DATE, 'Completed', 'Active')
FROM c;

-- ================================================== FACT_CAMPAIGN_PERFORMANCE
-- Funnel is internally consistent: cost -> impressions (CPM) -> clicks (CTR)
-- -> conversions (CVR) -> revenue (AOV) -> ROAS. CVR/CPM vary by campaign type.
INSERT INTO FACT_CAMPAIGN_PERFORMANCE (PERF_ID, CAMPAIGN_ID, PERF_DATE, IMPRESSIONS, CLICKS, CONVERSIONS,
    REVENUE_ATTRIBUTED, COST, ROAS)
WITH days AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS k FROM TABLE(GENERATOR(ROWCOUNT => 60))
), p AS (
    SELECT c.CAMPAIGN_ID AS id, c.CAMPAIGN_TYPE AS t, c.BUDGET AS budget,
           DATEDIFF('day', c.START_DATE, c.END_DATE) + 1 AS ndays,
           DATEADD('day', d.k, c.START_DATE) AS pdate
    FROM DIM_MARKETING_CAMPAIGN c
    JOIN days d ON d.k <= DATEDIFF('day', c.START_DATE, c.END_DATE)
), m AS (
    SELECT p.*,
        ROUND(budget / ndays * UNIFORM(0.7::FLOAT, 1.3::FLOAT, HASH(id, pdate, 'cost')), 2) AS cost,
        CASE t WHEN 'Email Blast' THEN 10 WHEN 'Loyalty Program' THEN 10 WHEN 'Retargeting' THEN 9
               WHEN 'Brand Awareness' THEN 7 ELSE 12 END AS cpm,
        UNIFORM(0.008::FLOAT, 0.03::FLOAT, HASH(id, pdate, 'ctr')) AS ctr,
        CASE t WHEN 'Retargeting' THEN 0.055 WHEN 'Loyalty Program' THEN 0.05 WHEN 'Email Blast' THEN 0.045
               WHEN 'Seasonal Sale' THEN 0.04 WHEN 'New Launch' THEN 0.03 WHEN 'Influencer' THEN 0.025
               WHEN 'Social Ads' THEN 0.02 ELSE 0.012 END
            * UNIFORM(0.75::FLOAT, 1.25::FLOAT, HASH(id, pdate, 'cvr')) AS cvr,
        UNIFORM(95::FLOAT, 140::FLOAT, HASH(id, pdate, 'aov')) AS aov
    FROM p
), f AS (
    SELECT m.*, ROUND(cost / cpm * 1000) AS impressions FROM m
), f2 AS (
    SELECT f.*, ROUND(impressions * ctr) AS clicks FROM f
), f3 AS (
    SELECT f2.*, ROUND(clicks * cvr) AS conversions FROM f2
)
SELECT
    'PF' || LPAD(ROW_NUMBER() OVER (ORDER BY id, pdate), 7, '0'),
    id, pdate, impressions, clicks, conversions,
    ROUND(conversions * aov, 2),
    cost,
    ROUND(DIV0(conversions * aov, cost), 2)
FROM f3;

-- =========================================================== FACT_DAILY_SALES
-- ~50K transactions. Daily volume has weekend lift, a holiday peak (Black
-- Friday week), a summer bump, a Jan/Feb dip and ~25% YoY growth. Customers
-- only buy between their first and last purchase dates, so lapsed customers
-- stop buying. Popular products are skewed (power-law), wholesale uses
-- wholesale price, markdown items and the holiday sale carry deeper discounts.
INSERT INTO FACT_DAILY_SALES (SALE_ID, SALE_DATE, PRODUCT_ID, STORE_ID, CUSTOMER_ID, CHANNEL, QUANTITY,
    UNIT_PRICE, DISCOUNT_PCT, GROSS_REVENUE, NET_REVENUE, COST_OF_GOODS, RETURN_FLAG)
WITH days AS (
    SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2024-10-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 365))
), slots AS (
    SELECT d, ROW_NUMBER() OVER (ORDER BY d, s.seq) AS k
    FROM days CROSS JOIN (SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 650))) s
), demand AS (
    SELECT d, k,
        155
        * IFF(DAYOFWEEKISO(d) >= 6, 1.35, 1.0)
        * CASE WHEN d BETWEEN '2024-11-25' AND '2024-12-02' THEN 2.4
               WHEN MONTH(d) IN (11, 12) THEN 1.6
               WHEN MONTH(d) IN (5, 6, 7) THEN 1.15
               WHEN MONTH(d) IN (1, 2)    THEN 0.8
               ELSE 1.0 END
        * (1 + 0.25 * DATEDIFF('day', '2024-10-01', d) / 365) AS expected
    FROM slots
), kept AS (
    SELECT d, k FROM demand
    WHERE UNIFORM(0::FLOAT, 1::FLOAT, HASH(k, 'keep')) < expected / 650
), sellable AS (
    SELECT PRODUCT_ID, MSRP, WHOLESALE_PRICE, UNIT_COST, LIFECYCLE_STAGE,
           ROW_NUMBER() OVER (ORDER BY PRODUCT_ID) AS rn
    FROM DIM_PRODUCT WHERE LIFECYCLE_STAGE IN ('In Market', 'Markdown', 'Retired')
), cnt AS (
    SELECT COUNT(*) AS c FROM sellable
), picks AS (
    SELECT kept.d, kept.k,
        FLOOR(POW(UNIFORM(0::FLOAT, 1::FLOAT, HASH(k, 'prod')), 1.6) * cnt.c) + 1 AS prod_rn,
        'C' || LPAD(UNIFORM(1, 5000, HASH(k, 'cust')), 6, '0') AS customer_id
    FROM kept CROSS JOIN cnt
), tx AS (
    SELECT pk.d, pk.k, pk.customer_id, s.PRODUCT_ID, s.MSRP, s.WHOLESALE_PRICE, s.UNIT_COST, s.LIFECYCLE_STAGE,
        CASE WHEN c.REGION = 'International' THEN 'International DTC'
             WHEN UNIFORM(0, 99, HASH(pk.k, 'chan')) < 50 THEN 'DTC Website'
             WHEN UNIFORM(0, 99, HASH(pk.k, 'chan')) < 85 THEN 'Retail Store'
             ELSE 'Wholesale' END AS channel,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(pk.k, 'qty')) AS uq,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(pk.k, 'disc')) AS ud
    FROM picks pk
    JOIN sellable s     ON s.rn = pk.prod_rn
    JOIN DIM_CUSTOMER c ON c.CUSTOMER_ID = pk.customer_id
    WHERE pk.d BETWEEN c.FIRST_PURCHASE_DATE AND c.LAST_PURCHASE_DATE
), priced AS (
    SELECT tx.*,
        CASE channel WHEN 'DTC Website' THEN 'S00024'
                     WHEN 'International DTC' THEN 'S00025'
                     WHEN 'Wholesale' THEN 'S000' || (21 + UNIFORM(0, 2, HASH(k, 'store')))
                     ELSE 'S' || LPAD(UNIFORM(1, 20, HASH(k, 'store')), 5, '0') END AS store_id,
        CASE WHEN uq < 0.62 THEN 1 WHEN uq < 0.87 THEN 2 WHEN uq < 0.96 THEN 3 ELSE 4 END AS qty,
        IFF(channel = 'Wholesale', WHOLESALE_PRICE, MSRP) AS unit_price,
        CASE WHEN channel = 'Wholesale'                      THEN 0
             WHEN LIFECYCLE_STAGE = 'Markdown'               THEN 0.30
             WHEN d BETWEEN '2024-11-25' AND '2024-12-02'    THEN 0.25
             WHEN ud < 0.70 THEN 0 WHEN ud < 0.85 THEN 0.10 WHEN ud < 0.95 THEN 0.15 ELSE 0.20 END AS disc
    FROM tx
)
SELECT
    'T' || LPAD(k, 9, '0'),
    d, PRODUCT_ID, store_id, customer_id, channel, qty, unit_price, disc,
    ROUND(qty * unit_price, 2),
    ROUND(qty * unit_price * (1 - disc), 2),
    ROUND(qty * UNIT_COST, 2),
    UNIFORM(0::FLOAT, 1::FLOAT, HASH(k, 'return')) < IFF(channel IN ('DTC Website', 'International DTC'), 0.11, 0.05)
FROM priced;

-- ============================================================= FACT_DAILY_KPI
-- Rolled up from FACT_DAILY_SALES by date x channel x customer region, so the
-- KPI table always reconciles with transactions. Conversion rate, marketing
-- spend and inventory turns are modelled (no session/inventory-cost source).
INSERT INTO FACT_DAILY_KPI (KPI_DATE, CHANNEL, REGION, GROSS_REVENUE, NET_REVENUE, ORDERS, UNITS_SOLD,
    AVG_ORDER_VALUE, RETURN_RATE, CONVERSION_RATE, NEW_CUSTOMERS, REPEAT_CUSTOMERS, INVENTORY_TURNS,
    GROSS_MARGIN_PCT, COGS, MARKETING_SPEND, CAC, LTV_TO_CAC_RATIO)
WITH s AS (
    SELECT f.*, c.REGION,
           MIN(f.SALE_DATE) OVER (PARTITION BY f.CUSTOMER_ID) AS first_sale
    FROM FACT_DAILY_SALES f JOIN DIM_CUSTOMER c ON c.CUSTOMER_ID = f.CUSTOMER_ID
), g AS (
    SELECT SALE_DATE AS kpi_date, CHANNEL, REGION,
        SUM(GROSS_REVENUE) AS gross, SUM(NET_REVENUE) AS net, COUNT(*) AS orders, SUM(QUANTITY) AS units,
        AVG(IFF(RETURN_FLAG, 1, 0)) AS return_rate, SUM(COST_OF_GOODS) AS cogs,
        COUNT(DISTINCT IFF(SALE_DATE = first_sale, CUSTOMER_ID, NULL)) AS new_c,
        COUNT(DISTINCT CUSTOMER_ID) AS all_c
    FROM s GROUP BY 1, 2, 3
), m AS (
    SELECT g.*,
        ROUND(net * UNIFORM(0.08::FLOAT, 0.14::FLOAT, HASH(kpi_date, CHANNEL, REGION, 'mkt')), 2) AS mkt_spend
    FROM g
)
SELECT
    kpi_date, CHANNEL, REGION,
    ROUND(gross, 2), ROUND(net, 2), orders, units,
    ROUND(DIV0(net, orders), 2),
    ROUND(return_rate, 4),
    ROUND(CASE CHANNEL WHEN 'Retail Store' THEN 0.22 WHEN 'Wholesale' THEN 0.35 ELSE 0.032 END
          * UNIFORM(0.8::FLOAT, 1.2::FLOAT, HASH(kpi_date, CHANNEL, REGION, 'conv')), 4),
    new_c,
    all_c - new_c,
    ROUND(UNIFORM(4::FLOAT, 9::FLOAT, HASH(kpi_date, CHANNEL, REGION, 'turns')), 2),
    ROUND(DIV0(net - cogs, net), 4),
    ROUND(cogs, 2),
    mkt_spend,
    ROUND(DIV0(mkt_spend, GREATEST(new_c, 1)), 2),
    ROUND(LEAST(99, DIV0(DIV0(net, orders) * 3.5, DIV0(mkt_spend, GREATEST(new_c, 1)))), 2)
FROM m;

-- ================================================ FACT_CUSTOMER_INTERACTIONS (20K)
-- Each product has a latent quality score, so ratings, review text and
-- sentiment are consistent with each other and differ between products.
INSERT INTO FACT_CUSTOMER_INTERACTIONS (INTERACTION_ID, CUSTOMER_ID, INTERACTION_DATE, CHANNEL, INTERACTION_TYPE,
    PRODUCT_ID, PAGE_VIEWS, SESSION_DURATION_SEC, ADDED_TO_CART, PURCHASED, RETURNED, RATING, REVIEW_TEXT,
    SENTIMENT_SCORE, DEVICE_TYPE, REFERRAL_SOURCE)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 20000))
), sellable AS (
    SELECT PRODUCT_ID, ROW_NUMBER() OVER (ORDER BY PRODUCT_ID) AS rn
    FROM DIM_PRODUCT WHERE LIFECYCLE_STAGE IN ('In Market', 'Markdown', 'Retired')
), cnt AS (
    SELECT COUNT(*) AS c FROM sellable
), r AS (
    SELECT n,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'type')) AS ut,
        FLOOR(POW(UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'prod')), 1.6) * cnt.c) + 1 AS prod_rn,
        'C' || LPAD(UNIFORM(1, 5000, HASH(n, 'cust')), 6, '0') AS customer_id,
        DATEADD('second', UNIFORM(0, 31535999, HASH(n, 'ts')), '2024-10-01'::TIMESTAMP_NTZ) AS ts,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'dev')) AS ud,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'ref')) AS ur,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'intl')) AS ui,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'rating')) AS zr,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'sent')) AS zs,
        UNIFORM(1, 20, HASH(n, 'pv')) AS pv,
        UNIFORM(15, 900, HASH(n, 'dur')) AS dur,
        UNIFORM(0, 2, HASH(n, 'txt')) AS txt
    FROM base CROSS JOIN cnt
), t AS (
    SELECT r.*, s.PRODUCT_ID,
        CASE WHEN ut < 0.35 THEN 'Page View'  WHEN ut < 0.47 THEN 'Search'
             WHEN ut < 0.59 THEN 'Add to Cart' WHEN ut < 0.67 THEN 'Purchase'
             WHEN ut < 0.69 THEN 'Return'      WHEN ut < 0.75 THEN 'Review'
             WHEN ut < 0.85 THEN 'Email Click' WHEN ut < 0.90 THEN 'SMS Click'
             ELSE 'Store Visit' END AS itype,
        NORMAL(0::FLOAT, 0.6::FLOAT, HASH(s.PRODUCT_ID, 'quality')) AS quality
    FROM r JOIN sellable s ON s.rn = r.prod_rn
), t2 AS (
    SELECT t.*,
        IFF(itype = 'Review', GREATEST(1, LEAST(5, ROUND(4.1 + quality + 0.8 * zr))), NULL) AS rating
    FROM t
)
SELECT
    'I' || LPAD(n, 9, '0'),
    customer_id,
    ts,
    CASE WHEN itype = 'Store Visit' THEN 'Retail Store'
         WHEN ui < 0.08 THEN 'International DTC'
         ELSE 'DTC Website' END,
    itype,
    PRODUCT_ID,
    IFF(itype = 'Store Visit', 1, pv),
    dur,
    itype IN ('Add to Cart', 'Purchase'),
    itype = 'Purchase',
    itype = 'Return',
    rating,
    CASE WHEN rating = 5 THEN GET(ARRAY_CONSTRUCT('Love the fit and feel!', 'Best joggers I have ever owned.', 'My new favorite brand.'), txt)::STRING
         WHEN rating = 4 THEN GET(ARRAY_CONSTRUCT('Great for workouts and everyday wear.', 'Fabric is incredibly soft.', 'Perfect for travel.'), txt)::STRING
         WHEN rating = 3 THEN GET(ARRAY_CONSTRUCT('Runs a bit large, otherwise great.', 'A bit pricey but worth it.', 'Nice fabric, sizing is inconsistent.'), txt)::STRING
         WHEN rating <= 2 THEN GET(ARRAY_CONSTRUCT('Color faded after a few washes.', 'The quality has gone down recently.', 'Seams started coming apart after a month.'), txt)::STRING
    END,
    IFF(rating IS NULL, NULL, ROUND(GREATEST(-1, LEAST(1, (rating - 3) / 2 + 0.2 * zs)), 4)),
    CASE WHEN itype = 'Store Visit' THEN 'In-Store'
         WHEN ud < 0.58 THEN 'Mobile' WHEN ud < 0.92 THEN 'Desktop' ELSE 'Tablet' END,
    CASE WHEN itype = 'Email Click' THEN 'Email'
         WHEN itype IN ('Store Visit', 'SMS Click') THEN 'Direct'
         WHEN ur < 0.25 THEN 'Organic Search' WHEN ur < 0.45 THEN 'Paid Search'
         WHEN ur < 0.65 THEN 'Social Media'   WHEN ur < 0.85 THEN 'Direct'
         WHEN ur < 0.92 THEN 'Referral'       ELSE 'Influencer' END
FROM t2;

-- ==================================================== FACT_INVENTORY_SNAPSHOT
-- 52 weekly snapshots x 120 most popular products x 8 retail stores.
-- Holiday weeks draw stock down, producing more stockouts in Nov/Dec.
INSERT INTO FACT_INVENTORY_SNAPSHOT (SNAPSHOT_DATE, PRODUCT_ID, STORE_ID, ON_HAND_QTY, IN_TRANSIT_QTY,
    ALLOCATED_QTY, WEEKS_OF_SUPPLY, REORDER_POINT, STOCKOUT_FLAG)
WITH weeks AS (
    SELECT DATEADD('week', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2024-10-07'::DATE) AS wk
    FROM TABLE(GENERATOR(ROWCOUNT => 52))
), prods AS (
    SELECT PRODUCT_ID FROM DIM_PRODUCT
    WHERE LIFECYCLE_STAGE IN ('In Market', 'Markdown', 'Retired')
    ORDER BY PRODUCT_ID LIMIT 120
), strs AS (
    SELECT STORE_ID FROM DIM_STORE WHERE CHANNEL = 'Retail Store' ORDER BY STORE_ID LIMIT 8
), g AS (
    SELECT w.wk, p.PRODUCT_ID, s.STORE_ID,
        UNIFORM(4::FLOAT, 15::FLOAT, HASH(p.PRODUCT_ID, s.STORE_ID, 'rate')) AS weekly_rate,
        GREATEST(0, ROUND(60 - IFF(MONTH(w.wk) IN (11, 12), 28, 0)
                          + 28 * NORMAL(0::FLOAT, 1::FLOAT, HASH(w.wk, p.PRODUCT_ID, s.STORE_ID, 'oh')))) AS on_hand,
        GREATEST(0, ROUND(20 + 10 * NORMAL(0::FLOAT, 1::FLOAT, HASH(w.wk, p.PRODUCT_ID, s.STORE_ID, 'it')))) AS in_transit,
        GREATEST(0, ROUND(10 + 5 * NORMAL(0::FLOAT, 1::FLOAT, HASH(w.wk, p.PRODUCT_ID, s.STORE_ID, 'al')))) AS allocated
    FROM weeks w CROSS JOIN prods p CROSS JOIN strs s
)
SELECT wk, PRODUCT_ID, STORE_ID, on_hand, in_transit, allocated,
       ROUND(on_hand / weekly_rate, 1), ROUND(weekly_rate * 3), on_hand = 0
FROM g;

-- ======================================================= FACT_DEMAND_FORECAST
-- 12 months x 100 products x 6 stores. Model v1.0 (Oct-Mar) has ~22% error;
-- the improved v2.1 (Apr-Sep) has ~11% error — a nice "model improvement" story.
INSERT INTO FACT_DEMAND_FORECAST (FORECAST_ID, FORECAST_DATE, PRODUCT_ID, STORE_ID, SEASON, FORECAST_QTY,
    ACTUAL_QTY, FORECAST_REVENUE, ACTUAL_REVENUE, MODEL_VERSION, MAPE)
WITH months AS (
    SELECT DATEADD('month', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2024-10-01'::DATE) AS m
    FROM TABLE(GENERATOR(ROWCOUNT => 12))
), prods AS (
    SELECT PRODUCT_ID, MSRP FROM DIM_PRODUCT
    WHERE LIFECYCLE_STAGE IN ('In Market', 'Markdown', 'Retired')
    ORDER BY PRODUCT_ID LIMIT 100
), strs AS (
    SELECT STORE_ID FROM DIM_STORE WHERE CHANNEL = 'Retail Store' ORDER BY STORE_ID LIMIT 6
), a AS (
    SELECT mo.m, p.PRODUCT_ID, p.MSRP, s.STORE_ID,
        IFF(mo.m < '2025-04-01', 'v1.0', 'v2.1') AS model_version,
        GREATEST(0, ROUND(UNIFORM(25::FLOAT, 120::FLOAT, HASH(p.PRODUCT_ID, s.STORE_ID, 'base'))
            * CASE MONTH(mo.m) WHEN 11 THEN 1.6 WHEN 12 THEN 1.8 WHEN 1 THEN 0.8 WHEN 2 THEN 0.8
                               WHEN 5 THEN 1.15 WHEN 6 THEN 1.15 WHEN 7 THEN 1.15 ELSE 1.0 END
            * (1 + 0.12 * NORMAL(0::FLOAT, 1::FLOAT, HASH(mo.m, p.PRODUCT_ID, s.STORE_ID, 'act'))))) AS actual_qty,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(mo.m, p.PRODUCT_ID, s.STORE_ID, 'err')) AS z_err
    FROM months mo CROSS JOIN prods p CROSS JOIN strs s
), f AS (
    SELECT a.*,
        GREATEST(1, ROUND(actual_qty * (1 + IFF(model_version = 'v1.0', 0.22, 0.11) * z_err))) AS forecast_qty
    FROM a
)
SELECT
    'FC' || LPAD(ROW_NUMBER() OVER (ORDER BY m, PRODUCT_ID, STORE_ID), 7, '0'),
    m, PRODUCT_ID, STORE_ID,
    CASE WHEN MONTH(m) <= 4 THEN 'Spring' WHEN MONTH(m) <= 8 THEN 'Summer'
         WHEN MONTH(m) <= 10 THEN 'Fall' ELSE 'Holiday' END || ' ' || YEAR(m),
    forecast_qty, actual_qty,
    ROUND(forecast_qty * MSRP * 0.82, 2),
    ROUND(actual_qty * MSRP * 0.82, 2),
    model_version,
    ROUND(ABS(forecast_qty - actual_qty) / NULLIF(actual_qty, 0), 4)
FROM f;

-- ============================================================ ASSORTMENT_PLAN (200)
-- Closed seasons have full actuals; Fall 2025 is in season (partial);
-- Holiday 2025 is still being planned (no actuals). Markdown rises as
-- sell-through falls.
INSERT INTO ASSORTMENT_PLAN (PLAN_ID, SEASON, STORE_ID, CATEGORY, PRODUCT_LINE, PLANNED_STYLES, PLANNED_UNITS,
    PLANNED_REVENUE, ACTUAL_STYLES, ACTUAL_UNITS, ACTUAL_REVENUE, SELL_THROUGH_PCT, MARKDOWN_PCT, PLAN_STATUS)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 200))
), a AS (
    SELECT n,
        GET(ARRAY_CONSTRUCT('Spring 2024','Summer 2024','Fall 2024','Holiday 2024','Spring 2025','Summer 2025',
                            'Fall 2025','Holiday 2025'), UNIFORM(0, 7, HASH(n, 'season')))::STRING AS season,
        'S' || LPAD(UNIFORM(1, 20, HASH(n, 'store')), 5, '0') AS store_id,
        GET(ARRAY_CONSTRUCT('Men''s Tops','Men''s Bottoms','Men''s Outerwear','Women''s Tops','Women''s Bottoms',
                            'Women''s Outerwear','Women''s Accessories'), UNIFORM(0, 6, HASH(n, 'cat')))::STRING AS category,
        GET(ARRAY_CONSTRUCT('Performance','Everyday','Sunday','Banks','Ponto','DreamKnit'),
            UNIFORM(0, 5, HASH(n, 'line')))::STRING AS line,
        UNIFORM(5, 30, HASH(n, 'styles')) AS planned_styles,
        ROUND(UNIFORM(200, 4000, HASH(n, 'units')), -1) AS planned_units,
        UNIFORM(60::FLOAT, 130::FLOAT, HASH(n, 'price')) AS avg_price,
        LEAST(1.0, UNIFORM(0.6::FLOAT, 1.12::FLOAT, HASH(n, 'st'))) AS st_full,
        UNIFORM(0.8::FLOAT, 1.05::FLOAT, HASH(n, 'astyles')) AS style_ratio,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'md')) AS z_md,
        UNIFORM(0, 1, HASH(n, 'status')) AS status_roll
    FROM base
), b AS (
    SELECT a.*,
        season = 'Holiday 2025' AS is_future,
        season = 'Fall 2025'    AS in_season,
        st_full * IFF(season = 'Fall 2025', 0.55, 1.0) AS st
    FROM a
), c AS (
    SELECT b.*,
        IFF(is_future, NULL, GREATEST(0, LEAST(0.4, 0.42 - 0.38 * st + 0.05 * z_md))) AS markdown,
        IFF(is_future, NULL, ROUND(planned_units * st)) AS actual_units
    FROM b
)
SELECT
    'AP' || LPAD(n, 5, '0'),
    season, store_id, category, line,
    planned_styles, planned_units, ROUND(planned_units * avg_price, 2),
    IFF(is_future, NULL, GREATEST(1, ROUND(planned_styles * style_ratio))),
    actual_units,
    IFF(is_future, NULL, ROUND(actual_units * avg_price * (1 - markdown * 0.5), 2)),
    IFF(is_future, NULL, ROUND(st, 4)),
    ROUND(markdown, 4),
    CASE WHEN is_future THEN IFF(status_roll = 0, 'Draft', 'Approved')
         WHEN in_season THEN 'In Season'
         ELSE 'Closed' END
FROM c;

-- ================================================ PRODUCT_DEVELOPMENT_PIPELINE (80)
INSERT INTO PRODUCT_DEVELOPMENT_PIPELINE (PIPELINE_ID, PRODUCT_NAME, PRODUCT_LINE, CATEGORY, DESIGNER,
    TARGET_SEASON, CURRENT_STAGE, STAGE_ENTRY_DATE, TARGET_LAUNCH_DATE, ESTIMATED_COST, SUSTAINABILITY_CERT,
    MATERIAL_INNOVATION, RISK_LEVEL, NOTES)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 80))
), a AS (
    SELECT n,
        GET(ARRAY_CONSTRUCT('Performance','Everyday','Sunday','Banks','Ponto','Clementine','Riviera','Halo',
                            'DreamKnit','BlueLine'), UNIFORM(0, 9, HASH(n, 'line')))::STRING AS line,
        GET(ARRAY_CONSTRUCT('Men''s Tops','Men''s Bottoms','Women''s Tops','Women''s Bottoms','Women''s Outerwear',
                            'Women''s Accessories'), UNIFORM(0, 5, HASH(n, 'cat')))::STRING AS category,
        GET(ARRAY_CONSTRUCT('Concept','Design','Sampling','Tech Pack Review','Pre-Production','Production','In Market'),
            UNIFORM(0, 6, HASH(n, 'stage')))::STRING AS stage,
        UNIFORM(0, 2, HASH(n, 'risk')) AS risk_idx,
        DATEADD('day', UNIFORM(0, 240, HASH(n, 'entry')), '2025-01-15'::DATE) AS entry_date,
        UNIFORM(60, 300, HASH(n, 'lead')) AS lead_days
    FROM base
)
SELECT
    'PD' || LPAD(n, 4, '0'),
    line || ' ' || SPLIT_PART(category, ' ', 2) || ' Next Gen',
    line,
    category,
    GET(ARRAY_CONSTRUCT('Alex Chen','Sam Rivera','Jordan Lee','Taylor Kim','Morgan Patel','Casey Nguyen',
                        'Drew Santos','Riley Thompson','Avery Mitchell','Quinn Harper'), UNIFORM(0, 9, HASH(n, 'designer')))::STRING,
    CASE WHEN stage IN ('Concept', 'Design') THEN 'Fall 2026'
         WHEN stage IN ('Sampling', 'Tech Pack Review') THEN 'Summer 2026'
         WHEN stage = 'Pre-Production' THEN 'Spring 2026'
         ELSE 'Holiday 2025' END,
    stage,
    entry_date,
    DATEADD('day', lead_days, entry_date),
    ROUND(UNIFORM(8::FLOAT, 45::FLOAT, HASH(n, 'cost')), 2),
    GET(ARRAY_CONSTRUCT('bluesign', 'OEKO-TEX', 'GOTS', 'GRS', NULL, NULL), UNIFORM(0, 5, HASH(n, 'cert')))::STRING,
    GET(ARRAY_CONSTRUCT('Bio-based nylon from castor beans', 'Recycled ocean plastic fiber', 'Plant-based dye process',
                        'Zero-waste pattern cutting', 'Graphene-infused moisture wicking', 'Seaweed-based Lyocell',
                        'Regenerative cotton sourcing', NULL, NULL), UNIFORM(0, 8, HASH(n, 'innov')))::STRING,
    GET(ARRAY_CONSTRUCT('Low', 'Medium', 'High'), risk_idx)::STRING,
    CASE risk_idx
        WHEN 0 THEN 'Progressing on schedule; supplier samples approved.'
        WHEN 1 THEN 'Fit adjustments requested after wear test; one extra sample round expected.'
        ELSE 'Material sourcing delay - alternate mill being evaluated; launch date at risk.' END
FROM a;

DROP TABLE IF EXISTS _CUSTOMER_BASE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. CHURN PREDICTIONS (model scores the agent reads through the semantic view)
-- ─────────────────────────────────────────────────────────────────────────────

-- The churn notebook section overwrites this with scores from the registered
-- CHURN_PREDICTION_MODEL (MODEL_VERSION = 'V1'). Until then it is seeded from the
-- legacy score so the agent can already answer churn questions.
CREATE TABLE IF NOT EXISTS CHURN_PREDICTIONS AS
SELECT CUSTOMER_ID,
       CHURN_PROBABILITY::FLOAT                       AS CHURN_SCORE,
       IFF(CHURN_PROBABILITY >= 0.5, 1, 0)            AS CHURN_PREDICTION,
       'LEGACY_SEED'                                  AS MODEL_VERSION,
       CURRENT_TIMESTAMP()::TIMESTAMP_NTZ             AS SCORED_AT
FROM ML_CUSTOMER_FEATURES;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SEMANTIC VIEWS (Cortex Analyst: customer + churn, and executive KPIs)
-- ─────────────────────────────────────────────────────────────────────────────

-- ----------------------------------------------- Customer interactions view
CREATE OR REPLACE SEMANTIC VIEW CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CUSTOMER_INTERACTIONS_SV

  TABLES (
    customers AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.DIM_CUSTOMER
      PRIMARY KEY (CUSTOMER_ID)
      COMMENT = 'Customer dimension with demographics, segmentation, and lifetime value',
    interactions AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.FACT_CUSTOMER_INTERACTIONS
      PRIMARY KEY (INTERACTION_ID)
      COMMENT = 'Customer interaction events across channels',
    products AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.DIM_PRODUCT
      PRIMARY KEY (PRODUCT_ID)
      COMMENT = 'Product catalog with lines, categories, materials, and pricing',
    ml_features AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.ML_CUSTOMER_FEATURES
      PRIMARY KEY (CUSTOMER_ID)
      COMMENT = 'ML-generated customer features including churn and CLV predictions',
    campaigns AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.DIM_MARKETING_CAMPAIGN
      PRIMARY KEY (CAMPAIGN_ID)
      COMMENT = 'Marketing campaigns',
    campaign_perf AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.FACT_CAMPAIGN_PERFORMANCE
      PRIMARY KEY (PERF_ID)
      COMMENT = 'Daily campaign performance metrics',
    churn_preds AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CHURN_PREDICTIONS
      PRIMARY KEY (CUSTOMER_ID)
      COMMENT = 'Churn scores from the registered CHURN_PREDICTION_MODEL (batch inference in the warehouse)'
  )

  RELATIONSHIPS (
    interaction_to_customer AS interactions(CUSTOMER_ID) REFERENCES customers,
    interaction_to_product AS interactions(PRODUCT_ID) REFERENCES products,
    ml_to_customer AS ml_features(CUSTOMER_ID) REFERENCES customers,
    perf_to_campaign AS campaign_perf(CAMPAIGN_ID) REFERENCES campaigns,
    preds_to_customer AS churn_preds(CUSTOMER_ID) REFERENCES customers
  )

  FACTS (
    interactions.page_views AS interactions.PAGE_VIEWS,
    interactions.session_duration_sec AS interactions.SESSION_DURATION_SEC,
    interactions.rating AS interactions.RATING,
    interactions.sentiment_score AS interactions.SENTIMENT_SCORE COMMENT = 'Sentiment score from review text (-1 to 1)',
    customers.lifetime_value AS customers.LIFETIME_VALUE COMMENT = 'Customer lifetime value in dollars',
    customers.nps_score AS customers.NPS_SCORE COMMENT = 'Net Promoter Score 0-10',
    customers.churn_risk_score AS customers.CHURN_RISK_SCORE,
    ml_features.churn_probability AS ml_features.CHURN_PROBABILITY,
    ml_features.clv_predicted_12m AS ml_features.CLV_PREDICTED_12M,
    ml_features.purchase_frequency AS ml_features.PURCHASE_FREQUENCY,
    ml_features.f_avg_order_value AS ml_features.AVG_ORDER_VALUE,
    ml_features.total_spend_12m AS ml_features.TOTAL_SPEND_12M,
    campaign_perf.impressions AS campaign_perf.IMPRESSIONS,
    campaign_perf.clicks AS campaign_perf.CLICKS,
    campaign_perf.conversions AS campaign_perf.CONVERSIONS,
    campaign_perf.revenue_attributed AS campaign_perf.REVENUE_ATTRIBUTED,
    campaign_perf.campaign_cost AS campaign_perf.COST,
    churn_preds.model_churn_score AS churn_preds.CHURN_SCORE COMMENT = 'Model churn probability 0-1 from CHURN_PREDICTION_MODEL'
  )

  DIMENSIONS (
    customers.customer_name AS CONCAT(customers.FIRST_NAME, ' ', customers.LAST_NAME) WITH SYNONYMS = ('customer name', 'shopper') COMMENT = 'Full name of the customer',
    customers.customer_city AS customers.CITY,
    customers.customer_state AS customers.STATE,
    customers.customer_region AS customers.REGION SAMPLE_VALUES ('West', 'East', 'South', 'Midwest', 'International') IS_ENUM,
    customers.customer_segment AS customers.SEGMENT WITH SYNONYMS = ('segment', 'customer type') COMMENT = 'Customer loyalty segment' SAMPLE_VALUES ('Loyal VIP', 'Active Regular', 'New Customer', 'Lapsed', 'High-Value At-Risk', 'Win-Back Target', 'Browser') IS_ENUM,
    customers.preferred_channel AS customers.PREFERRED_CHANNEL SAMPLE_VALUES ('DTC Website', 'Retail Store', 'Wholesale', 'International DTC') IS_ENUM,
    interactions.interaction_date AS interactions.INTERACTION_DATE COMMENT = 'Date and time of the interaction',
    interactions.interaction_type AS interactions.INTERACTION_TYPE SAMPLE_VALUES ('Page View', 'Search', 'Add to Cart', 'Purchase', 'Return', 'Review', 'Email Click', 'SMS Click', 'Store Visit') IS_ENUM,
    interactions.interaction_channel AS interactions.CHANNEL SAMPLE_VALUES ('DTC Website', 'Retail Store', 'International DTC') IS_ENUM,
    interactions.device_type AS interactions.DEVICE_TYPE SAMPLE_VALUES ('Mobile', 'Desktop', 'Tablet', 'In-Store') IS_ENUM,
    interactions.referral_source AS interactions.REFERRAL_SOURCE SAMPLE_VALUES ('Organic Search', 'Paid Search', 'Social Media', 'Email', 'Direct', 'Referral', 'Influencer') IS_ENUM,
    products.product_name AS products.PRODUCT_NAME,
    products.product_line AS products.PRODUCT_LINE SAMPLE_VALUES ('Performance', 'Everyday', 'Sunday', 'Banks', 'Ponto', 'Clementine', 'Riviera', 'Halo', 'DreamKnit', 'BlueLine') IS_ENUM,
    products.product_category AS products.CATEGORY,
    products.product_material AS products.MATERIAL,
    ml_features.predicted_segment AS ml_features.SEGMENT_PREDICTED,
    campaigns.campaign_name_dim AS campaigns.CAMPAIGN_NAME,
    campaigns.campaign_type AS campaigns.CAMPAIGN_TYPE SAMPLE_VALUES ('Email Blast', 'Social Ads', 'Influencer', 'Retargeting', 'Loyalty Program', 'Seasonal Sale', 'New Launch', 'Brand Awareness') IS_ENUM,
    campaigns.campaign_status AS campaigns.STATUS SAMPLE_VALUES ('Active', 'Completed') IS_ENUM,
    churn_preds.churn_prediction AS churn_preds.CHURN_PREDICTION COMMENT = '1 if the model predicts the customer will churn (score >= 0.5)',
    churn_preds.model_version AS churn_preds.MODEL_VERSION COMMENT = 'Model version that produced the score; LEGACY_SEED before the notebook runs',
    churn_preds.scored_at AS churn_preds.SCORED_AT COMMENT = 'When the score was produced'
  )

  METRICS (
    interactions.total_interactions AS COUNT(interactions.INTERACTION_ID) COMMENT = 'Total customer interactions',
    interactions.unique_customers AS COUNT(DISTINCT interactions.CUSTOMER_ID) COMMENT = 'Unique interacting customers',
    interactions.avg_page_views AS AVG(interactions.page_views) COMMENT = 'Average page views per interaction',
    interactions.avg_session_duration AS AVG(interactions.session_duration_sec) COMMENT = 'Average session duration in seconds',
    interactions.avg_sentiment AS AVG(interactions.sentiment_score) COMMENT = 'Average sentiment score',
    interactions.avg_rating AS AVG(interactions.rating) COMMENT = 'Average product rating',
    interactions.purchase_count AS COUNT_IF(interactions.PURCHASED) COMMENT = 'Number of purchases',
    interactions.return_count AS COUNT_IF(interactions.RETURNED) COMMENT = 'Number of returns',
    interactions.cart_add_count AS COUNT_IF(interactions.ADDED_TO_CART) COMMENT = 'Number of add-to-cart events',
    customers.avg_lifetime_value AS AVG(customers.lifetime_value) COMMENT = 'Average customer lifetime value',
    customers.avg_nps AS AVG(customers.nps_score) COMMENT = 'Average NPS',
    ml_features.avg_churn_probability AS AVG(ml_features.churn_probability) COMMENT = 'Average ML churn probability',
    ml_features.avg_predicted_clv AS AVG(ml_features.clv_predicted_12m) COMMENT = 'Average predicted 12-month CLV',
    campaign_perf.total_campaign_revenue AS SUM(campaign_perf.revenue_attributed) COMMENT = 'Total campaign-attributed revenue',
    campaign_perf.total_campaign_cost AS SUM(campaign_perf.campaign_cost) COMMENT = 'Total campaign spend',
    campaign_perf.campaign_roas AS DIV0(SUM(campaign_perf.revenue_attributed), SUM(campaign_perf.campaign_cost)) COMMENT = 'Return on ad spend',
    churn_preds.avg_model_churn_score AS AVG(churn_preds.model_churn_score) WITH SYNONYMS = ('model churn risk', 'predicted churn risk') COMMENT = 'Average churn score from the registered churn model. Prefer this over avg_churn_probability, the legacy rule-based score',
    churn_preds.predicted_churners AS COUNT_IF(churn_preds.CHURN_PREDICTION = 1) COMMENT = 'Customers the churn model predicts will churn'
  )

  COMMENT = 'Customer interaction analytics: engagement, segmentation, campaigns, ML churn and CLV predictions.';


-- ------------------------------------------------- Executive KPI / BI view
CREATE OR REPLACE SEMANTIC VIEW CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CONVERSATIONAL_BI_SV

  TABLES (
    daily_kpi AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.FACT_DAILY_KPI
      COMMENT = 'Daily KPI metrics by channel and region',
    sales AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.FACT_DAILY_SALES
      PRIMARY KEY (SALE_ID)
      COMMENT = 'Individual sales transactions',
    products AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.DIM_PRODUCT
      PRIMARY KEY (PRODUCT_ID)
      COMMENT = 'Product catalog',
    stores AS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.DIM_STORE
      PRIMARY KEY (STORE_ID)
      COMMENT = 'Store locations'
  )

  RELATIONSHIPS (
    sale_to_product AS sales(PRODUCT_ID) REFERENCES products,
    sale_to_store AS sales(STORE_ID) REFERENCES stores
  )

  FACTS (
    sales.quantity AS sales.QUANTITY,
    sales.unit_price AS sales.UNIT_PRICE,
    sales.discount_pct AS sales.DISCOUNT_PCT,
    sales.gross_revenue AS sales.GROSS_REVENUE,
    sales.net_revenue AS sales.NET_REVENUE,
    sales.cost_of_goods AS sales.COST_OF_GOODS,
    daily_kpi.kpi_gross_revenue AS daily_kpi.GROSS_REVENUE,
    daily_kpi.kpi_net_revenue AS daily_kpi.NET_REVENUE,
    daily_kpi.kpi_orders AS daily_kpi.ORDERS,
    daily_kpi.kpi_units_sold AS daily_kpi.UNITS_SOLD,
    daily_kpi.kpi_aov AS daily_kpi.AVG_ORDER_VALUE,
    daily_kpi.kpi_return_rate AS daily_kpi.RETURN_RATE,
    daily_kpi.kpi_conversion_rate AS daily_kpi.CONVERSION_RATE,
    daily_kpi.kpi_new_customers AS daily_kpi.NEW_CUSTOMERS,
    daily_kpi.kpi_repeat_customers AS daily_kpi.REPEAT_CUSTOMERS,
    daily_kpi.kpi_gross_margin_pct AS daily_kpi.GROSS_MARGIN_PCT,
    daily_kpi.kpi_cogs AS daily_kpi.COGS,
    daily_kpi.kpi_marketing_spend AS daily_kpi.MARKETING_SPEND,
    daily_kpi.kpi_cac AS daily_kpi.CAC,
    daily_kpi.kpi_ltv_cac_ratio AS daily_kpi.LTV_TO_CAC_RATIO,
    products.unit_cost AS products.UNIT_COST,
    products.msrp AS products.MSRP
  )

  DIMENSIONS (
    daily_kpi.kpi_date AS daily_kpi.KPI_DATE COMMENT = 'KPI date',
    daily_kpi.kpi_channel AS daily_kpi.CHANNEL SAMPLE_VALUES ('DTC Website', 'Retail Store', 'Wholesale', 'International DTC') IS_ENUM,
    daily_kpi.kpi_region AS daily_kpi.REGION SAMPLE_VALUES ('West', 'East', 'South', 'Midwest', 'International') IS_ENUM,
    sales.sale_date AS sales.SALE_DATE COMMENT = 'Sale date',
    sales.sale_channel AS sales.CHANNEL SAMPLE_VALUES ('DTC Website', 'Retail Store', 'Wholesale', 'International DTC') IS_ENUM,
    products.product_name AS products.PRODUCT_NAME,
    products.product_line AS products.PRODUCT_LINE WITH SYNONYMS = ('collection', 'line') SAMPLE_VALUES ('Performance', 'Everyday', 'Sunday', 'Banks', 'Ponto', 'Clementine', 'Riviera', 'Halo', 'DreamKnit', 'BlueLine') IS_ENUM,
    products.product_category AS products.CATEGORY,
    products.product_subcategory AS products.SUBCATEGORY,
    products.product_material AS products.MATERIAL,
    products.product_color AS products.COLOR,
    products.product_season AS products.SEASON,
    products.lifecycle_stage AS products.LIFECYCLE_STAGE SAMPLE_VALUES ('Concept', 'Design', 'Sampling', 'Tech Pack Review', 'Pre-Production', 'Production', 'In Market', 'Markdown', 'Retired') IS_ENUM,
    products.is_sustainable AS products.IS_SUSTAINABLE,
    stores.store_name AS stores.STORE_NAME,
    stores.store_city AS stores.CITY,
    stores.store_state AS stores.STATE,
    stores.store_region AS stores.REGION SAMPLE_VALUES ('West', 'East', 'South', 'Midwest', 'International') IS_ENUM,
    stores.store_channel AS stores.CHANNEL
  )

  METRICS (
    sales.total_gross_revenue AS SUM(sales.gross_revenue) WITH SYNONYMS = ('total revenue', 'gross sales') COMMENT = 'Total gross revenue',
    sales.total_net_revenue AS SUM(sales.net_revenue) WITH SYNONYMS = ('net sales') COMMENT = 'Total net revenue after discounts',
    sales.total_orders AS COUNT(sales.SALE_ID) COMMENT = 'Total orders',
    sales.total_units_sold AS SUM(sales.quantity) COMMENT = 'Total units sold',
    sales.avg_order_value AS DIV0(SUM(sales.net_revenue), COUNT(sales.SALE_ID)) WITH SYNONYMS = ('AOV') COMMENT = 'Average order value',
    sales.total_cogs AS SUM(sales.cost_of_goods) COMMENT = 'Total cost of goods sold',
    sales.gross_margin AS DIV0(SUM(sales.net_revenue) - SUM(sales.cost_of_goods), SUM(sales.net_revenue)) COMMENT = 'Gross margin percentage',
    sales.avg_discount AS AVG(sales.discount_pct) COMMENT = 'Average discount percentage',
    sales.return_rate AS DIV0(COUNT_IF(sales.RETURN_FLAG), COUNT(sales.SALE_ID)) COMMENT = 'Return rate',
    sales.unique_customers AS COUNT(DISTINCT sales.CUSTOMER_ID) COMMENT = 'Unique customers',
    daily_kpi.total_kpi_gross_revenue AS SUM(daily_kpi.kpi_gross_revenue) COMMENT = 'KPI total gross revenue',
    daily_kpi.total_kpi_net_revenue AS SUM(daily_kpi.kpi_net_revenue) COMMENT = 'KPI total net revenue',
    daily_kpi.total_kpi_orders AS SUM(daily_kpi.kpi_orders) COMMENT = 'KPI total orders',
    daily_kpi.total_new_customers AS SUM(daily_kpi.kpi_new_customers) COMMENT = 'Total new customers',
    daily_kpi.total_repeat_customers AS SUM(daily_kpi.kpi_repeat_customers) COMMENT = 'Total repeat customers',
    daily_kpi.avg_gross_margin AS AVG(daily_kpi.kpi_gross_margin_pct) COMMENT = 'Average gross margin',
    daily_kpi.avg_conversion_rate AS AVG(daily_kpi.kpi_conversion_rate) COMMENT = 'Average conversion rate',
    daily_kpi.total_marketing_spend AS SUM(daily_kpi.kpi_marketing_spend) COMMENT = 'Total marketing spend',
    daily_kpi.avg_cac AS AVG(daily_kpi.kpi_cac) COMMENT = 'Average customer acquisition cost',
    daily_kpi.avg_ltv_cac_ratio AS AVG(daily_kpi.kpi_ltv_cac_ratio) COMMENT = 'Average LTV to CAC ratio'
  )

  COMMENT = 'Executive conversational BI: daily revenue KPIs, channel and region performance, product line analytics, store metrics, and marketing efficiency.'

  AI_SQL_GENERATION 'When calculating revenue metrics, use NET_REVENUE as the default unless the user specifically asks for gross. Round monetary values to 2 decimal places. When asked about trends, show data by month unless specified otherwise. Use FACT_DAILY_KPI for high-level KPI questions and FACT_DAILY_SALES for transaction-level analysis.'

  AI_QUESTION_CATEGORIZATION 'This view covers retail business analytics: revenue, orders, margins, marketing efficiency, and store performance. For customer churn, lifetime value, or ML predictions, direct users to the Customer Interactions semantic view.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CORTEX AGENT + MCP SERVER (one governed tool for external LLM agents)
-- ─────────────────────────────────────────────────────────────────────────────

-- The agent orchestrates two Cortex Analyst tools, each of which generates AND runs
-- its SQL against a semantic view. The MCP server exposes only the agent, so the
-- external client never gets a raw SQL tool that could bypass the semantic views.
-- Clients connect via streamable HTTP at:
--   POST /api/v2/databases/CORTEX_GATEWAY_RETAIL_LAB/schemas/PUBLIC/mcp-servers/RETAIL_MCP

CREATE OR REPLACE AGENT CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.RETAIL_ANALYTICS_AGENT
  COMMENT = 'Governed retail analytics agent exposed via RETAIL_MCP'
  PROFILE = '{"display_name": "Retail Analytics Assistant"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: >
    You are a retail analytics assistant for a specialty athletic apparel brand.
    You help business users analyze customer interactions, marketing campaign performance,
    sales trends, and key business KPIs. Be conversational but data-driven.
    Always include specific numbers and percentages in your answers.
    When showing revenue, round to 2 decimal places and format with dollar signs.
    When showing trends, default to monthly unless the user specifies otherwise.
    The data covers October 2024 through September 2025.
    If the user asks a vague question, suggest 2-3 specific angles they could explore.
  orchestration: >
    For questions about customer behavior, engagement, segmentation, churn, CLV,
    marketing campaigns, or ML predictions, use the customer_interactions_analyst tool.
    For churn risk, use the model churn score (avg_model_churn_score, predicted_churners)
    from the registered churn model unless the user asks for the legacy score.
    For questions about revenue, sales, orders, product performance, store metrics,
    margins, marketing spend efficiency, or executive KPIs, use the business_kpi_analyst tool.
    If a question spans both domains, use both tools and synthesize the results.
    Always generate a chart when the data supports visualization.
  sample_questions:
    - question: "What are our top product lines by net revenue?"
    - question: "Which customer segments have the highest churn risk?"
    - question: "How does DTC Website compare to Retail Store on revenue and margin?"
    - question: "What is our marketing ROAS by campaign type?"
    - question: "Show me the monthly revenue trend by region"
    - question: "Which referral sources drive the most purchases?"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "customer_interactions_analyst"
      description: >
        Use this tool for questions about customer behavior and engagement.
        Covers: customer interactions (page views, purchases, returns, reviews),
        customer segmentation (Loyal VIP, Active Regular, New Customer, Lapsed, etc.),
        customer sentiment and NPS scores, churn scores from the registered churn model
        (CHURN_PREDICTIONS), legacy churn probability and predicted CLV,
        marketing campaign performance (impressions, clicks, conversions, ROAS),
        product-level conversion rates, and device/channel/referral source analysis.
        Do NOT use for revenue totals, order counts, store performance, or executive KPIs.
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "business_kpi_analyst"
      description: >
        Use this tool for executive business intelligence and financial metrics.
        Covers: daily/weekly/monthly revenue (gross and net), order volume, units sold,
        average order value (AOV), gross margin, cost of goods sold (COGS),
        return rates, conversion rates, marketing spend and CAC, LTV-to-CAC ratio,
        product line performance, store-level analytics, channel comparison
        (DTC Website, Retail Store, Wholesale, International DTC),
        and regional performance (West, East, South, Midwest, International).
        Do NOT use for individual customer behavior, churn predictions, or campaign-level metrics.
  - tool_spec:
      type: "data_to_chart"
      name: "data_to_chart"
      description: "Generates visualizations from structured data returned by analyst tools. Use when the user asks for charts, trends, comparisons, or when data has 3+ rows."

tool_resources:
  customer_interactions_analyst:
    semantic_view: "CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CUSTOMER_INTERACTIONS_SV"
    execution_environment:
      type: "warehouse"
      warehouse: "GATEWAY_RETAIL_WH"
  business_kpi_analyst:
    semantic_view: "CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CONVERSATIONAL_BI_SV"
    execution_environment:
      type: "warehouse"
      warehouse: "GATEWAY_RETAIL_WH"
$$;

CREATE OR REPLACE MCP SERVER RETAIL_MCP FROM SPECIFICATION $$
tools:
  - name: retail_analytics_agent
    title: "Retail analytics agent"
    description: "Answers retail business questions end to end: revenue, orders, AOV, margin, returns by channel, region, store and product line; customer segments, engagement, reviews and campaign ROAS; and churn risk scored by the registered churn model. Pass the user's question as the message."
    type: "CORTEX_AGENT_RUN"
    identifier: "CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.RETAIL_ANALYTICS_AGENT"
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6b. GRANT ACCESS TO LAB OBJECTS (PUBLIC + SYSADMIN)
-- ─────────────────────────────────────────────────────────────────────────────
-- The agent resolves permissions from the querying user's DEFAULT ROLE.
-- That role needs: USAGE on db/schema/warehouse/agent/mcp-server,
-- SELECT on both semantic views AND their underlying tables.

-- PUBLIC (covers any role)
GRANT USAGE ON DATABASE CORTEX_GATEWAY_RETAIL_LAB TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA  CORTEX_GATEWAY_RETAIL_LAB.PUBLIC TO ROLE PUBLIC;
GRANT USAGE ON WAREHOUSE GATEWAY_RETAIL_WH TO ROLE PUBLIC;
GRANT USAGE ON AGENT CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.RETAIL_ANALYTICS_AGENT TO ROLE PUBLIC;
GRANT USAGE ON MCP SERVER CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.RETAIL_MCP TO ROLE PUBLIC;
GRANT SELECT ON SEMANTIC VIEW CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CUSTOMER_INTERACTIONS_SV TO ROLE PUBLIC;
GRANT SELECT ON SEMANTIC VIEW CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CONVERSATIONAL_BI_SV TO ROLE PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC TO ROLE PUBLIC;
GRANT SELECT ON FUTURE TABLES IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC TO ROLE PUBLIC;

-- SYSADMIN (explicit grants beyond ALL PRIVILEGES on db/schema)
GRANT USAGE ON WAREHOUSE GATEWAY_RETAIL_WH TO ROLE SYSADMIN;
GRANT USAGE ON AGENT CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.RETAIL_ANALYTICS_AGENT TO ROLE SYSADMIN;
GRANT USAGE ON MCP SERVER CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.RETAIL_MCP TO ROLE SYSADMIN;
GRANT SELECT ON SEMANTIC VIEW CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CUSTOMER_INTERACTIONS_SV TO ROLE SYSADMIN;
GRANT SELECT ON SEMANTIC VIEW CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CONVERSATIONAL_BI_SV TO ROLE SYSADMIN;
GRANT SELECT ON ALL TABLES IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC TO ROLE SYSADMIN;
GRANT SELECT ON FUTURE TABLES IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC TO ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. AI GATEWAY CONFIGURATION
-- ─────────────────────────────────────────────────────────────────────────────
-- The AI Gateway is auto-provisioned per account (named SNOWFLAKE).
-- Endpoint (get the exact host from SHOW AI GATEWAYS / DESCRIBE AI GATEWAY):
--   https://<account-host>/api/v2/aigateways/SNOWFLAKE
--   + /v1/chat/completions   OpenAI-compatible (all non-Claude models)
--   + /v1/messages           Anthropic-compatible (Claude models only)
-- This is a different endpoint from Cortex Inference (/api/v2/cortex): only
-- traffic through the gateway gets its access control, traces, and cost attribution.
--
-- The spec defines:
--   models:   allowlist of model name patterns (* = all models)
--   logging:  trace capture, client telemetry, payload recording
-- FROM SPECIFICATION replaces the WHOLE spec, so always submit every field.
-- Requires ACCOUNTADMIN.

USE ROLE ACCOUNTADMIN;

ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$
schema_version: 1
models:
  - name: '*'
logging:
  enabled: true
  enable_client_telemetry: true
  capture_payload:
    request_response: true
$$;

-- Let the lab role read traces (AGENT_TRACE_TABLE + usage views need MONITOR)
GRANT MONITOR ON AI GATEWAY SNOWFLAKE TO ROLE SYSADMIN;
GRANT USAGE   ON AI GATEWAY SNOWFLAKE TO ROLE SYSADMIN;

-- Cost sections of the lab/app: AI_GATEWAY_USAGE_HISTORY, budgets, user tags
GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER   TO ROLE SYSADMIN;
GRANT DATABASE ROLE SNOWFLAKE.BUDGET_CREATOR TO ROLE SYSADMIN;
GRANT DATABASE ROLE SNOWFLAKE.SECURITY_VIEWER TO ROLE SYSADMIN;   -- ACCOUNT_USAGE.USERS (spend by user)
GRANT DATABASE ROLE SNOWFLAKE.QUOTA_CREATOR TO ROLE SYSADMIN;
GRANT CREATE SNOWFLAKE.CORE.QUOTA ON SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC TO ROLE SYSADMIN;
GRANT APPLY TAG ON ACCOUNT TO ROLE SYSADMIN;
GRANT ALL PRIVILEGES ON DATABASE CORTEX_GATEWAY_RETAIL_LAB TO ROLE SYSADMIN;
GRANT ALL PRIVILEGES ON SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC TO ROLE SYSADMIN;

-- Verify the gateway configuration
DESCRIBE AI GATEWAY SNOWFLAKE;

USE ROLE SYSADMIN;
USE DATABASE CORTEX_GATEWAY_RETAIL_LAB;
USE SCHEMA PUBLIC;
USE WAREHOUSE GATEWAY_RETAIL_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. OPTIMIZATION LOOP TABLES (used by the Trace Analyzer app)
-- ─────────────────────────────────────────────────────────────────────────────
-- EVAL_PROMPTS     : fixed question set replayed through the gateway for each config
-- OPTIMIZATION_RUNS: one row per experiment config (model / system prompt / max_tokens)
-- OPTIMIZATION_RESULTS: one row per (run, prompt) with latency, tokens, judge score,
--                   and the trace_id so every result links back to AGENT_TRACE_TABLE

-- A view, so the numeric expectations are always computed from the current data,
-- including CHURN_PREDICTIONS after the notebook replaces the seed scores.
CREATE OR REPLACE VIEW EVAL_PROMPTS AS
WITH sales AS (
    SELECT s.*, p.PRODUCT_LINE FROM FACT_DAILY_SALES s JOIN DIM_PRODUCT p USING (PRODUCT_ID)
), seg AS (
    SELECT c.SEGMENT, AVG(cp.CHURN_SCORE) AS avg_score,
           COUNT_IF(cp.CHURN_PREDICTION = 1) AS churners
    FROM CHURN_PREDICTIONS cp JOIN DIM_CUSTOMER c USING (CUSTOMER_ID)
    GROUP BY c.SEGMENT
)
SELECT 'P01' AS PROMPT_ID, 'metric' AS CATEGORY,
       'What was total net revenue from October 2024 through September 2025?' AS PROMPT,
       'Total net revenue was $' || TO_VARCHAR(SUM(NET_REVENUE), 'FM999,999,999.00') AS EXPECTED
FROM sales
UNION ALL
SELECT 'P02', 'metric', 'Which sales channel had the highest net revenue, and how much?',
       MAX_BY(CHANNEL, rev) || ' had the highest net revenue at $' || TO_VARCHAR(MAX(rev), 'FM999,999,999.00')
FROM (SELECT CHANNEL, SUM(NET_REVENUE) rev FROM sales GROUP BY CHANNEL)
UNION ALL
SELECT 'P03', 'metric', 'Which product line had the highest net revenue?',
       MAX_BY(PRODUCT_LINE, rev) || ' with $' || TO_VARCHAR(MAX(rev), 'FM999,999,999.00')
FROM (SELECT PRODUCT_LINE, SUM(NET_REVENUE) rev FROM sales GROUP BY PRODUCT_LINE)
UNION ALL
SELECT 'P04', 'metric', 'What was the average order value across all channels?',
       'Average order value was $' || TO_VARCHAR(ROUND(SUM(NET_REVENUE) / COUNT(*), 2), 'FM999,990.00')
FROM sales
UNION ALL
SELECT 'P05', 'metric', 'What is the return rate for the DTC Website channel?',
       'DTC Website return rate was ' || TO_VARCHAR(ROUND(100 * COUNT_IF(RETURN_FLAG) / COUNT(*), 1)) || '%'
FROM sales WHERE CHANNEL = 'DTC Website'
UNION ALL
SELECT 'P06', 'metric', 'Which campaign type had the highest ROAS?',
       MAX_BY(CAMPAIGN_TYPE, roas) || ' had the highest ROAS at ' || TO_VARCHAR(ROUND(MAX(roas), 2)) || 'x'
FROM (SELECT c.CAMPAIGN_TYPE, SUM(p.REVENUE_ATTRIBUTED) / NULLIF(SUM(p.COST), 0) roas
      FROM FACT_CAMPAIGN_PERFORMANCE p JOIN DIM_MARKETING_CAMPAIGN c USING (CAMPAIGN_ID)
      GROUP BY c.CAMPAIGN_TYPE)
UNION ALL
SELECT 'P07', 'ml', 'Which customer segment has the highest average model churn score?',
       MAX_BY(SEGMENT, avg_score) || ' at ' || TO_VARCHAR(ROUND(MAX(avg_score), 2))
FROM seg
UNION ALL
SELECT 'P08', 'ml', 'How many customers does the churn model predict will churn?',
       TO_VARCHAR(SUM(churners)) || ' customers are predicted to churn'
FROM seg
UNION ALL
SELECT 'P09', 'ml', 'Which customer segment has the most predicted churners?',
       MAX_BY(SEGMENT, churners) || ' with ' || TO_VARCHAR(MAX(churners)) || ' predicted churners'
FROM seg
UNION ALL
SELECT 'P10', 'ml', 'What share of Loyal VIP customers are predicted to churn?',
       TO_VARCHAR(ROUND(100 * SUM(churners) / NULLIF(SUM(n), 0), 1)) || '% of Loyal VIP customers'
FROM (SELECT churners, (SELECT COUNT(*) FROM DIM_CUSTOMER WHERE SEGMENT = 'Loyal VIP') n
      FROM seg WHERE SEGMENT = 'Loyal VIP')
UNION ALL SELECT 'P11', 'definition', 'Define average order value in one sentence.', 'Net revenue divided by number of orders'
UNION ALL SELECT 'P12', 'definition', 'Define sell-through rate in one sentence.', 'Units sold as a share of units received or available in a period'
UNION ALL SELECT 'P13', 'definition', 'What is MAPE in demand forecasting? One sentence.', 'Mean absolute percentage error between forecast and actual demand'
UNION ALL SELECT 'P14', 'definition', 'What does an LTV to CAC ratio measure? One sentence.', 'Customer lifetime value relative to the cost of acquiring the customer'
UNION ALL SELECT 'P15', 'definition', 'Define customer churn in one sentence.', 'Customers who stop buying from the brand within a period';

CREATE TABLE IF NOT EXISTS OPTIMIZATION_RUNS (
    RUN_ID          VARCHAR,
    CREATED_AT      TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    LABEL           VARCHAR,          -- 'baseline' | 'candidate'
    MODEL           VARCHAR,
    SYSTEM_PROMPT   VARCHAR,
    MAX_TOKENS      NUMBER,
    SOURCE_FINDING  VARCHAR           -- advisor finding that motivated the run
);

CREATE TABLE IF NOT EXISTS OPTIMIZATION_RESULTS (
    RUN_ID          VARCHAR,
    PROMPT_ID       VARCHAR,
    TRACE_ID        VARCHAR,
    RESPONSE        VARCHAR,
    LATENCY_MS      NUMBER,
    INPUT_TOKENS    NUMBER,
    OUTPUT_TOKENS   NUMBER,
    STATUS          VARCHAR,
    JUDGE_SCORE     FLOAT,            -- 0-1 from AI_COMPLETE judge vs EXPECTED
    CREATED_AT      TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. STREAMLIT APP ACCESS (container runtime)
-- ─────────────────────────────────────────────────────────────────────────────
-- The Trace Analyzer app (../app) runs on the container runtime. It needs:
--   * PyPI egress to install its dependencies
--   * egress to the account host so the Live / Experiments pages can call the
--     gateway inference endpoint. The app authenticates with its container
--     session token by default; GATEWAY_PAT_SECRET is an optional fallback
--     (set SECRET_STRING to a PAT, then uncomment the SECRETS line in snowflake.yml).

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE NETWORK RULE CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_APP_EGRESS
  TYPE = HOST_PORT
  MODE = EGRESS
  VALUE_LIST = ('pypi.org', 'pypi.python.org', 'pythonhosted.org', 'files.pythonhosted.org',
                '<org>-<account>.snowflakecomputing.com');
-- ^ replace the last host with your account host (hyphens, not underscores)

CREATE SECRET IF NOT EXISTS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_PAT_SECRET
  TYPE = GENERIC_STRING
  SECRET_STRING = 'replace-with-a-programmatic-access-token';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION GATEWAY_RETAIL_APP_EAI
  ALLOWED_NETWORK_RULES = (CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_APP_EGRESS)
  ALLOWED_AUTHENTICATION_SECRETS = (CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_PAT_SECRET)
  ENABLED = TRUE;

GRANT USAGE ON INTEGRATION GATEWAY_RETAIL_APP_EAI TO ROLE SYSADMIN;
GRANT USAGE ON COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU TO ROLE SYSADMIN;
GRANT OWNERSHIP ON SECRET CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_PAT_SECRET TO ROLE SYSADMIN COPY CURRENT GRANTS;

USE ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9b. COST GOVERNANCE DEMO USER AND QUOTA
-- ─────────────────────────────────────────────────────────────────────────────
-- A dedicated service user that the demo drives over a tiny daily quota so the
-- block can be shown live. Keep real users OUT of this quota: a block applies to
-- every AI domain the user touches, not just the gateway.
-- The quota is scoped by tag INTERSECTION, so only users tagged
-- QUOTA_TIER = 'RETAIL_DEMO' are in it.

CREATE TAG IF NOT EXISTS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.COST_CENTER
  COMMENT = 'Cost center for gateway chargeback';
CREATE TAG IF NOT EXISTS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.QUOTA_TIER
  COMMENT = 'Selects which per-user quota a user falls under';

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS GATEWAY_RETAIL_COST_RL COMMENT = 'Gateway inference only';
GRANT USAGE ON AI GATEWAY SNOWFLAKE TO ROLE GATEWAY_RETAIL_COST_RL;
GRANT USAGE ON DATABASE CORTEX_GATEWAY_RETAIL_LAB TO ROLE GATEWAY_RETAIL_COST_RL;
GRANT USAGE ON SCHEMA  CORTEX_GATEWAY_RETAIL_LAB.PUBLIC TO ROLE GATEWAY_RETAIL_COST_RL;
GRANT USAGE ON WAREHOUSE GATEWAY_RETAIL_WH TO ROLE GATEWAY_RETAIL_COST_RL;
GRANT USAGE ON AGENT CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.RETAIL_ANALYTICS_AGENT TO ROLE GATEWAY_RETAIL_COST_RL;
GRANT USAGE ON MCP SERVER CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.RETAIL_MCP TO ROLE GATEWAY_RETAIL_COST_RL;
GRANT SELECT ON SEMANTIC VIEW CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CUSTOMER_INTERACTIONS_SV TO ROLE GATEWAY_RETAIL_COST_RL;
GRANT SELECT ON SEMANTIC VIEW CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.CONVERSATIONAL_BI_SV TO ROLE GATEWAY_RETAIL_COST_RL;
GRANT SELECT ON ALL TABLES IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC TO ROLE GATEWAY_RETAIL_COST_RL;
GRANT ROLE GATEWAY_RETAIL_COST_RL TO ROLE SYSADMIN;

CREATE USER IF NOT EXISTS GATEWAY_RETAIL_COST_DEMO
  TYPE = SERVICE
  DEFAULT_ROLE = GATEWAY_RETAIL_COST_RL
  COMMENT = 'AI Gateway lab: driven over its quota to demo block enforcement';
GRANT ROLE GATEWAY_RETAIL_COST_RL TO USER GATEWAY_RETAIL_COST_DEMO;
ALTER USER GATEWAY_RETAIL_COST_DEMO SET TAG
  CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.COST_CENTER = 'MERCHANDISING',
  CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.QUOTA_TIER = 'RETAIL_DEMO';

-- PAT for lab/generate_traffic.py --burst. Copy token_secret from the output into
-- ~/.snowflake/gateway_retail_cost.pat (chmod 600). Valid 7 days.
ALTER USER GATEWAY_RETAIL_COST_DEMO ADD PROGRAMMATIC ACCESS TOKEN cost_demo
  ROLE_RESTRICTION = 'GATEWAY_RETAIL_COST_RL' DAYS_TO_EXPIRY = 7;

USE ROLE SYSADMIN;
USE SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC;

CREATE SNOWFLAKE.CORE.QUOTA IF NOT EXISTS GATEWAY_RETAIL_QUOTA();
CALL GATEWAY_RETAIL_QUOTA!ADD_SHARED_RESOURCE('AI GATEWAY');
CALL GATEWAY_RETAIL_QUOTA!SET_USER_TAGS(
  [[(SELECT SYSTEM$REFERENCE('TAG', 'CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.QUOTA_TIER', 'SESSION', 'APPLYBUDGET')), 'RETAIL_DEMO']],
  'INTERSECTION');
-- Limits are whole credits; 1/day is the smallest. The burst uses a large model
-- with long outputs to reach it in a few minutes.
CALL GATEWAY_RETAIL_QUOTA!SET_PER_USER_LIMIT(1, 'DAILY');
CALL GATEWAY_RETAIL_QUOTA!SET_BLOCK_ENFORCEMENT_ENABLED(TRUE, FALSE);
CALL GATEWAY_RETAIL_QUOTA!ADD_NOTIFICATION_THRESHOLD(80, 'ACTUAL', FALSE, 'DAILY');
CALL GATEWAY_RETAIL_QUOTA!GET_CONFIG();

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. VERIFY SETUP
-- ─────────────────────────────────────────────────────────────────────────────

SHOW TABLES IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC;
SHOW SEMANTIC VIEWS IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC;
SHOW AGENTS IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC;
SHOW MCP SERVERS IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC;
SELECT TABLE_NAME, ROW_COUNT
FROM CORTEX_GATEWAY_RETAIL_LAB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'PUBLIC' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
