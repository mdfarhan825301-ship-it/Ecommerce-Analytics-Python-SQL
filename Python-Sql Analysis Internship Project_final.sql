Use olist;
DESCRIBE customers;
DESCRIBE sellers;
DESCRIBE products;
DESCRIBE orders;
DESCRIBE payments;

USE olist;

SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE order_items;
TRUNCATE TABLE payments;
TRUNCATE TABLE orders;
TRUNCATE TABLE products;
TRUNCATE TABLE sellers;
TRUNCATE TABLE customers;

SET FOREIGN_KEY_CHECKS = 1;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/customers (2).csv'
INTO TABLE customers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/sellers.csv'
INTO TABLE sellers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/products.csv'
INTO TABLE products
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE order_items;
TRUNCATE TABLE payments;
TRUNCATE TABLE orders;
SET FOREIGN_KEY_CHECKS = 0;


SELECT COUNT(*) FROM orders;


LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/payments.csv'
INTO TABLE payments
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/order_items.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

truncate table orders;
select count(*) from orders;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/orders.csv.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
order_id,
customer_id,
order_status,
@purchase,
@approved,
@carrier,
@customer,
@estimated
)
SET
order_purchase_timestamp = STR_TO_DATE(NULLIF(@purchase,''), '%Y-%m-%d %H:%i:%s'),
order_approved_at = STR_TO_DATE(NULLIF(@approved,''), '%Y-%m-%d %H:%i:%s'),
order_delivered_carrier_date = STR_TO_DATE(NULLIF(@carrier,''), '%Y-%m-%d %H:%i:%s'),
order_delivered_customer_date = STR_TO_DATE(NULLIF(@customer,''), '%Y-%m-%d %H:%i:%s'),
order_estimated_delivery_date = STR_TO_DATE(NULLIF(@estimated,''), '%Y-%m-%d %H:%i:%s');



-- ============================================================================
-- PART 1: FUNDAMENTAL PROBLEMS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- F1. List all unique cities where customers are located
-- ----------------------------------------------------------------------------
SELECT count(DISTINCT customer_city)
FROM customers
ORDER BY customer_city;
-- Result: 4,119 distinct cities (query returns one row per city)


-- ----------------------------------------------------------------------------
-- F2. Count the number of orders placed in 2017
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS orders_2017
FROM orders
WHERE YEAR(order_purchase_timestamp) = 2017;
-- Result: 45,101 orders

describe products;
-- ----------------------------------------------------------------------------
-- F3. Find the total sales per category
-- ----------------------------------------------------------------------------
SELECT 
    LOWER(TRIM(p.`product category`)) AS category,
    ROUND(SUM(oi.price), 2) AS total_sales
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY LOWER(TRIM(p.`product category`))
ORDER BY total_sales DESC;
-- Top 5 results:
--   health beauty          1,258,681.34
--   watches present        1,205,005.68
--   bed table bath         1,036,988.68
--   sport leisure            988,048.97
--   computer accessories     911,954.32


-- ----------------------------------------------------------------------------
-- F4. Calculate the percentage of orders that were paid in installments
-- (payment_installments > 1). Uses DISTINCT order_id because an order can
-- have multiple payment rows (e.g. voucher + credit card).
-- ----------------------------------------------------------------------------
SELECT
    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN payment_installments > 1 THEN order_id END)
        / COUNT(DISTINCT order_id)
    , 2) AS pct_orders_paid_in_installments
FROM payments;
-- Result: 51.46% of orders were paid in installments


-- ----------------------------------------------------------------------------
-- F5. Count the number of customers from each state
-- ----------------------------------------------------------------------------
SELECT
    customer_state,
    COUNT(*) AS n_customers
FROM customers
GROUP BY customer_state
ORDER BY n_customers DESC;
-- Top 5: SP 41,746 | RJ 12,852 | MG 11,635 | RS 5,466 | PR 5,045


-- ============================================================================
-- PART 2: INTERMEDIATE PROBLEMS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- I1. Calculate the number of orders per month in 2018
-- ----------------------------------------------------------------------------
SELECT
    MONTH(order_purchase_timestamp) AS month_2018,
    COUNT(*)                        AS n_orders
FROM orders
WHERE YEAR(order_purchase_timestamp) = 2018
GROUP BY MONTH(order_purchase_timestamp)
ORDER BY month_2018;



