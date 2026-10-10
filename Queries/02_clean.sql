/** 02_clean.sql - Seattle Building Permit Cycle-Time Analysis
 *  Purpose: build the analysis table: one row per issued permit with a trustworthy cycle time.
 *  Input:   permits_raw (191,830 rows, loaded by 00_load.sql from Building_Permits_20260729.csv).
 *  Output:  permits_clean (133,560 rows): typed dates, cycle_days, post_issue_stage, five review-timing columns.
 *  Run:     after 00_load and 01_profile; reruns top to bottom (Block A builds a diagnostic table, Block D replaces it).
 *  Author:  Peter Jeong. Last full rerun: 2026-09-25. **/

USE seattle_building_permit;

DROP TABLE IF EXISTS permits_clean;

/** Block A: Unfiltered build for diagnostics. **/
CREATE TABLE permits_clean AS 
SELECT
	PermitNum
	,PermitClassMapped
	,PermitTypeMapped
	,PermitTypeDesc
	,StatusCurrent
	,CAST(AppliedDate AS DATE) AS applied_date
	,CAST(IssuedDate AS DATE)  AS issued_date
	,DATEDIFF(CAST(IssuedDate AS DATE), CAST(AppliedDate AS DATE))    AS cycle_days
FROM permits_raw
WHERE AppliedDate IS NOT NULL AND IssuedDate IS NOT NULL;

/** Block A verification **/ 
SELECT COUNT(*) FROM permits_clean;
SELECT MIN(cycle_days) AS min_days, MAX(cycle_days) AS max_days FROM permits_clean;
SELECT COUNT(*) FROM permits_clean WHERE cycle_days < 0;
/** 137,375. -699, 6,226. 14. 14 negative cycle_days (issued before applied). **/

/** Block B: date-integrity checks. Negatives, long tail, and applied-year volume. **/
SELECT
	PermitNum
	,StatusCurrent
	,PermitTypeMapped
	,applied_date
	,issued_date
	,cycle_days
FROM permits_clean
WHERE cycle_days < 0
ORDER BY cycle_days ASC;

SELECT
	PermitNum
	,StatusCurrent
	,PermitTypeMapped
	,applied_date
	,issued_date
	,cycle_days
FROM permits_clean
ORDER BY cycle_days DESC LIMIT 20;

/** Negatives: 14, all Building; 11 applied 2003-2006, 3 applied 2018-2022.
	Long tail: 16 of 20 rows applied 1988-1994, issued 2004-05 (migration stamp).
	The 11 old negatives and the 16 tail rows are all in the 606xxxx-613xxxx PermitNum block.
	How the 14 negatives leave in Block D: 8 applied before 2006 go with the year cutoff;
	the other 6 (three applied 2006, three 2018-2022) go with the cycle_days >= 0 filter. **/

SELECT
	YEAR(applied_date) AS applied_year
	,COUNT(*) AS permits
	,ROUND(AVG(cycle_days), 0) AS avg_days
FROM permits_clean
GROUP BY applied_year
ORDER BY applied_year; 
/** 2005 is the ramp year (388 to 3,059). 2006 is the first full year observed by the current system. 
    Therefore, applied before 2006 excluded. 
    Migration-stamped dates, avg_days decays 6,226 to 116 into 2004-05 stamp window.
    -3,809 rows, 2.8% 
    Applied years 2025-2026 are incomplete cohorts, only already-issued permits present, flag or drop the last 12 months in 
    03_analysis. Done in 03 Block G1: 2024 read with caution, 2025-2026 as a floor. **/

/** Block C: raw-format checks. Every number column is text in permits_raw; check commas, decimals,
 *  and magnitude before choosing a CAST. **/

SELECT EstProjectCost FROM permits_raw WHERE EstProjectCost IS NOT NULL LIMIT 5;
/** Cost is text with thousands separators ('214,000'). Plain CAST stops at the comma and returns 214,
 *  so REPLACE the commas first. Values carry cents -> DECIMAL, not UNSIGNED. **/

SELECT
	SUM(DaysOutCorrections LIKE '%,%')  AS doc
	,SUM(NumberReviewCycles LIKE '%,%')  AS nrc
	,SUM(TotalDaysPlanReview LIKE '%,%') AS tdpr
	,SUM(DaysPlanReviewCity LIKE '%,%')  AS dprc
