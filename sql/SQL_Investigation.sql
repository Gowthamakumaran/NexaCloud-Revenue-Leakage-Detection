Create database nexacloud_revenue;
use nexacloud_revenue;

-- How much revenue has NexaCloud invoiced?
select count(*) as total_invoices , round(sum(invoice_amount), 1) as total_invoiced_revenue, 
round(avg(invoice_amount), 1) as average_invoice_value from invoices;

-- How much money was actually collected?
select count(*) as payment_count, round(sum(payment_amount), 2) as total_payment_amount 
from payments where payment_status in ('success', 'partial');

-- What is the difference between total invoiced revenue and actual collected payments?
select
	(select round(sum(invoice_amount), 1) from invoices) as total_invoiced_revenue,
	(select round(sum(payment_amount), 2) from payments 
    where payment_status in ('success', 'partial') ) as total_payment_amount,
    ((select round(sum(invoice_amount), 1) from invoices)-(select round(sum(payment_amount), 2) from payments 
    where payment_status in ('success', 'partial') )) as initial_revenue_gap;

-- How many invoices are marked Paid, Partially Paid, Unpaid, Overdue, or Cancelled, and what is their total invoice value?
select invoice_status, count(invoice_id) as no_of_invoices , 
round(sum(invoice_amount), 2) as total_invoiced_amount from invoices
group by invoice_status order by total_invoiced_amount;

-- Which payment methods account for the most successfully collected money?
select payment_method, count(payment_id) as no_of_payments, 
round(sum(payment_amount), 2) as total_payment_amount 
from payments where payment_status in ('success', 'partial')
group by payment_method
order by total_payment_amount desc;

-- Count overdue invoices and calculate their value
select count(invoice_id) as no_of_overdue_invoices , round(sum(invoice_amount), 2) as total_overdue_invoice_amount from invoices where invoice_status = 'Overdue';

-- Calculate overdue days for each invoice
SELECT invoice_id, due_date, DATEDIFF(CURDATE(), due_date) AS days_overdue
FROM invoices WHERE invoice_status = 'Overdue'
order by days_overdue desc;

-- Group overdue invoices by aging bucket
select 
	case 
		when datediff(curdate(), due_date) between 0 and 30 then '0-30 Days'
        when datediff(curdate(), due_date) between 31 and 60 then '31-60 Days'
        when datediff(curdate(), due_date) between 61 and 90 then '61-90 Days'
        else 'above 90 days'
     END as aging_bucket,
     count(invoice_id) as no_of_invoices,
     sum(invoice_amount) as total_inoice_value
from invoices where invoice_status = 'overdue' and due_date < curdate()
group by aging_bucket order by aging_bucket;    

-- Find customers with the highest overdue invoice value
SELECT C.customer_id, C.company_name, COUNT(I.invoice_id) AS no_of_invoices, ROUND(SUM(I.invoice_amount), 2) AS total_overdue_value
FROM customers C JOIN contracts S ON C.customer_id = S.customer_id
JOIN invoices I ON I.contract_id = S.contract_id
WHERE I.invoice_status = 'Overdue' AND I.due_date < CURDATE()
GROUP BY C.customer_id, C.company_name ORDER BY total_overdue_value DESC LIMIT 10;

-- How many payments failed, and what was their total attempted value?
select count(payment_status) as total_failed_attempt , sum(payment_amount) as failed_payment_amount
from payments where payment_status = 'failed' ;

-- What are the main reasons for payment failures?
select failure_reason, count(payment_id) as failed_payment_count , round(sum(payment_amount), 2) as failed_payment_amount
from payments where payment_status = 'Failed'
group by failure_reason order by failed_payment_count desc;

-- Which payment methods have the highest failure rates?
select payment_method, count(payment_id) as total_payments, 
sum(case when payment_status = 'Failed' then 1 else 0 end )  failed_payments,
round(
	sum(case
			when payment_status = 'Failed' then 1 else 0 end) * 100.0 / count(payment_id),
            2
            ) as failure_rate_pct