-- ----------------------------------------------------------------------------
-- I2. Find the average number of products per order, grouped by customer city
-- Filtered to cities with >=30 orders so the average isn't dominated by a
-- single-order city producing a noisy 1.0 or higher average.
-- ----------------------------------------------------------------------------
WITH order_item_counts AS (
    SELECT order_id, COUNT(*) AS n_items
    FROM order_items
    GROUP BY order_id
)
SELECT
    c.customer_city,
    ROUND(AVG(oic.n_items), 3) AS avg_items_per_order,
    COUNT(DISTINCT o.order_id) AS n_orders
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_item_counts oic ON o.order_id = oic.order_id
GROUP BY c.customer_city
HAVING COUNT(DISTINCT o.order_id) >= 30
ORDER BY avg_items_per_order DESC;


-- ----------------------------------------------------------------------------
-- I3. Calculate the percentage of total revenue contributed by each category
-- ----------------------------------------------------------------------------
SELECT 
    LOWER(TRIM(p.`product category`)) AS product_category,
    ROUND(100.0 * SUM(oi.price) / (SELECT SUM(price) FROM order_items), 2) AS pct_of_total_revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
WHERE p.`product category` IS NOT NULL
GROUP BY LOWER(TRIM(p.`product category`))
ORDER BY pct_of_total_revenue DESC
LIMIT 15;



-- ----------------------------------------------------------------------------
-- I4. Identify the correlation between product price and the number of
-- times a product has been purchased.
-- MySQL has no built-in CORR() aggregate, so we compute Pearson's r
-- manually from the standard formula:
--   r = (n*Sum(xy) - Sum(x)*Sum(y)) / sqrt((n*Sum(x^2)-Sum(x)^2)*(n*Sum(y^2)-Sum(y)^2))
-- ----------------------------------------------------------------------------
WITH product_stats AS (
    SELECT
        product_id,
        AVG(price)  AS avg_price,
        COUNT(*)    AS times_purchased
    FROM order_items
    GROUP BY product_id
),
agg AS (
    SELECT
        COUNT(*)                              AS n,
        SUM(avg_price)                        AS sum_x,
        SUM(times_purchased)                  AS sum_y,
        SUM(avg_price * avg_price)            AS sum_x2,
        SUM(times_purchased * times_purchased) AS sum_y2,
        SUM(avg_price * times_purchased)      AS sum_xy
    FROM product_stats
)
SELECT
    ROUND(
        (n * sum_xy - sum_x * sum_y) /
        (SQRT(n * sum_x2 - sum_x * sum_x) * SQRT(n * sum_y2 - sum_y * sum_y))
    , 4) AS correlation_price_vs_purchase_count
FROM agg;
-- Result: r = -0.0321 (essentially no linear relationship — price does not
-- meaningfully predict how often a product sells in this marketplace)


-- ----------------------------------------------------------------------------
-- I5. Calculate the total revenue generated by each seller, ranked by revenue
-- ----------------------------------------------------------------------------
SELECT
    seller_id,
    ROUND(SUM(price), 2) AS total_revenue,
    RANK() OVER (ORDER BY SUM(price) DESC) AS revenue_rank
FROM order_items
GROUP BY seller_id
ORDER BY total_revenue DESC;
-- #1 seller 4869f7a5... R$229,472.63 | #2 53243585... R$222,776.05
-- #3 4a3ca931... R$200,472.92


-- ============================================================================
-- PART 3: ADVANCED PROBLEMS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A1. Moving average of order values for each customer over their order
-- history (running average up to and including each order, in date order).
-- Order value = sum of item price + freight for all items in that order.
-- Uses customer_unique_id since one person can have multiple customer_ids.
-- ----------------------------------------------------------------------------
WITH order_values AS (
    SELECT
        o.order_id,
        c.customer_unique_id,
        o.order_purchase_timestamp,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM orders o
    JOIN customers c    ON o.customer_id = c.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY o.order_id, c.customer_unique_id, o.order_purchase_timestamp
)
SELECT
    customer_unique_id,
    order_purchase_timestamp,
    order_value,
    ROUND(
        AVG(order_value) OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
    , 2) AS moving_avg_order_value
FROM order_values
ORDER BY customer_unique_id, order_purchase_timestamp;


