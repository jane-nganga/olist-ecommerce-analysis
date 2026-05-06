-- ================================================
-- OLIST E-COMMERCE ANALYSIS
-- Tools: MySQL Workbench
-- Dataset: Olist Brazilian E-Commerce (Kaggle)
-- Period: January 2017 - August 2018
-- ================================================

-- ================================================
-- DATABASE SETUP
-- ================================================

CREATE DATABASE olist;
USE olist;

-- ================================================
-- DATA CLEANING
-- Fix empty strings in date columns
-- ================================================

UPDATE orders SET order_purchase_timestamp = NULL 
WHERE order_purchase_timestamp = '';

UPDATE orders SET order_approved_at = NULL 
WHERE order_approved_at = '';

UPDATE orders SET order_delivered_carrier_date = NULL 
WHERE order_delivered_carrier_date = '';

UPDATE orders SET order_delivered_customer_date = NULL 
WHERE order_delivered_customer_date = '';

UPDATE orders SET order_estimated_delivery_date = NULL 
WHERE order_estimated_delivery_date = '';

-- Convert date columns to proper DATETIME type
ALTER TABLE orders
MODIFY order_purchase_timestamp DATETIME,
MODIFY order_approved_at DATETIME,
MODIFY order_delivered_carrier_date DATETIME,
MODIFY order_delivered_customer_date DATETIME,
MODIFY order_estimated_delivery_date DATETIME;

-- Fix order_items date column
UPDATE order_items SET shipping_limit_date = NULL 
WHERE shipping_limit_date = '';

ALTER TABLE order_items
MODIFY shipping_limit_date DATETIME;

-- Fix corrupted hash values in order_reviews date columns
UPDATE order_reviews 
SET review_creation_date = NULL 
WHERE review_creation_date NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}';

UPDATE order_reviews 
SET review_answer_timestamp = NULL 
WHERE review_answer_timestamp NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}';

ALTER TABLE order_reviews
MODIFY review_creation_date DATETIME,
MODIFY review_answer_timestamp DATETIME;

-- ================================================
-- SALES PERFORMANCE
-- ================================================

-- Query 1: Total Revenue
SELECT 
    ROUND(SUM(payment_value), 2) AS total_revenue
FROM order_payments;

-- Query 2: Monthly Revenue Trend
-- Note: Excludes incomplete months (Sep-Oct 2018)
-- and Olist launch period (Oct-Dec 2016)
SELECT 
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS month,
    ROUND(SUM(payment_value), 2) AS monthly_revenue
FROM orders o
JOIN order_payments op ON o.order_id = op.order_id
WHERE order_purchase_timestamp >= '2017-01-01'
AND order_purchase_timestamp < '2018-09-01'
GROUP BY month
ORDER BY month ASC;

-- Query 3: Order Volume by Status
SELECT 
    order_status,
    COUNT(*) AS total_orders,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;

-- ================================================
-- DELIVERY PERFORMANCE
-- ================================================

-- Query 4: On Time vs Late Delivery Rate
SELECT 
    COUNT(DISTINCT order_id) AS total_delivered,
    SUM(CASE WHEN order_delivered_customer_date <= order_estimated_delivery_date 
        THEN 1 ELSE 0 END) AS on_time,
    SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date 
        THEN 1 ELSE 0 END) AS late,
    ROUND(SUM(CASE WHEN order_delivered_customer_date <= order_estimated_delivery_date 
        THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT order_id), 2) AS on_time_percentage
FROM orders
WHERE order_status = 'delivered'
AND order_delivered_customer_date IS NOT NULL
AND order_estimated_delivery_date IS NOT NULL;

-- ================================================
-- CUSTOMER SATISFACTION
-- ================================================

-- Query 5: Review Score Distribution
SELECT 
    review_score,
    COUNT(*) AS total_reviews,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage
FROM order_reviews
GROUP BY review_score
ORDER BY review_score DESC;