from payments group by payment_method order by failure_rate_pct desc;

-- Which customers have the largest value of failed payment attempts?
select C.customer_id, C.company_name, count(P.payment_status) as total_failed_attempt, 
round(sum(P.payment_amount), 2) as failed_payment_amount from Payments P 
join invoices I on P.invoice_id = I.invoice_id
join contracts M on M.contract_id = I.contract_id
join customers C on M.customer_id = C.customer_id
where payment_status = 'failed' group by C.customer_id, C.company_name
order by failed_payment_amount desc limit 10;
 
select * from contracts;
select * from customers;
select * from invoices;
select * from payments;
select * from refunds;

-- Which contracts have an approved discount different from the standard discount?
select contract_id, customer_id, standard_discount_pct, approved_discount_pct, 
approved_discount_pct - standard_discount_pct as discount_difference
from contracts where standard_discount_pct != approved_discount_pct 
order by discount_difference desc;

-- Are any invoice discounts higher than the discount approved in the corresponding contract?
SELECT I.invoice_id, I.contract_id, ROUND(I.discount_amount * 100.0 / NULLIF(I.base_amount, 0), 2)
AS invoice_discount_percentage, C.approved_discount_pct FROM contracts C JOIN invoices I
ON C.contract_id = I.contract_id WHERE I.discount_amount * 100.0 / NULLIF(I.base_amount, 0) > C.approved_discount_pct;

-- Which customers account for the largest estimated excess discounts?
SELECT
    C.customer_id,
    C.company_name,
    COUNT(DISTINCT I.invoice_id) AS affected_invoices,
    ROUND( SUM( GREATEST( I.discount_amount -
                (I.base_amount * CT.approved_discount_pct / 100.0),
                0) ), 2 ) AS estimated_excess_discount
FROM customers C JOIN contracts CT
ON C.customer_id = CT.customer_id
JOIN invoices I ON CT.contract_id = I.contract_id
GROUP BY C.customer_id, C.company_name
HAVING estimated_excess_discount > 0
ORDER BY estimated_excess_discount DESC
LIMIT 10;

-- How many refunds exist under each refund status, and what is their total value?
select refund_status, count(refund_id) as refund_count, round(sum(refund_amount), 2) as Total_refund_amount
from refunds group by refund_Status;

-- Which refund reasons account for the highest refund amounts?
select refund_reason, count(refund_id) as refund_count, round(sum(refund_amount), 2) as Total_refund_amount
from refunds group by refund_reason order by total_refund_amount desc;

-- Which payments have more than one refund record?
select payment_id, count(refund_id) as refund_count, round(sum(refund_amount), 2) as Total_refund_amount
from refunds group by payment_id having count(*) > 1;

-- Are any payments associated with total refund amounts exceeding the original payment amount?
select P.payment_id, P.payment_amount as original_payment_amount, R.total_refund_amount,
round(R.total_refund_amount - P.payment_amount, 2) AS excess_refund_amount from payments P
join( select payment_id, sum(refund_amount) as total_refund_amount from refunds 
where refund_status = 'success' group by payment_id ) R on P.payment_id = R.payment_id
WHERE R.total_refund_amount > P.payment_amount ORDER BY excess_refund_amount DESC;

-- What is the outstanding balance for each invoice?
SELECT I.invoice_id, I.invoice_status, I.invoice_amount, COALESCE(P.total_paid_amount, 0) AS total_paid_amount, 
ROUND( GREATEST(I.invoice_amount - COALESCE(P.total_paid_amount, 0), 0), 2) AS outstanding_amount,
    ROUND( GREATEST(COALESCE(P.total_paid_amount, 0) - I.invoice_amount, 0), 2 ) AS excess_payment_amount
FROM invoices I
LEFT JOIN ( SELECT
        invoice_id, SUM(payment_amount) AS total_paid_amount FROM payments WHERE payment_status IN ('SUCCESS', 'PARTIAL')
GROUP BY invoice_id ) P ON I.invoice_id = P.invoice_id
WHERE I.invoice_status <> 'Cancelled' ORDER BY outstanding_amount DESC;