-- ----------------------------------------------------------------------------
-- A2. Cumulative sales per month for each year
-- ----------------------------------------------------------------------------
WITH monthly AS (
    SELECT
        YEAR(o.order_purchase_timestamp)  AS yr,
        MONTH(o.order_purchase_timestamp) AS mo,
        SUM(oi.price)                     AS monthly_sales
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY YEAR(o.order_purchase_timestamp), MONTH(o.order_purchase_timestamp)
)
SELECT
    yr,
    mo,
    ROUND(monthly_sales, 2) AS monthly_sales,
    ROUND(SUM(monthly_sales) OVER (PARTITION BY yr ORDER BY mo), 2) AS cumulative_sales_ytd
FROM monthly
ORDER BY yr, mo;


-- ----------------------------------------------------------------------------
-- A3. Year-over-year growth rate of total sales
-- ----------------------------------------------------------------------------
WITH yearly AS (
    SELECT
        YEAR(o.order_purchase_timestamp) AS yr,
        SUM(oi.price)                    AS yearly_sales
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY YEAR(o.order_purchase_timestamp)
)
SELECT
    yr,
    ROUND(yearly_sales, 2) AS yearly_sales,
    ROUND(
        100.0 * (yearly_sales - LAG(yearly_sales) OVER (ORDER BY yr))
        / LAG(yearly_sales) OVER (ORDER BY yr)
    , 2) AS yoy_growth_pct
FROM yearly
ORDER BY yr;
-- 2016: 49,785.92 (baseline, only ~3 partial months of data)
-- 2017: 6,155,806.98 (+12,264.55% vs the tiny 2016 base -- not a real
--        comparison, 2016 is a launch-period artifact)
-- 2018: 7,386,050.80 (+19.99% vs 2017 -- the meaningful YoY figure;
--        note 2018 data is also partial, cutting off in Sep/Oct)

SELECT COUNT(DISTINCT customer_id) FROM customers;
SELECT COUNT(DISTINCT customer_unique_id) FROM customers;
SELECT COUNT(DISTINCT customer_id) FROM orders;
SHOW COLUMNS FROM orders;
SHOW COLUMNS FROM customers;



-- ----------------------------------------------------------------------------
-- A4. Retention rate: % of customers who make another purchase within
-- 6 months of their first purchase
-- ----------------------------------------------------------------------------
WITH first_orders AS (
    SELECT
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_purchase
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
),
repeat_within_6m AS (
    SELECT DISTINCT f.customer_unique_id
    FROM first_orders f
    JOIN customers c ON c.customer_unique_id = f.customer_unique_id
    JOIN orders o    ON o.customer_id = c.customer_id
    WHERE o.order_purchase_timestamp > f.first_purchase
      AND o.order_purchase_timestamp <= DATE_ADD(f.first_purchase, INTERVAL 6 MONTH)
)
SELECT
    (SELECT COUNT(*) FROM first_orders)        AS total_customers,
    (SELECT COUNT(*) FROM repeat_within_6m)     AS retained_customers,
    ROUND(
        100.0 * (SELECT COUNT(*) FROM repeat_within_6m)
        / (SELECT COUNT(*) FROM first_orders)
    , 2) AS retention_rate_pct
FROM DUAL;
-- Result: 96,096 total customers, 2,234 retained within 6 months -> 2.32%
-- retention rate. This confirms the low overall repeat-purchase behavior
-- seen in the broader analysis -- the large majority of customers never
-- return, let alone within a 6-month window.


-- ----------------------------------------------------------------------------
-- A5. Top 3 customers who spent the most money in each year
-- ----------------------------------------------------------------------------
WITH yearly_spend AS (
    SELECT
        YEAR(o.order_purchase_timestamp) AS yr,
        c.customer_unique_id,
        SUM(oi.price)                    AS total_spent
    FROM orders o
    JOIN customers c    ON o.customer_id = c.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY YEAR(o.order_purchase_timestamp), c.customer_unique_id
),
ranked AS (
    SELECT
        yr,
        customer_unique_id,
        total_spent,
        ROW_NUMBER() OVER (PARTITION BY yr ORDER BY total_spent DESC) AS rn
    FROM yearly_spend
)
SELECT yr, customer_unique_id, ROUND(total_spent, 2) AS total_spent, rn
FROM ranked
WHERE rn <= 3
ORDER BY yr, rn;
-- 2016: fdaa290a... 1,399.00 | 753bc5d6... 1,299.99 | b92a2e5e... 1,199.00
-- 2017: 0a0a9211... 13,440.00 | da122df9... 7,388.00 | dc4802a7... 6,735.00
-- 2018: 763c8b1c... 7,160.00  | 459bef48... 6,729.00 | 5d0a2980... 4,599.90
