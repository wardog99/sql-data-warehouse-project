--stored procedure for loading data from bronze layer to silver layer....
/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/
CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Silver Layer';
        PRINT '================================================';

		PRINT '------------------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '------------------------------------------------';

        --crm_cust_info
        --Truncate the table if there is data.
        SET @start_time = GETDATE();
        PRINT '>> Truncating the table silver.crm_cust_info';
        IF EXISTS (SELECT 1 FROM silver.crm_cust_info)
        TRUNCATE TABLE silver.crm_cust_info;
        -- loading data into silver.crm_cust-info table 
        PRINT '>> Loading the table silver.crm_cust_info';
        INSERT INTO silver.crm_cust_info (
        cst_id,
        cst_key,
        cst_firstname,
        cst_lastname,
        cst_marital_status,
        cst_gndr,
        cst_create_date
        )
        select 
        cst_id,
        cst_key,
        TRIM(cst_firstname) as cst_firstname,                           --removing unwanted spaces from the data
        TRIM(cst_lastname) as cst_lastname,                             --removing unwanted spaces from the data
        CASE WHEN UPPER(TRIM(cst_marital_status))= 'M' THEN 'Married'   -- data normalizationa and standardization
            WHEN UPPER(TRIM(cst_marital_status))= 'S' THEN 'Single'
            ELSE 'n/a'                                                 -- handling missing data
        END as cst_marital_status,
        CASE WHEN UPPER(TRIM(cst_gndr))= 'M' THEN 'Male'                -- data normalizationa and standardization
            WHEN UPPER(TRIM(cst_gndr))= 'F' THEN 'Female'
            ELSE 'n/a'                                                 -- handling missing data  
        END as cst_gndr,
        cst_create_date
        from (SELECT *,
        ROW_NUMBER() OVER (PARTITION BY cst_id order by cst_create_date desc) AS flag_last
        FROM bronze.crm_cust_info where cst_id is not null) as t        -- removing duplicates by keeping the latest record
        where t.flag_last = 1;
        SET @end_time = GETDATE();
        PRINT '>> LOAD DURATION: ' + CAST(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        --crm_prd_info
        --Truncate the table if there is data.
        SET @start_time = GETDATE();
        PRINT '>> Truncating the table silver.crm_prd_info';
        IF EXISTS (SELECT 1 FROM silver.crm_prd_info)
        TRUNCATE TABLE silver.crm_prd_info;
        -- loading data into silver.crm_prd_info table 
        PRINT '>> Loading the table silver.crm_prd_info';
        INSERT INTO silver.crm_prd_info (
        prd_id,
        cat_id,
        prd_key,
        prd_nm,
        prd_cost,
        prd_line,
        prd_start_dt,
        prd_end_dt
        )
        select 
        prd_id,
        REPLACE(SUBSTRING(prd_key,1,5),'-','_') as cat_id,              -- generated from prd_key, first 5 characters
        SUBSTRING(prd_key,7,LEN(prd_key)) as prd_key,                   -- separated the cat_id from prd_key
        prd_nm,
        ISNULL(prd_cost,0) as prd_cost,                                 -- made NULL cose as ZERO (0)
        CASE UPPER(TRIM(prd_line))                                      -- updated low cardinality columns with full names
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other Sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'n/a'
            END as prd_line,
        CAST(prd_start_dt AS DATE) as prd_start_dt,                     -- updated the datatype for date
        CAST(lead(prd_start_dt) over (partition by prd_key order by prd_start_dt) - 1 AS DATE) as prd_end_dt        -- updated prd_end_dt with correct values
        from [bronze].[crm_prd_info];
        SET @end_time = GETDATE();
        PRINT '>> LOAD DURATION: ' + CAST(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        --crm_sales_details
        --Truncate the table if there is data.
        SET @start_time = GETDATE();
        PRINT '>> Truncating the table silver.crm_sales_details';
        IF EXISTS (SELECT 1 FROM silver.crm_sales_details)
        TRUNCATE TABLE silver.crm_sales_details;
        -- loading data into silver.crm_sales_details table
        PRINT '>> Loading the table silver.crm_sales_details';
        INSERT INTO silver.crm_sales_details(
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )
        select
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        CASE WHEN sls_order_dt <= 0 OR LEN(sls_order_dt)!=8 THEN NULL       -- handling bad date
            ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
        END as sls_order_dt,
        CASE WHEN sls_ship_dt <= 0 OR LEN(sls_ship_dt)!=8 THEN NULL
            ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
        END as sls_ship_dt,
        CASE WHEN sls_due_dt <= 0 OR LEN(sls_due_dt)!=8 THEN NULL
            ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
        END as sls_due_dt,
        CASE WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)     --correcting the sales values
            THEN sls_quantity * ABS(sls_price)                              
            ELSE sls_sales
        END AS sls_sales,
        sls_quantity,
        CASE WHEN sls_price IS NULL or sls_price <= 0                       -- correcting the sales_price values
            THEN sls_price / NULLIF(sls_quantity,0)
            WHEN sls_price <= 0 THEN ABS(sls_price)
            ELSE sls_price
        END AS sls_price
        from bronze.crm_sales_details;
        SET @end_time = GETDATE();
        PRINT '>> LOAD DURATION: ' + CAST(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        PRINT '------------------------------------------------';
		PRINT 'Loading ERP Tables';
		PRINT '------------------------------------------------';

        --erp_cust_az12
        --Truncate the table if there is data.
        SET @start_time = GETDATE();
        PRINT '>> Truncating the table silver.erp_cust_az12';
        IF EXISTS (SELECT 1 FROM silver.erp_cust_az12)
        TRUNCATE TABLE silver.erp_cust_az12;
        -- loading data into silver.erp_cust_az12 table
        PRINT '>> Loading the table silver.erp_cust_az12';
        INSERT INTO silver.erp_cust_az12 (
            cid,
            bdate,
            gen
        )
        select
        CASE WHEN LEN(cid) > 10 THEN SUBSTRING(TRIM(cid),4,LEN(cid))    -- match the cid with cust_key in cust_info
            ELSE cid
        END as cid,
        CASE WHEN bdate > getdate() then NULL                           -- removing invalid date
            else bdate
        end as bdate,
        CASE WHEN UPPER(TRIM(REPLACE(gen,CHAR(13),''))) IN ('F','FEMALE') THEN 'Female'     --data standardization
            WHEN  UPPER(TRIM(REPLACE(gen,CHAR(13),''))) IN ('M','MALE') THEN 'Male'
            else 'n/a'
        END as gen
        from bronze.erp_cust_az12;
        SET @end_time = GETDATE();
        PRINT '>> LOAD DURATION: ' + CAST(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        --erp_loc_a101
        --Truncate the table if there is data.
        SET @start_time = GETDATE();
        PRINT '>> Truncating the table silver.erp_loc_a101';
        IF EXISTS (SELECT 1 FROM silver.erp_loc_a101)
        TRUNCATE TABLE silver.erp_loc_a101;
        -- loading data into silver.erp_loc_a101 table
        PRINT '>> Loading the table silver.erp_loc_a101';
        INSERT INTO silver.erp_loc_a101(
            cid,
            cntry
        )
        select 
        REPLACE(cid,'-','') as cid_new,
        case when UPPER(TRIM(REPLACE(cntry,CHAR(13),''))) in ('US','UNITED STATES','USA') then 'United States'
            when UPPER(TRIM(REPLACE(cntry,CHAR(13),''))) in ('GERMANY','DE') then 'Germany'
            when UPPER(TRIM(REPLACE(cntry,CHAR(13),''))) in ('FRANCE') then 'France'
            when UPPER(TRIM(REPLACE(cntry,CHAR(13),''))) in ('AUSTRALIA') then 'Australia'
            when UPPER(TRIM(REPLACE(cntry,CHAR(13),''))) in ('UNITED KINGDOM') then 'United Kingdom'
            when UPPER(TRIM(REPLACE(cntry,CHAR(13),''))) in ('CANADA') then 'Canada'
            else 'n/a'
        end as cntry
        from bronze.erp_loc_a101;
        SET @end_time = GETDATE();
        PRINT '>> LOAD DURATION: ' + CAST(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        --erp_px_cat_g1v2
        --Truncate the table if there is data.
        SET @start_time = GETDATE();
        PRINT '>> Truncating the table silver.erp_px_cat_g1v2';
        IF EXISTS (SELECT 1 FROM silver.erp_px_cat_g1v2)
        TRUNCATE TABLE silver.erp_px_cat_g1v2;
        -- loading data into silver.erp_px_cat_g1v2 table
        PRINT '>> Loading the table silver.erp_px_cat_g1v2';
        INSERT INTO silver.erp_px_cat_g1v2(
            id,
            cat,
            sub_cat,
            maintenance
        )
        select 
        id,
        cat,
        sub_cat,
        REPLACE(maintenance,char(13),'') as maintenace
        from bronze.erp_px_cat_g1v2;
        SET @end_time = GETDATE();
        PRINT '>> LOAD DURATION: ' + CAST(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @batch_end_time = GETDATE();
        PRINT '=========================================='
		PRINT 'Loading Silver Layer is Completed';
        PRINT '>> BATCH LOAD DURATION: ' + CAST(DATEDIFF(second,@batch_start_time,@batch_end_time) as NVARCHAR) + ' seconds';
        PRINT '=========================================='

    END TRY
    BEGIN CATCH
        PRINT '=========================================='
		PRINT 'ERROR OCCURED DURING LOADING SILVER LAYER'
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
    END CATCH
END