FROM permits_raw;
/** 1,251. 0. 562. 215. Day columns carry commas once >= 1,000 -> REPLACE. NumberReviewCycles is clean.
 *  Day columns also carry half-days ('387.5') and TotalDaysPlanReview has negatives -> DECIMAL(10,1);
 *  UNSIGNED would silently flip negatives into huge positives. **/

SELECT
	EstProjectCost
	,CAST(REPLACE(EstProjectCost, ',', '') AS UNSIGNED) AS est_project_cost
FROM permits_raw
WHERE EstProjectCost IS NOT NULL
ORDER BY est_project_cost DESC
LIMIT 5;

SELECT PermitNum, PermitTypeDesc, LEFT(Description, 60) AS descr, EstProjectCost
FROM permits_raw
WHERE CAST(REPLACE(EstProjectCost, ',', '') AS UNSIGNED) >= 1000000000;
/** Six rows >= $1B in raw, three projects plus one outlier: $25B CN+DM pair for a 5-story mixed-use (= $25M with
 *  three extra zeros); $1B CN+DM pair with a blank description; $3.3B tenant alteration ending in 555;
 *  $1.44B for a 175,000 GSF surgical building (~$8,000/sq ft, implausible but unverified).
 *  Max value exceeds 999,999,999 -> DECIMAL(14,2). None of the six survive the Block D scope filter (see Block H).
 *  Both queries raise 872 warnings from CAST ... AS UNSIGNED on raw text; read-only check, the build uses DECIMAL. **/

/** Block D: final table **/
/** Exclusions (evidence in Block B):
 *  - applied before 2006-01-01: -3,809 (2.8%), pre-migration dates
 *  - negative cycle_days: -6 after the year cutoff, issued before applied is impossible **/

DROP TABLE IF EXISTS permits_clean;

CREATE TABLE permits_clean AS 
SELECT
	PermitNum
	,PermitClassMapped
	,PermitTypeMapped
	,PermitTypeDesc
	,StatusCurrent
	,CAST(AppliedDate AS DATE) AS applied_date
	,CAST(IssuedDate AS DATE)  AS issued_date
	,DATEDIFF(CAST(IssuedDate AS DATE), CAST(AppliedDate AS DATE))    AS cycle_days
	,CAST(REPLACE(DaysOutCorrections, ',','') AS DECIMAL(10,1))   AS days_out_corrections
	,CAST(NumberReviewCycles AS UNSIGNED)   AS number_review_cycles
	,CAST(REPLACE(TotalDaysPlanReview, ',','') AS DECIMAL(10,1))  AS total_days_plan_review
	,CAST(REPLACE(DaysPlanReviewCity, ',','') AS DECIMAL(10,1))   AS days_plan_review_city
	,CAST(REPLACE(EstProjectCost, ',', '') AS DECIMAL(14,2)) AS est_project_cost
	,CASE 
		WHEN StatusCurrent IN ('Completed','Expired', 'Closed', 'Approved to Occupy') THEN 'finished'
		WHEN StatusCurrent IN ('Issued', 'Inspections Completed', 'Phase Issued') THEN 'live'
		WHEN StatusCurrent IN ('Canceled', 'Withdrawn') THEN 'abandoned'
		ELSE 'contradiction'
	END AS post_issue_stage
FROM permits_raw
WHERE 
	AppliedDate IS NOT NULL AND 
	IssuedDate IS NOT NULL AND 
	DATEDIFF(CAST(IssuedDate AS DATE), CAST(AppliedDate AS DATE)) >= 0 AND 
	CAST(AppliedDate AS DATE) >= '2006-01-01';

SELECT COUNT(*) FROM permits_clean;
SELECT MIN(cycle_days) AS min_days, MAX(cycle_days) AS max_days FROM permits_clean;
SELECT COUNT(*) FROM permits_clean WHERE cycle_days < 0;
/** 133,560. 0, 4,737. 0. **/

/** Block E: status distribution on the scoped table. 
 * Prediction: 80% completed, 10% expired, 5% closed, 3% issued, and 1% withdrawn **/
SELECT 
	StatusCurrent
	,COUNT(*) AS permits
	,ROUND(COUNT(*)/(SELECT COUNT(*) FROM permits_clean) * 100, 1) as pct
FROM permits_clean
GROUP BY StatusCurrent
ORDER BY permits DESC;

