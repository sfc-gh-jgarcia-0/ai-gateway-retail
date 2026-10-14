-- =============================================================================
-- Cortex AI Gateway Lab: Cleanup Script
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. CORTEX_GATEWAY_RETAIL_LAB is dedicated to this demo, so the fast path
-- drops the database (cascading the retail tables, both semantic views, the agent,
-- the churn model, its monitor and predictions, MCP server, network rule, secret, the Streamlit app, the eval/optimization
-- tables, and the notebook's COST_CENTER tag, GATEWAY_BUDGET and GATEWAY_QUOTA)
-- plus the account-level objects DROP DATABASE does NOT cascade.
--
-- The AI Gateway itself is account-level and shared: it is NOT dropped. The last
-- block resets its specification and removes the lab's grants.
--
-- All statements use IF EXISTS / are idempotent, so this is safe to re-run.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FAST PATH — drop the whole demo (recommended for "start fresh")
-- ─────────────────────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;

-- The notebook tags the lab user with COST_CENTER; unset it before the tag is dropped.
-- Replace <your_user> with the user that ran the notebook.
-- ALTER USER <your_user> UNSET TAG CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.COST_CENTER;

-- Cost governance demo user (setup.sql section 9b). Dropping it removes its PAT.
DROP USER IF EXISTS GATEWAY_RETAIL_COST_DEMO;
DROP ROLE IF EXISTS GATEWAY_RETAIL_COST_RL;

-- Cascades every schema-level object created by setup.sql, the notebook, and the app.
DROP DATABASE IF EXISTS CORTEX_GATEWAY_RETAIL_LAB;

-- Warehouse and external access integration live at the account level.
DROP WAREHOUSE IF EXISTS GATEWAY_RETAIL_WH;
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS GATEWAY_RETAIL_APP_EAI;

-- Lab PAT (created in the lab notebook's Configuration step). Replace <your_user>.
-- ALTER USER <your_user> REMOVE PROGRAMMATIC ACCESS TOKEN ai_gateway_demo;

-- ─────────────────────────────────────────────────────────────────────────────
-- AI GATEWAY — reset (shared account object; review before running)
-- ─────────────────────────────────────────────────────────────────────────────
-- setup.sql enabled client telemetry and payload capture and granted SYSADMIN
-- access. Uncomment to return the gateway to metadata-only logging and remove the
-- lab grants. Payload capture records full prompts/responses, so turn it off if
-- nothing else in the account needs it.

-- ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$
-- schema_version: 1
-- models:
--   - name: '*'
-- logging:
--   enabled: true
-- $$;
-- REVOKE MONITOR ON AI GATEWAY SNOWFLAKE FROM ROLE SYSADMIN;
-- REVOKE DATABASE ROLE SNOWFLAKE.USAGE_VIEWER    FROM ROLE SYSADMIN;
-- REVOKE DATABASE ROLE SNOWFLAKE.BUDGET_CREATOR  FROM ROLE SYSADMIN;
-- REVOKE DATABASE ROLE SNOWFLAKE.SECURITY_VIEWER FROM ROLE SYSADMIN;
-- REVOKE DATABASE ROLE SNOWFLAKE.QUOTA_CREATOR   FROM ROLE SYSADMIN;
-- REVOKE APPLY TAG ON ACCOUNT FROM ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleanup complete. Re-run lab/setup.sql, then the notebook, to rebuild.
-- ─────────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- ALTERNATIVE — object-by-object teardown (KEEP the database/warehouse)
-- =============================================================================
-- Use instead of the fast path if CORTEX_GATEWAY_RETAIL_LAB holds other work. Comment out
-- the DROP DATABASE / DROP WAREHOUSE lines above and run this block. Dependents
-- first: app -> quota/budget -> MCP server -> agent -> model monitor -> model ->
-- semantic views -> tables.
--
-- USE ROLE SYSADMIN;
-- USE SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC;
-- DROP STREAMLIT IF EXISTS AI_GATEWAY_RETAIL_TRACE_ANALYZER;
-- DROP SNOWFLAKE.CORE.QUOTA IF EXISTS GATEWAY_QUOTA;
-- DROP SNOWFLAKE.CORE.QUOTA IF EXISTS GATEWAY_RETAIL_QUOTA;
-- DROP SNOWFLAKE.CORE.BUDGET IF EXISTS GATEWAY_BUDGET;
-- DROP TAG IF EXISTS COST_CENTER;
-- DROP TAG IF EXISTS QUOTA_TIER;
-- DROP MCP SERVER IF EXISTS RETAIL_MCP;
-- DROP AGENT IF EXISTS RETAIL_ANALYTICS_AGENT;
-- DROP MODEL MONITOR IF EXISTS CHURN_MODEL_MONITOR;
-- DROP MODEL IF EXISTS CHURN_PREDICTION_MODEL;
-- DROP SEMANTIC VIEW IF EXISTS CUSTOMER_INTERACTIONS_SV;
-- DROP SEMANTIC VIEW IF EXISTS CONVERSATIONAL_BI_SV;
-- DROP VIEW IF EXISTS EVAL_PROMPTS;
-- DROP VIEW IF EXISTS CHURN_FEATURES_V;
-- DROP TABLE IF EXISTS OPTIMIZATION_RESULTS;
-- DROP TABLE IF EXISTS OPTIMIZATION_RUNS;
-- DROP TABLE IF EXISTS CHURN_PREDICTIONS;
-- DROP TABLE IF EXISTS CHURN_MONITOR_SOURCE;
-- DROP TABLE IF EXISTS CHURN_MONITOR_BASELINE;
-- -- Retail data tables
-- DROP TABLE IF EXISTS DIM_PRODUCT;            DROP TABLE IF EXISTS DIM_STORE;
-- DROP TABLE IF EXISTS DIM_CUSTOMER;           DROP TABLE IF EXISTS DIM_MARKETING_CAMPAIGN;
-- DROP TABLE IF EXISTS FACT_DAILY_SALES;       DROP TABLE IF EXISTS FACT_INVENTORY_SNAPSHOT;
-- DROP TABLE IF EXISTS FACT_DEMAND_FORECAST;   DROP TABLE IF EXISTS PRODUCT_DEVELOPMENT_PIPELINE;
-- DROP TABLE IF EXISTS FACT_CUSTOMER_INTERACTIONS; DROP TABLE IF EXISTS FACT_CAMPAIGN_PERFORMANCE;
-- DROP TABLE IF EXISTS FACT_DAILY_KPI;         DROP TABLE IF EXISTS ML_CUSTOMER_FEATURES;
-- DROP TABLE IF EXISTS ASSORTMENT_PLAN;
-- USE ROLE ACCOUNTADMIN;
-- DROP EXTERNAL ACCESS INTEGRATION IF EXISTS GATEWAY_RETAIL_APP_EAI;
-- DROP SECRET IF EXISTS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_PAT_SECRET;
-- DROP NETWORK RULE IF EXISTS CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_APP_EGRESS;
-- =============================================================================
