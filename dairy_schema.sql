-- AHM05: Agricultural Input & Output Price Indices (you downloaded only needed items)
DROP TABLE IF EXISTS stg_ahm05_raw;
CREATE TABLE stg_ahm05_raw (
    statistic           text,
    month_text          text,   -- e.g. '2020 January'
    agricultural_product text,  -- e.g. 'Milk', 'Fertilisers', 'Energy', 'Compound feeding stuffs'
    value               numeric
);

-- CPM18: CPI (Milk, cheese & eggs + items)
DROP TABLE IF EXISTS stg_cpm18_raw;
CREATE TABLE stg_cpm18_raw (
    statistic   text,
    month_text  text,   -- e.g. '2020 January'
    coicop_item text,   -- e.g. '01.1.4 Milk, cheese and eggs' or 'Fresh whole milk'
    value       numeric
);


DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date AS
SELECT DISTINCT
    date_trunc('month', to_date(month_text, 'YYYY Month'))::date AS month_start,
    EXTRACT(YEAR  FROM to_date(month_text, 'YYYY Month'))::int  AS year,
    EXTRACT(MONTH FROM to_date(month_text, 'YYYY Month'))::int  AS month,
    to_char(to_date(month_text, 'YYYY Month'), 'YYYY-MM')       AS ym,
    CASE EXTRACT(MONTH FROM to_date(month_text, 'YYYY Month'))
        WHEN 3 THEN 'Spring' WHEN 4 THEN 'Spring' WHEN 5 THEN 'Spring'
        WHEN 6 THEN 'Summer' WHEN 7 THEN 'Summer' WHEN 8 THEN 'Summer'
        WHEN 9 THEN 'Autumn' WHEN 10 THEN 'Autumn' WHEN 11 THEN 'Autumn'
        ELSE 'Winter' END                                       AS season
FROM (
    SELECT month_text FROM stg_ahm05_raw
    UNION
    SELECT month_text FROM stg_cpm18_raw
) m
ORDER BY 1;
ALTER TABLE dim_date ADD PRIMARY KEY (month_start);

DROP TABLE IF EXISTS fact_farm_inputs;
CREATE TABLE fact_farm_inputs AS
WITH base AS (
    SELECT
        date_trunc('month', to_date(month_text,'YYYY Month'))::date AS month_start,
        -- Normalise product names just in case
        trim(lower(agricultural_product)) AS product,
        value::numeric AS idx
    FROM stg_ahm05_raw
)
SELECT
    d.month_start,
    MAX(idx) FILTER (WHERE product = 'milk')                                   AS output_milk_idx,
    MAX(idx) FILTER (WHERE product LIKE 'fertiliser%')                          AS input_fertilisers_idx,
    MAX(idx) FILTER (WHERE product LIKE 'energy%')                              AS input_energy_idx,
    MAX(idx) FILTER (WHERE product LIKE 'compound feeding stuffs%')             AS input_feed_idx
FROM dim_date d
LEFT JOIN base b ON b.month_start = d.month_start
GROUP BY d.month_start
ORDER BY d.month_start;

-- Add derived metrics
ALTER TABLE fact_farm_inputs
    ADD COLUMN input_avg_idx numeric,
    ADD COLUMN spread_idx    numeric,
    ADD COLUMN mom_spread_chg numeric,
    ADD COLUMN yoy_spread_chg numeric;

UPDATE fact_farm_inputs f
SET input_avg_idx = ROUND( (COALESCE(input_fertilisers_idx,0) 
                           +COALESCE(input_energy_idx,0) 
                           +COALESCE(input_feed_idx,0)) / NULLIF(
                              (CASE WHEN input_fertilisers_idx IS NOT NULL THEN 1 ELSE 0 END
                               +CASE WHEN input_energy_idx      IS NOT NULL THEN 1 ELSE 0 END
                               +CASE WHEN input_feed_idx        IS NOT NULL THEN 1 ELSE 0 END), 0), 2 ),
    spread_idx    = ROUND(output_milk_idx - input_avg_idx, 2);

-- MoM & YoY spread deltas
WITH x AS (
  SELECT month_start, spread_idx,
         LAG(spread_idx, 1)  OVER (ORDER BY month_start) AS prev_m,
         LAG(spread_idx,12)  OVER (ORDER BY month_start) AS prev_y
  FROM fact_farm_inputs
)
UPDATE fact_farm_inputs f
SET mom_spread_chg = ROUND((x.spread_idx - x.prev_m), 2),
    yoy_spread_chg = ROUND((x.spread_idx - x.prev_y), 2)
FROM x
WHERE f.month_start = x.month_start;


DROP TABLE IF EXISTS fact_retail_cpi;
CREATE TABLE fact_retail_cpi AS
SELECT
    date_trunc('month', to_date(month_text,'YYYY Month'))::date AS month_start,
    MAX(value) FILTER (WHERE lower(coicop_item) LIKE '01.1.4%') AS cpi_mce_idx,  -- Milk, cheese & eggs (broad)
    MAX(value) FILTER (WHERE lower(coicop_item) LIKE 'fresh%milk%') AS cpi_fresh_milk_idx