-- Which customers have the highest outstanding balances?
SELECT
    C.customer_id,
    C.company_name,
    COUNT(I.invoice_id) AS invoice_count,
    ROUND(SUM(GREATEST(I.invoice_amount - COALESCE(P.total_paid, 0), 0)), 2) AS outstanding_amount
FROM customers C JOIN contracts CT ON C.customer_id = CT.customer_id JOIN invoices I ON CT.contract_id = I.contract_id
LEFT JOIN (
    SELECT invoice_id, SUM(payment_amount) AS total_paid
    FROM payments WHERE payment_status IN ('SUCCESS', 'PARTIAL')
    GROUP BY invoice_id
) P ON I.invoice_id = P.invoice_id
WHERE I.invoice_status <> 'Cancelled' GROUP BY C.customer_id, C.company_name ORDER BY outstanding_amount DESC LIMIT 10;

-- Which contracts have the highest outstanding balances?
SELECT
    CT.contract_id,
    CT.customer_id,
    CT.plan,
    COUNT(I.invoice_id) AS invoice_count,
    ROUND(SUM(GREATEST(I.invoice_amount - COALESCE(P.total_paid, 0), 0)), 2) AS outstanding_amount
FROM contracts CT
JOIN invoices I ON CT.contract_id = I.contract_id
LEFT JOIN (
    SELECT invoice_id, SUM(payment_amount) AS total_paid
    FROM payments
    WHERE payment_status IN ('SUCCESS', 'PARTIAL')
    GROUP BY invoice_id
) P ON I.invoice_id = P.invoice_id
WHERE I.invoice_status <> 'Cancelled'
GROUP BY CT.contract_id, CT.customer_id, CT.plan
ORDER BY outstanding_amount DESC
LIMIT 10;

-- Which regions have the highest outstanding balances?
SELECT
    C.region,
    COUNT(DISTINCT I.invoice_id) AS invoice_count,
    ROUND(SUM(GREATEST(I.invoice_amount - COALESCE(P.total_paid, 0), 0)), 2) AS outstanding_amount
FROM customers C
JOIN contracts CT ON C.customer_id = CT.customer_id
JOIN invoices I ON CT.contract_id = I.contract_id
LEFT JOIN (
    SELECT invoice_id, SUM(payment_amount) AS total_paid
    FROM payments
    WHERE payment_status IN ('SUCCESS', 'PARTIAL')
    GROUP BY invoice_id
) P ON I.invoice_id = P.invoice_id
WHERE I.invoice_status <> 'Cancelled'
GROUP BY C.region
ORDER BY outstanding_amount DESC;

-- Identify invoices with successful refunds
SELECT
    P.invoice_id,
    SUM(P.payment_amount) AS successful_payment_amount,
    COALESCE(R.total_refund, 0) AS successful_refund_amount
FROM payments P
LEFT JOIN (
    SELECT payment_id, SUM(refund_amount) AS total_refund
    FROM refunds
    WHERE refund_status = 'SUCCESS'
    GROUP BY payment_id
) R ON P.payment_id = R.payment_id
WHERE P.payment_status IN ('SUCCESS', 'PARTIAL')
GROUP BY P.invoice_id, R.total_refund;

-- Identify reversed payments and their value
SELECT payment_method, COUNT(payment_id) AS reversed_payment_count,
    ROUND(SUM(payment_amount), 2) AS reversed_payment_amount
FROM payments WHERE payment_status = 'REVERSED'
GROUP BY payment_method ORDER BY reversed_payment_amount DESC;

-- Identify invoices with the highest potential outstanding exposure
SELECT I.invoice_id, I.contract_id, I.invoice_status, I.invoice_amount, I.due_date,
    DATEDIFF(CURDATE(), I.due_date) AS days_overdue FROM invoices I