/** 83.3% completed, 9.5% expired, 6% issued, 0.5% closed, 0.3% canceled, 0.3% withdrawn, 0.1% inspections completed. 
 * Completed rose after clean up because 58k rows of ghost data were removed, so the denominator shrank. **/

/** Block F: map StatusCurrent to a post-issuance stage for Tableau.
 * Every row here is issued, so the 17 statuses collapse to 4 buckets by what happened after issuance.
 * Decisions: 
 * 	- Reviews Completed (12) -> contradiction. In raw, 449 of 461 Reviews Completed rows have no IssuedDate
 * 	  (checked against the CSV 2026-09-25), so it is a pre-issuance status; on an issued row it contradicts the dates.
 * 	- Canceled + Withdrawn (788) -> abandoned. Issued then dropped; cycle time is real, kept in the buckets.
 * 	- 8 pre-issuance statuses on issued rows (68, incl. the 12 above) -> contradiction via ELSE. Data error, kept and
 * 	  flagged; 03 decides in/out.
 * 	- Risk: ELSE hides new or misspelled statuses. Verification GROUP BY below must match the paper tally. **/

SELECT post_issue_stage, COUNT(*) AS permits
FROM permits_clean
GROUP BY post_issue_stage 
ORDER BY post_issue_stage;
/** Finished 124,591. Live 8,113. Abandoned 788. Contradiction 68. Total 133,560. **/

/** Block G: coverage of review-timing columns on the scoped universe. **/

SELECT
	COUNT(*) AS total
	,COUNT(DaysOutCorrections) AS has_days_out_corrections
	,COUNT(TotalDaysPlanReview) AS has_total_plan_review
	,COUNT(DaysPlanReviewCity) AS has_plan_review_city
	,COUNT(NumberReviewCycles) AS has_review_cycles
	,COUNT(EstProjectCost) AS has_est_cost
	,COUNT(DaysInitialPlanReview) AS has_initial_plan_review
	,COUNT(DaysIssuePermitCity) AS has_issue_permit_city
FROM permits_raw pr
JOIN permits_clean pc ON pr.PermitNum = pc.PermitNum;
/** 133,560 total. DaysOutCorrections 132,187 (99.0%) = NumberReviewCycles. TotalDaysPlanReview 31,441 (23.5%)
 *  = DaysPlanReviewCity. EstProjectCost 122,351 (91.6%). DaysInitialPlanReview 29,919. DaysIssuePermitCity 7,353 (5.5%).
 *  Identical counts = identical populations. Carried into permits_clean: the first five.
 *  Skipped: DaysInitialPlanReview (a subset of TotalDaysPlanReview), DaysIssuePermitCity (5.5% coverage). **/

SELECT
	SUM(DaysOutCorrections = '') AS empty_string
	,SUM(DaysOutCorrections = 0) AS zero
	,SUM(DaysOutCorrections > 0) AS positive
FROM permits_raw pr
JOIN permits_clean pc ON pr.PermitNum = pc.PermitNum;
/** 0. 108,365. 23,822. (Remaining 1,373 are NULL.) Zero vs missing: is a 0 a real "no corrections" or a blank?
 *  Answered by the plan-review split below. **/

SELECT
	(TotalDaysPlanReview IS NOT NULL) AS had_plan_review
	,SUM(DaysOutCorrections > 0) AS positive_corrections
	,SUM(DaysOutCorrections = 0) AS zero_corrections
	,COUNT(*) AS permits
FROM permits_raw pr
JOIN permits_clean pc ON pr.PermitNum = pc.PermitNum 
GROUP BY had_plan_review;
/** 23,794 of the 23,822 positives sit inside the 31,441 plan-reviewed permits (28 outside = noise).
 *  Zeros outside plan review are structural (no review, so no corrections), so the column is trusted.
 *  Correction (03_analysis Block D3): corrections were not tracked before ~2017 and old rows were filled
 *  with 0. Zeros mean "no corrections" only for applied 2018+.
 *  76% of plan-reviewed permits (23,794 / 31,441) had at least one correction round. **/

/** Block H: final verification. **/
SELECT
	COUNT(*)                            AS rows_total
	,MAX(days_out_corrections)          AS max_doc
	,SUM(total_days_plan_review < 0)    AS negative_plan_review
	,MAX(est_project_cost)              AS max_cost
FROM permits_clean;

/** Max cost is $458M, not $25B. Exclude the 81 negative plan review in 03. Max days out of corrections of 7,624 is probably a migration error. **/