-- Query 6: Impact of Late Delivery on Review Scores
-- Key finding: 34% satisfaction drop for late deliveries
SELECT 
    CASE 
        WHEN order_delivered_customer_date > order_estimated_delivery_date 
        THEN 'Late'
        ELSE 'On Time'
    END AS delivery_status,
    ROUND(AVG(review_score), 2) AS avg_review_score,
    COUNT(*) AS total_orders
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE order_delivered_customer_date IS NOT NULL
AND order_estimated_delivery_date IS NOT NULL
GROUP BY delivery_status;

-- ================================================
-- SELLER PERFORMANCE
-- ================================================

-- Query 7a: Top 10 Sellers by Order Volume
SELECT 
    seller_id,
    COUNT(DISTINCT order_id) AS total_orders
FROM order_items
GROUP BY seller_id
ORDER BY total_orders DESC
LIMIT 10;

-- Query 7b: Top 10 Sellers by Revenue
SELECT 
    seller_id,
    ROUND(SUM(price + freight_value), 2) AS total_revenue
FROM order_items
GROUP BY seller_id
ORDER BY total_revenue DESC
LIMIT 10;

-- Query 7c: Top Sellers by Review Score
-- Minimum 100 orders threshold for statistical reliability
SELECT 
    oi.seller_id,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    COUNT(DISTINCT oi.order_id) AS total_orders
FROM order_items oi
JOIN order_reviews r ON oi.order_id = r.order_id
GROUP BY oi.seller_id
HAVING COUNT(DISTINCT oi.order_id) >= 100
ORDER BY avg_review_score DESC
LIMIT 10;

-- Query 7d: Combined Seller Performance
-- Revenue, orders and satisfaction in one view
SELECT 
    oi.seller_id,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM order_items oi
JOIN order_reviews r ON oi.order_id = r.order_id
GROUP BY oi.seller_id
HAVING COUNT(DISTINCT oi.order_id) >= 100
ORDER BY total_revenue DESC
LIMIT 10;

-- ================================================
-- PRODUCT PERFORMANCE
-- ================================================

-- Query 8a: Revenue by Product Category
SELECT 
    pt.product_category_name_english,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    COUNT(DISTINCT oi.order_id) AS total_orders
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN product_category_translation pt 
    ON p.product_category_name = pt.product_category_name
GROUP BY pt.product_category_name_english
ORDER BY total_revenue DESC
LIMIT 10;

-- Query 8b: Average Price by Category
-- Reveals health_beauty has 40% price premium
SELECT 
    pt.product_category_name_english,
    ROUND(AVG(oi.price), 2) AS avg_price,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN product_category_translation pt 
    ON p.product_category_name = pt.product_category_name
GROUP BY pt.product_category_name_english
ORDER BY total_revenue DESC
LIMIT 10;

-- ================================================
-- VIEWS FOR POWER BI INTEGRATION
-- ================================================

-- View 1: Category Review Scores
-- Pre-aggregated for Power BI visualization
-- Minimum 100 orders for statistical reliability
CREATE VIEW category_review_scores AS
SELECT 
    pt.product_category_name_english,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM order_reviews r
JOIN orders o ON r.order_id = o.order_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
JOIN product_category_translation pt 
    ON p.product_category_name = pt.product_category_name
GROUP BY pt.product_category_name_english
HAVING COUNT(DISTINCT o.order_id) >= 100;

-- View 2: Top Sellers Ranked
-- Uses ROW_NUMBER for clean seller ranking
CREATE VIEW top_sellers AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY SUM(oi.price + oi.freight_value) DESC) 
        AS seller_rank,
    s.seller_id,
    s.seller_city,
    s.seller_state,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    COUNT(DISTINCT oi.order_id) AS total_orders
FROM sellers s
JOIN order_items oi ON s.seller_id = oi.seller_id
GROUP BY s.seller_id, s.seller_city, s.seller_state;