WHERE I.invoice_status IN ('OVERDUE', 'UNPAID', 'PARTIALLY PAID')
ORDER BY I.invoice_amount DESC LIMIT 20;

-- Calculate the adjusted outstanding balance
WITH refund_summary AS (
    SELECT
        payment_id,
        SUM(refund_amount) AS total_refund
    FROM refunds
    WHERE refund_status = 'SUCCESS'
    GROUP BY payment_id
),
payment_summary AS (
    SELECT P.invoice_id, 
    SUM(
            CASE
                WHEN P.payment_status IN ('SUCCESS', 'PARTIAL')
                THEN P.payment_amount - COALESCE(R.total_refund, 0)
                ELSE 0
            END
        ) AS net_collected
    FROM payments P LEFT JOIN refund_summary R ON P.payment_id = R.payment_id GROUP BY P.invoice_id
)
SELECT
    I.invoice_id, I.invoice_amount, COALESCE(P.net_collected, 0) AS net_collected,
    ROUND( GREATEST(I.invoice_amount - COALESCE(P.net_collected, 0), 0), 2 ) AS adjusted_outstanding
FROM invoices I LEFT JOIN payment_summary P ON I.invoice_id = P.invoice_id
WHERE I.invoice_status <> 'Cancelled' ORDER BY adjusted_outstanding DESC;

-- Understand the ground-truth data
SELECT leakage_type, COUNT(*) AS record_count FROM leakage_ground_truth
GROUP BY leakage_type ORDER BY record_count DESC;

-- What is the reference amount for each leakage type?
SELECT leakage_type, COUNT(*) AS record_count, ROUND(SUM(reference_amount), 2) AS total_reference_amount, ROUND(AVG(reference_amount), 2) AS average_reference_amount
FROM leakage_ground_truth GROUP BY leakage_type ORDER BY total_reference_amount DESC;

-- Are there records with zero reference amounts?
SELECT leakage_type, COUNT(*) AS zero_amount_records
FROM leakage_ground_truth WHERE reference_amount = 0 GROUP BY leakage_type;

-- Validate actual revenue leakage
SELECT leakage_type, COUNT(*) AS record_count, ROUND(SUM(reference_amount), 2) AS confirmed_leakage_amount
FROM leakage_ground_truth GROUP BY leakage_type ORDER BY confirmed_leakage_amount DESC;

SELECT G.leakage_type, COUNT(*) AS matched_records, ROUND(SUM(G.reference_amount), 2) AS confirmed_leakage_amount
FROM leakage_ground_truth G LEFT JOIN invoices I ON G.record_id = I.invoice_id GROUP BY G.leakage_type;

SELECT
    COUNT(*) AS total_leakage_records,
    COUNT(i.invoice_id) AS matched_invoice_records,
    COUNT(*) - COUNT(i.invoice_id) AS unmatched_records,
    ROUND(
        100.0 * COUNT(i.invoice_id) / COUNT(*), 2
    ) AS match_percentage
FROM leakage_ground_truth g
LEFT JOIN invoices i
    ON g.record_id = i.invoice_id;
    
    SELECT
    g.record_id,
    g.leakage_type,
    g.reference_amount
FROM leakage_ground_truth g
LEFT JOIN invoices i
    ON g.record_id = i.invoice_id
WHERE i.invoice_id IS NULL
ORDER BY g.leakage_type;
    
SELECT
    COUNT(*) AS total_refund_anomaly_records,
    COUNT(p.payment_id) AS matched_payment_records,
    COUNT(*) - COUNT(p.payment_id) AS unmatched_payment_records,
    ROUND(
        100.0 * COUNT(p.payment_id) / COUNT(*), 2
    ) AS payment_match_percentage
FROM leakage_ground_truth g
LEFT JOIN payments p
    ON g.record_id = p.payment_id
WHERE g.leakage_type = 'Refund Anomaly';

SELECT
    g.record_id,
    g.reference_amount,
    p.payment_amount,
    p.payment_status,
    ROUND(g.reference_amount - p.payment_amount, 2)
        AS amount_difference