FROM stg_cpm18_raw
GROUP BY 1
ORDER BY 1;

ALTER TABLE fact_retail_cpi ADD PRIMARY KEY (month_start);


-- View 1: Farm vs Input Costs (with spread & rolling means)
CREATE OR REPLACE VIEW v_farm_vs_inputs AS
SELECT
    f.month_start,
    f.output_milk_idx,
    f.input_fertilisers_idx,
    f.input_energy_idx,
    f.input_feed_idx,
    f.input_avg_idx,
    f.spread_idx,
    AVG(f.spread_idx) OVER (ORDER BY f.month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS spread_rolling_12,
    f.mom_spread_chg,
    f.yoy_spread_chg
FROM fact_farm_inputs f
ORDER BY f.month_start;

-- View 2: Farm vs Retail (alignment / lag spotting)
CREATE OR REPLACE VIEW v_farm_vs_retail AS
SELECT
    f.month_start,
    f.output_milk_idx,
    r.cpi_mce_idx,
    r.cpi_fresh_milk_idx,
    LAG(r.cpi_mce_idx, 1) OVER (ORDER BY f.month_start)  AS cpi_mce_tminus1,
    LAG(r.cpi_mce_idx, 3) OVER (ORDER BY f.month_start)  AS cpi_mce_tminus3
FROM fact_farm_inputs f
LEFT JOIN fact_retail_cpi r USING (month_start)
ORDER BY f.month_start;


-- Simple contemporaneous correlation (broad basket)
SELECT corr(output_milk_idx, cpi_mce_idx) AS corr_farm_vs_cpi
FROM v_farm_vs_retail;

-- Try a 3-month retail lag
SELECT corr(output_milk_idx, cpi_mce_tminus3) AS corr_farm_vs_cpi_lag3
FROM v_farm_vs_retail;


-- How many months do we have in the join?
SELECT COUNT(*) AS rows_all
FROM v_farm_vs_retail;

-- How many months have BOTH series present?
SELECT COUNT(*) AS rows_both_present
FROM v_farm_vs_retail
WHERE output_milk_idx IS NOT NULL
  AND cpi_mce_idx     IS NOT NULL;

-- See a few rows where CPI is NULL
SELECT *
FROM v_farm_vs_retail
WHERE cpi_mce_idx IS NULL
ORDER BY month_start
LIMIT 20;

-- What exactly are the CPI item labels we loaded?
SELECT DISTINCT coicop_item
FROM stg_cpm18_raw
ORDER BY 1
LIMIT 50;

DROP CASCADE TABLE IF EXISTS fact_retail_cpi;
CREATE TABLE fact_retail_cpi AS
WITH base AS (
  SELECT
    date_trunc('month', to_date(month_text,'YYYY Month'))::date AS month_start,
    trim(lower(coicop_item)) AS item_norm,
    value::numeric AS idx
  FROM stg_cpm18_raw
)
SELECT
  month_start,
  MAX(idx) FILTER (
    -- match either the code or the phrase
    WHERE item_norm LIKE '01.1.4%' 
       OR item_norm ILIKE '%milk, cheese%eggs%'
  ) AS cpi_mce_idx,
  MAX(idx) FILTER (
    WHERE item_norm ILIKE 'fresh%milk%'
       OR item_norm ILIKE '%whole milk%'
  ) AS cpi_fresh_milk_idx
FROM base
GROUP BY month_start
ORDER BY month_start;

ALTER TABLE fact_retail_cpi ADD PRIMARY KEY (month_start);

DROP VIEW IF EXISTS v_farm_vs_retail;

CREATE OR REPLACE VIEW v_farm_vs_retail AS
SELECT
    f.month_start,
    f.output_milk_idx,
    r.cpi_mce_idx,
    r.cpi_fresh_milk_idx,
    LAG(r.cpi_mce_idx, 1) OVER (ORDER BY f.month_start)  AS cpi_mce_tminus1,
    LAG(r.cpi_mce_idx, 3) OVER (ORDER BY f.month_start)  AS cpi_mce_tminus3
FROM fact_farm_inputs f
LEFT JOIN fact_retail_cpi r
  ON f.month_start = r.month_start
ORDER BY f.month_start;



-- Recompute corr with explicit NOT NULL filter
SELECT corr(output_milk_idx, cpi_mce_idx) AS corr_farm_vs_cpi
FROM v_farm_vs_retail
WHERE output_milk_idx IS NOT NULL
  AND cpi_mce_idx     IS NOT NULL;

-- 3-month lag version
SELECT corr(output_milk_idx, cpi_mce_tminus3) AS corr_farm_vs_cpi_lag3
FROM v_farm_vs_retail
WHERE output_milk_idx IS NOT NULL
  AND cpi_mce_tminus3 IS NOT NULL;

COPY (SELECT * FROM dairy.v_farm_vs_inputs ORDER BY month_start)
TO 'C:\\Users\\Adnaan\\\\v_farm_vs_inputs.csv'
WITH (FORMAT CSV, HEADER, ENCODING 'UTF8');