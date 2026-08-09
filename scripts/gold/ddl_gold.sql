/*
===============================================================================
DDL Script: Create Gold Views
===============================================================================
Script Purpose:
    This script creates views for the Gold layer in the data warehouse. 
    The Gold layer represents the final dimension and fact tables (Star Schema)

    Each view performs transformations and combines data from the Silver layer 
    to produce a clean, enriched, and business-ready dataset.

Usage:
    - These views can be queried directly for analytics and reporting.
===============================================================================
*/

-- =============================================================================
-- Create Dimension: gold.dim_customers
-- =============================================================================
--drop the view incase it already exists
IF OBJECT_ID('gold.dim_customer','V') is NOT NULL
    DROP VIEW gold.dim_customer;
GO
--Create the view in gold schema for dimension table dim_customer
CREATE VIEW gold.dim_customer as
select 
    ROW_NUMBER() OVER (ORDER BY cst_id) as customer_key,
    ci.cst_id as customer_id,
    ci.cst_key as customer_number,
    ci.cst_firstname as first_name,
    ci.cst_lastname as last_name,
    la.cntry as country,
    ci.cst_marital_status as marital_status,
    case when ci.cst_gndr != 'n/a' then ci.cst_gndr     --CRM is master for gender
        else coalesce(ca.gen, 'n/a')
    end as gender,
    ca.bdate as birthdate,
    ci.cst_create_date as create_date
from silver.crm_cust_info as ci
left join silver.erp_cust_az12 ca on ci.cst_key=ca.cid
left join silver.erp_loc_a101 la on ci.cst_key=la.cid;

-- =============================================================================
-- Create Dimension: gold.dim_products
-- =============================================================================
--drop the view incase it already exists
IF OBJECT_ID('gold.dim_products','V') is NOT NULL
    DROP VIEW gold.dim_products;
GO
--Create the view in gold schema for dimension table dim_products
CREATE VIEW gold.dim_products as
select
    ROW_NUMBER() OVER(ORDER BY pi.prd_id) as product_key,
    pi.prd_id as product_id,
    pi.prd_key as product_number,
    pi.prd_nm as product_name,
    pi.cat_id as category_id,
    pc.cat as category,
    pc.sub_cat as subcategory,
    pc.maintenance as maintenance,
    pi.prd_cost as cost,
    pi.prd_line as product_line,
    pi.prd_start_dt as start_date
from silver.crm_prd_info as pi 
left join silver.erp_px_cat_g1v2 pc on pi.cat_id=pc.id
where pi.prd_end_dt IS NULL ;                       -- Filter out all historical data

-- =============================================================================
-- Create Fact Table: gold.fact_sales
-- =============================================================================
--drop the view incase it already exists
IF OBJECT_ID('gold.fact_sales','V') is NOT NULL
    DROP VIEW gold.fact_sales;
GO
--Create the view in gold schema for dimension table fact_sales
CREATE VIEW gold.fact_sales as
select 
    sd.sls_ord_num as order_number,
    pr.product_key,
    cu.customer_key,
    sd.sls_order_dt as order_date,
    sd.sls_ship_dt as shipping_date,
    sd.sls_due_dt as due_date,
    sd.sls_sales as sales_amount,
    sd.sls_quantity as quantity,
    sd.sls_price as price
from silver.crm_sales_details sd 
left join gold.dim_products pr on sd.sls_prd_key = pr.product_number
left join gold.dim_customer cu on sd.sls_cust_id = cu.customer_id;