FROM leakage_ground_truth g
JOIN payments p
    ON g.record_id = p.payment_id
WHERE g.leakage_type = 'Refund Anomaly'
ORDER BY g.reference_amount DESC;

SELECT
    g.record_id,
    g.reference_amount,
    p.payment_amount,
    p.payment_status,
    COALESCE(r.refund_count, 0) AS refund_count,
    COALESCE(r.successful_refund_amount, 0)
        AS successful_refund_amount,
    ROUND(
        g.reference_amount -
        COALESCE(r.successful_refund_amount, 0), 2
    ) AS reference_vs_refund_difference
FROM leakage_ground_truth g
JOIN payments p
    ON g.record_id = p.payment_id
LEFT JOIN (
    SELECT
        payment_id,
        COUNT(*) AS refund_count,
        SUM(
            CASE
                WHEN refund_status = 'SUCCESS'
                THEN refund_amount
                ELSE 0
            END
        ) AS successful_refund_amount
    FROM refunds
    GROUP BY payment_id
) r
    ON p.payment_id = r.payment_id
WHERE g.leakage_type = 'Refund Anomaly'
ORDER BY g.reference_amount DESC;


SELECT
    r.refund_status,
    COUNT(*) AS refund_records,
    ROUND(SUM(r.refund_amount), 2) AS total_refund_amount
FROM leakage_ground_truth g
JOIN payments p
    ON g.record_id = p.payment_id
JOIN refunds r
    ON p.payment_id = r.payment_id
WHERE g.leakage_type = 'Refund Anomaly'
GROUP BY r.refund_status
ORDER BY refund_records DESC;

SELECT
    g.record_id,
    g.reference_amount,
    p.payment_amount,
    COALESCE(r.completed_refund_amount, 0)
        AS completed_refund_amount,
    ROUND(
        g.reference_amount -
        COALESCE(r.completed_refund_amount, 0), 2
    ) AS amount_difference
FROM leakage_ground_truth g
JOIN payments p
    ON g.record_id = p.payment_id
LEFT JOIN (
    SELECT
        payment_id,
        SUM(refund_amount) AS completed_refund_amount
    FROM refunds
    WHERE refund_status = 'COMPLETED'
    GROUP BY payment_id
) r
    ON p.payment_id = r.payment_id
WHERE g.leakage_type = 'Refund Anomaly'
ORDER BY ABS(
    g.reference_amount -
    COALESCE(r.completed_refund_amount, 0)
) DESC;

SELECT
    COUNT(*) AS total_records,

    ROUND(SUM(g.reference_amount), 2)
        AS total_reference_amount,

    ROUND(SUM(p.payment_amount), 2)
        AS total_payment_amount,

    ROUND(SUM(r.completed_refund_amount), 2)
        AS total_completed_refunds,

    SUM(
        CASE
            WHEN ABS(
                g.reference_amount - (p.payment_amount * 0.20)
            ) < 0.02
            THEN 1 ELSE 0
        END
    ) AS records_matching_20_percent,

    ROUND(
        AVG(g.reference_amount / NULLIF(p.payment_amount, 0)) * 100,
        2
    ) AS average_reference_percentage

FROM leakage_ground_truth g

JOIN payments p
    ON g.record_id = p.payment_id

LEFT JOIN (
    SELECT
        payment_id,
        SUM(refund_amount) AS completed_refund_amount
    FROM refunds
    WHERE refund_status = 'COMPLETED'
    GROUP BY payment_id
) r
    ON p.payment_id = r.payment_id

WHERE g.leakage_type = 'Refund Anomaly';


SELECT
    leakage_type,
    COUNT(*) AS record_count,
    ROUND(SUM(reference_amount), 2) AS total_reference_amount,
    ROUND(AVG(reference_amount), 2) AS average_reference_amount
FROM leakage_ground_truth
WHERE leakage_type <> 'Refund Anomaly'
GROUP BY leakage_type
ORDER BY total_reference_amount DESC;

SELECT
    leakage_type,
    LEFT(record_id, 3) AS record_prefix,
    COUNT(*) AS record_count,
    ROUND(SUM(reference_amount), 2) AS total_reference_amount
FROM leakage_ground_truth
GROUP BY leakage_type, LEFT(record_id, 3)
ORDER BY leakage_type, record_count DESC;

SELECT
    g.record_id AS invoice_id,
    g.reference_amount,
    i.invoice_amount,
    i.invoice_status,
    COUNT(p.payment_id) AS payment_attempts,
    SUM(
        CASE
            WHEN p.payment_status IN ('SUCCESS', 'PARTIAL')
            THEN 1 ELSE 0
        END
    ) AS successful_payment_attempts,
    ROUND(
        SUM(
            CASE
                WHEN p.payment_status IN ('SUCCESS', 'PARTIAL')
                THEN p.payment_amount
                ELSE 0
            END
        ), 2
    ) AS successful_payment_amount
FROM leakage_ground_truth g
JOIN invoices i
    ON g.record_id = i.invoice_id
LEFT JOIN payments p
    ON i.invoice_id = p.invoice_id
WHERE g.leakage_type = 'Duplicate Payment Pattern'
GROUP BY
    g.record_id,
    g.reference_amount,
    i.invoice_amount,
    i.invoice_status
ORDER BY g.reference_amount DESC;


SELECT
    COUNT(*) AS flagged_invoices,

    SUM(
        CASE WHEN successful_count > 1 THEN 1 ELSE 0 END
    ) AS invoices_with_multiple_successful_payments,

    ROUND(SUM(
        CASE
            WHEN successful_amount > invoice_amount
            THEN successful_amount - invoice_amount
            ELSE 0
        END
    ), 2) AS potential_excess_collection,

    ROUND(SUM(reference_amount), 2)
        AS ground_truth_reference_amount

FROM (
    SELECT
        g.record_id,
        g.reference_amount,
        i.invoice_amount,

        SUM(
            CASE
                WHEN p.payment_status IN ('SUCCESS', 'PARTIAL')
                THEN 1 ELSE 0
            END
        ) AS successful_count,

        SUM(
            CASE
                WHEN p.payment_status IN ('SUCCESS', 'PARTIAL')
                THEN p.payment_amount
                ELSE 0
            END
        ) AS successful_amount

    FROM leakage_ground_truth g
    JOIN invoices i
        ON g.record_id = i.invoice_id
    LEFT JOIN payments p
        ON i.invoice_id = p.invoice_id

    WHERE g.leakage_type = 'Duplicate Payment Pattern'

    GROUP BY
        g.record_id,
        g.reference_amount,
        i.invoice_amount
) x;



SELECT
    g.record_id,
    g.reference_amount,
    i.invoice_amount,
    COUNT(p.payment_id) AS payment_attempts,
    SUM(
        CASE
            WHEN p.payment_status IN ('SUCCESS', 'PARTIAL')
            THEN p.payment_amount
            ELSE 0
        END
    ) AS successful_payment_amount,
    ROUND(
        g.reference_amount -
        GREATEST(
            SUM(
                CASE
                    WHEN p.payment_status IN ('SUCCESS', 'PARTIAL')
                    THEN p.payment_amount
                    ELSE 0
                END
            ) - i.invoice_amount,
            0
        ), 2
    ) AS reference_difference
FROM leakage_ground_truth g
JOIN invoices i ON g.record_id = i.invoice_id
LEFT JOIN payments p ON i.invoice_id = p.invoice_id
WHERE g.leakage_type = 'Duplicate Payment Pattern'
GROUP BY g.record_id, g.reference_amount, i.invoice_amount
HAVING ABS(reference_difference) > 0.01
ORDER BY ABS(reference_difference) DESC;

SELECT
    g.record_id AS invoice_id,
    g.reference_amount,
    i.invoice_amount,
    i.contract_id,
    c.contract_value,
    ROUND(
        i.invoice_amount - c.contract_value, 2
    ) AS invoice_contract_difference
FROM leakage_ground_truth g
JOIN invoices i
    ON g.record_id = i.invoice_id
JOIN contracts c
    ON i.contract_id = c.contract_id
WHERE g.leakage_type = 'Billing Amount Mismatch'
ORDER BY g.reference_amount DESC
LIMIT 30;

describe invoices;

SELECT
    g.record_id AS invoice_id,
    g.reference_amount,
    i.base_amount,
    i.discount_amount,
    i.tax_amount,
    i.invoice_amount,
    ROUND(
        i.base_amount - i.discount_amount + i.tax_amount,
        2
    ) AS calculated_invoice_amount,
    ROUND(
        i.invoice_amount -
        (i.base_amount - i.discount_amount + i.tax_amount),
        2
    ) AS calculation_difference
FROM leakage_ground_truth g
JOIN invoices i
    ON g.record_id = i.invoice_id
WHERE g.leakage_type = 'Billing Amount Mismatch'
ORDER BY g.reference_amount DESC
LIMIT 30;

SELECT
    COUNT(*) AS total_records,
    SUM(
        CASE
            WHEN ABS(
                g.reference_amount -
                (i.base_amount * 0.02)
            ) < 0.02
            THEN 1 ELSE 0
        END
    ) AS records_matching_2_percent,
    ROUND(SUM(g.reference_amount), 2)
        AS total_reference_amount,
    ROUND(SUM(
        ABS(
            i.invoice_amount -
            (i.base_amount - i.discount_amount + i.tax_amount)
        )
    ), 2) AS total_calculation_difference,
    ROUND(
        AVG(g.reference_amount / NULLIF(i.base_amount, 0)) * 100,
        2
    ) AS average_reference_percentage
FROM leakage_ground_truth g
JOIN invoices i
    ON g.record_id = i.invoice_id
WHERE g.leakage_type = 'Billing Amount Mismatch';

SELECT
    g.record_id AS invoice_id,
    g.reference_amount,
    i.base_amount,
    i.discount_amount,
    i.tax_amount,
    i.invoice_amount,
    ROUND(
        i.discount_amount / NULLIF(i.base_amount, 0) * 100,
        2
    ) AS discount_percentage
FROM leakage_ground_truth g
JOIN invoices i
    ON g.record_id = i.invoice_id
WHERE g.leakage_type = 'Unauthorized Discount'
ORDER BY i.discount_amount DESC
LIMIT 30;

DESCRIBE contracts;

SELECT
    g.record_id AS invoice_id,
    i.base_amount,
    i.discount_amount,
    ROUND(
        (i.discount_amount / NULLIF(i.base_amount, 0)) * 100,
        2
    ) AS actual_discount_pct,
    c.approved_discount_pct,
    c.standard_discount_pct
FROM leakage_ground_truth g
JOIN invoices i
    ON g.record_id = i.invoice_id
JOIN contracts c
    ON i.contract_id = c.contract_id
WHERE g.leakage_type = 'Unauthorized Discount'
LIMIT 30;



SELECT
    COUNT(*) AS total_flagged_invoices,

    SUM(
        CASE
            WHEN (i.discount_amount / NULLIF(i.base_amount, 0)) * 100
                 > c.approved_discount_pct
            THEN 1 ELSE 0
        END
    ) AS invoices_exceeding_approval,

    SUM(
        CASE
            WHEN (i.discount_amount / NULLIF(i.base_amount, 0)) * 100
                 <= c.approved_discount_pct
            THEN 1 ELSE 0
        END
    ) AS invoices_within_approval,

    ROUND(SUM(
        GREATEST(
            0,
            i.discount_amount -
            (i.base_amount * c.approved_discount_pct / 100)
        )
    ), 2) AS indicative_excess_discount_amount
FROM leakage_ground_truth g
JOIN invoices i ON g.record_id = i.invoice_id
JOIN contracts c ON i.contract_id = c.contract_id
WHERE g.leakage_type = 'Unauthorized Discount';