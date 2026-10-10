/** 03_analysis.sql - Seattle Building Permit Cycle-Time Analysis
 * Purpose: find cycle-time distributions, trends, bottleneck segments, and headline KPI.
 * Input: permits_clean (built from permits_raw by 02_clean.sql).  
 * Output: no tables. Results recorded as comments under each query.
 * Run: after 00_load, 01_profile, and 02_clean.
 * Percentiles: nearest-rank (ROW_NUMBER + CEIL(p * n)); MySQL 8 has no PERCENTILE_CONT.
 * Author: Peter Jeong. Last full rerun: 2026-10-09. **/

USE seattle_building_permit;

/** Block A: overall cycle-time distribution on permits_clean. 
 * Citywide baseline: the yardstick for every segment below, and evidence for median/p90 over mean.
 * Predictions: median = 60 days, p90 ~ 300 (5x), mean > median (long right tail).
**/

WITH ranked AS (
	SELECT
		cycle_days
		,ROW_NUMBER() OVER (ORDER BY cycle_days) AS rn
		,COUNT(*) OVER () AS n
	FROM permits_clean
)
SELECT
	MAX(n) AS permits
	,MAX(CASE WHEN rn = CEIL(0.5 * n) THEN cycle_days END) AS median_days
	,MAX(CASE WHEN rn = CEIL(0.9 * n) THEN cycle_days END) AS p90_days
	,ROUND(AVG(cycle_days), 0) AS mean_days
FROM ranked;
/** Median = 32, p90 = 251, mean = 94. 
 * Mean 94 ~ 3x median: right-skewed, so median/p90 are the KPIs, not mean.
 * Permits are issued faster than predicted.
 * Long tail is heavier than predicted. p90 = 7.8x median vs. predicted 5x.
 * Half of Seattle's permits are issued within a month, but the slowest 10% wait more than 8 months. 
 * Hypothesis (test in Block B): the fast majority skipped plan review (only 23.5% had it); slow tail comes from the plan-reviewed minority.
**/

/** Block B: test the hypothesis.
 * Purpose: the same median/p90/mean, split by whether the permit went through plan review. If the hypothesis holds,
 * the no-review group will be fast and the plan-reviewed group will carry the tail.
 * Predictions: for no plan review group, median = 5 days and p90 = 32. For plan review group, median = 200 and p90 = 400.
**/

WITH ranked AS (
	SELECT
		cycle_days
		,(total_days_plan_review IS NOT NULL) AS had_plan_review
		,ROW_NUMBER() OVER(PARTITION BY total_days_plan_review IS NOT NULL ORDER BY cycle_days) AS rn
		,COUNT(*) OVER(PARTITION BY total_days_plan_review IS NOT NULL) AS n
	FROM permits_clean
)
SELECT 
	had_plan_review
	,MAX(n) AS permits
	,MAX(CASE WHEN rn = CEIL(0.5 * n) THEN cycle_days END) AS median_days
	,MAX(CASE WHEN rn = CEIL(0.9 * n) THEN cycle_days END) AS p90_days
	,ROUND(AVG(cycle_days), 0) AS mean_days
FROM ranked 
GROUP BY had_plan_review;

/** Had no plan review: median = 7, p90 = 181, and mean = 63.
 * Had plan review : median = 115, p90 = 427, and mean = 193.
 * Scorecard: no-review median HIT (7 vs 5), p90 MISS (181 vs 32); review median MISS (115 vs 200), p90 HIT (427 vs 400). 
 * Plan review splits the typical permit 16x (7 vs. 115 days), the strongest split tested so far.
 * No-review p90 is 181 days. About 10,000 permits that never saw plan review still took 6+ months. 
 * The tail is not only a plan-review problem.
 * Block A hypothesis: half confirmed.
 * Correction (See Block D2): plan-review time not recorded before ~2017, so this split is confounded by era. Valid redo: Block E.
***/

/** Block B2:  
 * Goal: how many permits slower than the citywide p90 (251 days) come from each group? What share of the tail does each group make up?
 * Predictions: no-review share of slow tail = 20% (80/20 split). 
 */

SELECT 
	(total_days_plan_review IS NOT NULL) AS had_plan_review
	,COUNT(*) AS permits
	,SUM(cycle_days > 251) AS slow_permits
	,ROUND(100 * SUM(cycle_days > 251) / COUNT(*), 1) AS pct_of_group_slow
	,ROUND(100 * SUM(cycle_days > 251) / SUM(SUM(cycle_days > 251)) OVER(), 1) AS pct_of_all_slow
FROM permits_clean
GROUP BY had_plan_review;
/** Slow = cycle_days > 251 (citywide p90, Block A).
 * 6,110 + 7,145 = 13,255 slow; shares sum to 100.0. 
 * 6% of no-plan-review group are slow permits. 
 * 22.7% of plan-review group are slow permits.
 * 54% of slow permits had plan review. 46% of slow permits had no plan review.
 * Prediction MISS: 80/20 predicted, 54/46 actual.
 * Rate vs. share: a plan-reviewed permit is ~4x as likely to be slow, but the no-review group is 3x bigger, so the tail splits nearly evenly.
 * Block A hypothesis mostly rejected: plan review is a slight majority of the tail, not the tail.
 * Implication: fixing plan review reaches at most ~half the slow permits; 6,110 slow permits never saw plan review. 
 * Next: Block C by permit type. 
 * Correction (See Block D2): plan-review time not recorded before ~2017, so this split is confounded by era. Valid redo: Block E2. 
**/

/** Block C: median, p90, and slow share by PermitTypeMapped.
 * Purpose: find which permit type drives cycle time. 
 * Block B showed that 6,110 slow permits never saw plan review, and permit type is the next place to look for them.
 * Predictions: demolition permits will have the slowest median because it is the biggest decision. Building permits will have the largest share of the slow tail due to the sheer amount of building permits compared to other permits.
**/

WITH ranked AS (
	SELECT
		PermitTypeMapped
		,cycle_days
		,ROW_NUMBER() OVER(PARTITION BY PermitTypeMapped ORDER BY cycle_days) AS rn
		,COUNT(*) OVER(PARTITION BY PermitTypeMapped) AS n
	FROM permits_clean
)
SELECT
	PermitTypeMapped
	,MAX(n) AS permits
	,MAX(CASE WHEN rn = CEIL(0.5 * n) THEN cycle_days END) AS median_days
	,MAX(CASE WHEN rn = CEIL(0.9 * n) THEN cycle_days END) AS p90_days
	,SUM(cycle_days > 251) AS slow_permits
	,ROUND(100 * SUM(cycle_days > 251) / COUNT(*), 1) AS pct_of_group_slow
	,ROUND(100 * SUM(cycle_days > 251) / SUM(SUM(cycle_days > 251)) OVER(), 1) AS pct_of_all_slow
FROM ranked 
GROUP BY PermitTypeMapped 
ORDER BY pct_of_all_slow  DESC;
/** Permit sum = 133,560. Slow permits sum = 13,255 (matches Block B). Verified.
 * Scorecard:
 * 	- Prediction 1 (Demolition slowest median): MISS, Grading 103 > Demolition 80, but Grading is n = 464 with 46.9% ghost records (F0), so among reliable types Demolition is slowest.
 *  - Prediction 2 (Building largest slow share): HIT, 83.6%. 
 * Percent of all slow permits: 83.6% building, 15.6% demolition, and 0.7% grading.
 * Percent of slow permits per group: 9.1% of building, 17.6% of demolition, and 20.9% of grading.
 * Median days: building 29, demolition 80, grading 103, and roof 0.
 * Share vs. size: Building is 90.8% of permits, but 83.6% of the slow tail (slightly under-represented). Demolition is 8.8% of permits, but 15.6% of the tail (~1.8x over-represented).
 * Roof: 77 permits, median and p90 = 0 (same-day, over-the-counter). Too small to matter. 
 * Permit type is too coarse. Building is 91% of everything, so the 6,110 no-review slow permits are likely inside Building. 
 * Next: Block D splits Building by PermitClassMapped or PermitTypeDesc.
**/

/** Block D: split Building.
**/

/** Block D0: choosing how to split Building (121,280).
 * PermitClassMapped: 3 groups (Residential 84,589 / Non-Residential 33,550 / N/A 3,141). Answers who is building.
 * PermitTypeDesc: 8 groups, 3 large (Addition/Alteration 92,600 / New 22,336 / Tenant Improvment 4,460).
 * Answers what kind of work, closer to whether plan review is triggered.
 * Decision: split by PermitTypeDesc. NONE (304) and blank (22) = unknown type.
 * "Tenant Improvment" is misspelled in source data. Filter must match it. **/
SELECT
	PermitTypeDesc
	,COUNT(*) AS permits
FROM permits_clean
WHERE PermitTypeMapped = 'Building'
GROUP BY PermitTypeDesc
ORDER BY permits DESC;

SELECT
	PermitClassMapped
	,COUNT(*) AS permits
FROM permits_clean
WHERE PermitTypeMapped = 'Building'
GROUP BY PermitClassMapped
ORDER BY permits DESC;

/** Block D1: split Building by PermitTypeDesc.
 * Predictions: 80% of Building's no-review slow permits are Addition/Alteration. New Median = 40, Addition/Alteration Median = 90.
 */
WITH ranked AS (
	SELECT
		PermitTypeDesc
		,(total_days_plan_review IS NULL) AS no_plan_review
		,cycle_days
		,ROW_NUMBER() OVER(PARTITION BY PermitTypeDesc ORDER BY cycle_days) AS rn
		,COUNT(*) OVER(PARTITION BY PermitTypeDesc) AS n
	FROM permits_clean
	WHERE PermitTypeMapped = 'Building'
)
SELECT
	PermitTypeDesc
	,MAX(n) AS permits
	,MAX(CASE WHEN rn = CEIL(0.5 * n) THEN cycle_days END) AS median_days
	,MAX(CASE WHEN rn = CEIL(0.9 * n) THEN cycle_days END) AS p90_days
	,SUM(cycle_days > 251) AS slow_permits
	,ROUND(100 * SUM(cycle_days > 251) / COUNT(*), 1) AS pct_of_group_slow
	,ROUND(100 * SUM(cycle_days > 251) / SUM(SUM(cycle_days > 251)) OVER(), 1) AS pct_of_all_slow
	,SUM(cycle_days > 251 AND no_plan_review = 1) AS slow_no_review
FROM ranked 
GROUP BY PermitTypeDesc 
ORDER BY slow_no_review  DESC;
/** Permits = 121,280. Slow = 11,087. Verified.
 * Slow_no_review = 4,689.
 * Scorecard:
 * 	- Prediction 1: 80% of Building's no-review slow permits are Addition/Alteration. MISSED. 28% are Addition/Alteration. 
 * 	- Prediction 2: New Median = 40, Addition/Alteration Median = 90. MISSED. New Median = 182, Addition/Alteration Median = 8.
 * Findings: New construction is the slow tail. It's 18% of Building permits, but 67% of Building's slow permits.
 * 	- A third of all new-construction permits take more than 251 days, and the typical one takes six months.
 * 	- Alterations are fast (median 8 days). They are slow because there are so many of them.
 * Red flag: 3,311 new-construction permits "had no plan review", but new construction essentially always gets plan review. 
 * 	So, total_days_plan_review IS NULL probably doesn't mean "not reviewed." It probably means "review time not recorded." Coverage was only 23.5% (02_clean.sql Block G). 
 * 	"The 6,110 permits never saw plan review" statement was incorrect. "6,110 slow permits with no recorded review time" is probably correct.
 * 	See D2: confirmed. slow_no_review is compromised by era. Main finding (New = 67% of slow tail) stands.
**/


/** Block D2: plan-review coverage by applied year, New Building permits (22,336).
 *  Why: Block D1 found 3,311 slow New permits with no plan review. New construction
 *  essentially always gets plan review, so NULL may mean "not recorded", not "not reviewed".
 *  Prediction: cliff around 2016. HIT (two-year ramp, not one-year cliff). **/
SELECT 
	YEAR(applied_date) AS year_applied
	,COUNT(*) AS permit_count
	,COUNT(total_days_plan_review) AS total_days_plan_review_count
	,ROUND(100 * COUNT(total_days_plan_review) / COUNT(*), 1) AS pct_with_review
FROM permits_clean
WHERE PermitTypeMapped = 'Building' AND PermitTypeDesc = 'New'
GROUP BY YEAR(applied_date)
ORDER BY year_applied;
/** Result: 2006-2015 coverage 0.0-1.1%. 2016 5.7%, 2017 34.7%, 2018 83.6%, 2019 onward 92-96%. 2026 85.2% (partial year).
 * Counts sum to 22,336 (matches D1).
 * So total_days_plan_review wasn't recorded before ~2017. Before that, NULL just means the field wasn't tracked yet.
 * This breaks Block B/B2 and D1's slow_no_review column (redone on 2018+ in E/E2). D1's main finding still holds: New = 67% of Building's slow tail.
 * City vs applicant split only works for applied 2018+.
 * New volume drops 2,134 (2006) -> 351 (2009) and recovers by 2013. Matches the recession, so the dates are real. **/

/** Block D3: corrections coverage by applied year, New Building permits (22,336).
 * Why: D2 showed plan-review time was not recorded before ~2017. 02_clean Block G
 * trusted days_out_corrections zeros because they lined up with plan-review NULLs.
 * If corrections also started ~2017, pre-2017 zeros only mean it wasn't tracked. 
 * Checks: zero vs positive vs NULL per year. Zero + positive + null = permits on every row.
	Predictions: pct_positive 2010 = 5%, 2020 = 70%.
**/
 
SELECT 
	YEAR(applied_date) AS year_applied
	,COUNT(*) AS permits
	,SUM(days_out_corrections = 0) AS zero_corrections
	,SUM(days_out_corrections > 0) AS positive_corrections
	,SUM(days_out_corrections IS NULL) AS null_corrections
	,ROUND(100 * SUM(days_out_corrections > 0) / COUNT(*), 1) AS pct_positive
FROM permits_clean
WHERE PermitTypeMapped = 'Building' AND PermitTypeDesc = 'New'
GROUP BY YEAR(applied_date)
ORDER BY year_applied;

/** Result: zero + positive + null = permits on every row. Verified.
 * Scorecard: 2010 = 0.0% vs. 5% predicted (direction HIT, number high); 2020 = 70.9% vs. 70% HIT.
 * 2006-2015 positive 0.0 - 0.8%, 2016 4.2%, 2017 23.2%, 2018 onward 47-77%. Same cliff as D2.
 * So days_out_corrections wasn't tracked before ~2017 either, and old rows got 0 instead of NULL. That's why the 02_clean Block G check passed.
 * pct_positive falls 74.7% (2018) -> 46.9% (2025). Maybe right-censoring since the table is issued-only. Test in Block G. **/

/** Block E: Block B redo on applied 2018+.
 *  Why: D2 and D3 showed plan-review time and corrections were not recorded before ~2017,
 *  so Block B's "no plan review" group mixed real no-review permits with unrecorded old ones.
 *  From 2018 on, coverage is 84-96% (D2), so NULL now mostly means no plan review.
 *  Filter goes inside the CTE, before ranking, so percentiles are computed on 2018+ only.
 *  Predictions: no-review p90 = 30, review p90 = 365. **/

WITH ranked AS (
	SELECT
		cycle_days
		,(total_days_plan_review IS NOT NULL) AS had_plan_review
		,ROW_NUMBER() OVER(PARTITION BY total_days_plan_review IS NOT NULL ORDER BY cycle_days) AS rn
		,COUNT(*) OVER(PARTITION BY total_days_plan_review IS NOT NULL) AS n
	FROM permits_clean
	WHERE YEAR(applied_date) >= 2018 
)
SELECT 
	had_plan_review
	,MAX(n) AS permits
	,MAX(CASE WHEN rn = CEIL(0.5 * n) THEN cycle_days END) AS median_days
	,MAX(CASE WHEN rn = CEIL(0.9 * n) THEN cycle_days END) AS p90_days
	,ROUND(AVG(cycle_days), 0) AS mean_days
FROM ranked 
GROUP BY had_plan_review;

/** Result (applied 2018+, 52,070 permits):
 *  No plan review: 21,493 permits, median 1, p90 41, mean 25.
 *  Plan review:    30,577 permits, median 111, p90 398, mean 181.
 *  Scorecard: no-review p90 41 vs 30 MISS (close); review p90 398 vs 365 MISS (close).
 *
 *  Compared with Block B (all years):
 *  - No-review group collapsed: median 7 -> 1, p90 181 -> 41. Block B's 181-day tail was
 *    pre-2017 permits with unrecorded review. Over-the-counter permits are fast.
 *  - Review group barely moved (115/427 -> 111/398): it was already mostly 2018+
 *    (30,577 of 31,441).
 *  - Plan review splits the typical permit 111x (1 vs 111 days), up from 16x.
 *  - Plan-reviewed permits are 59% of 2018+ permits (Block B: 23.5%).
 *
 *  Block A hypothesis confirmed once the era confound is removed: permits without
 *  plan review are fast; the tail comes from plan review.
 *  Caveat: 2024-2026 permits are right-censored (issued-only table).
 *  Next: Block E2, tail share (B2 redo) on 2018+. **/

/** Block E2: Block B2 redo on applied 2018+ (tail share by plan review).
 *  Why: B2's 54/46 tail split was confounded by era (D2). Block E showed the
 *  no-review group is fast once pre-2017 permits are excluded.
 *  Slow = cycle_days > 251 (citywide p90, Block A), kept for comparability with B2.
 *  Predictions: 10%, 80% (intended: no-review share of tail, review rate slow). **/
SELECT 
	(total_days_plan_review IS NOT NULL) AS had_plan_review
	,COUNT(*) AS permits
	,SUM(cycle_days > 251) AS slow_permits
	,ROUND(100 * SUM(cycle_days > 251) / COUNT(*), 1) AS pct_of_group_slow
	,ROUND(100 * SUM(cycle_days > 251) / SUM(SUM(cycle_days > 251)) OVER(), 1) AS pct_of_all_slow
FROM permits_clean
WHERE YEAR(applied_date) >= 2018
GROUP BY had_plan_review;
/** Result (applied 2018+): 648 + 6,422 = 7,070 slow; shares sum to 100.0. Verified.
 *  No plan review: 3.0% of group slow, 9.2% of all slow.
 *  Plan review:   21.0% of group slow, 90.8% of all slow.
 *  Scorecard: no-review share 10% vs 9.2% HIT. 80% MISS: actual review rate is 21.0%,
 *  review share is 90.8% (rate vs share mixed up again).
 *
 *  Compared with B2 (all years): plan-review share of the tail 54% -> 91%.
 *  B2's near-even split came from the era confound.
 *  A plan-reviewed permit is 7x as likely to be slow (21.0 vs 3.0) and is now the
 *  larger group, so rate and share point the same way.
 *
 *  Conclusion: the slow tail is a plan-review problem. Fixing plan review reaches ~91%
 *  of slow permits. B2 suggested about half.
 *  Side note for Block G: 13.6% of 2018+ permits exceed 251 days vs 9.9% all years.
 *  Recent era is slower despite right-censoring biasing it faster.
 *  Next: Block F, city vs applicant days inside plan review.
**/


/** Block F: city vs applicant time inside plan review (headline).
 *  Scope for every F query: applied 2018+ (D2, D3), plan review recorded, and
 *  total_days_plan_review >= 0 (02_clean Block H found 81 impossible negatives).
 * total_days_plan_review = days in plan review. days_plan_review_city = days the city had it.
 * days_out_corrections = days the applicant had it (fixing corrections).
 **/

/** Block F0: does total = city + applicant? Must hold before splitting the total.
 * Expected: most rows add up. Rows that don't should have city + applicant > total (the 7,624-day migration artifact is one). **/
SELECT
	COUNT(*) AS plan_reviewed
	,SUM(ABS(total_days_plan_review - days_plan_review_city - days_out_corrections) <= 1) AS adds_up
	,SUM(ABS(total_days_plan_review - days_plan_review_city - days_out_corrections) > 1) AS does_not_add_up
	,SUM(days_plan_review_city IS NULL OR days_out_corrections IS NULL) AS missing_a_part
	,SUM(total_days_plan_review <= cycle_days) AS review_within_cycle
FROM permits_clean
WHERE YEAR(applied_date) >= 2018
	AND total_days_plan_review >= 0;
/** 30,496 plan-reviewed (Block E 30,577 minus the 81 negatives). 29,761 (97.6%) add up, 735 don't.
	88 permits have review longer than the whole cycle. Too few to matter.
 * F1-G2 use the 29,761. **/

/** Block F1: median / p90 / mean of each piece, rows that add up only (F0).
 *  Long format (UNION ALL) so one window ranks all four measures, partitioned by measure. **/
WITH base AS (
	SELECT
		cycle_days
		,total_days_plan_review
		,days_plan_review_city
		,days_out_corrections
	FROM permits_clean
	WHERE YEAR(applied_date) >= 2018
		AND total_days_plan_review >= 0
		AND ABS(total_days_plan_review - days_plan_review_city - days_out_corrections) <= 1
)
,long_form AS (
	SELECT '1 cycle (applied to issued)' AS measure, cycle_days AS days FROM base
	UNION ALL SELECT '2 plan review total', total_days_plan_review FROM base
	UNION ALL SELECT '3 city side', days_plan_review_city FROM base
	UNION ALL SELECT '4 applicant side', days_out_corrections FROM base
)
,ranked AS (
	SELECT
		measure
		,days
		,ROW_NUMBER() OVER(PARTITION BY measure ORDER BY days) AS rn
		,COUNT(*) OVER(PARTITION BY measure) AS n
	FROM long_form
)
SELECT
	measure
	,MAX(n) AS permits
	,MAX(CASE WHEN rn = CEIL(0.5 * n) THEN days END) AS median_days
	,MAX(CASE WHEN rn = CEIL(0.9 * n) THEN days END) AS p90_days
	,ROUND(AVG(days), 0) AS mean_days
FROM ranked
GROUP BY measure
ORDER BY measure;
/** median / p90 / mean: cycle 110 / 393 / 180, review 93 / 354 / 159, city 54 / 195 / 92, applicant 20 / 172 / 67.
 *  Means add up (92 + 67 = 159), medians don't.
 * Review is 88% of the cycle. City has 58% of review days, applicant 42%.
	Applicant side has the longest tail (p90 is 8.6x the median). Most fix corrections fast, a few take months. **/

/** Block F1b: who holds the days, slow tail vs the rest.
 *  Shares are of total days, so they show where the time goes.
 * Slow = cycle_days > 251 (citywide p90, Block A). **/
SELECT
	(cycle_days > 251) AS slow
	,COUNT(*) AS permits
	,ROUND(100 * SUM(total_days_plan_review) / SUM(cycle_days), 1) AS pct_cycle_in_review
	,ROUND(100 * SUM(days_plan_review_city) / SUM(total_days_plan_review), 1) AS pct_review_city
	,ROUND(100 * SUM(days_out_corrections) / SUM(total_days_plan_review), 1) AS pct_review_applicant
	,ROUND(100 * SUM(days_out_corrections > days_plan_review_city) / COUNT(*), 1) AS pct_applicant_longer
	,ROUND(AVG(number_review_cycles), 1) AS avg_review_cycles
FROM permits_clean
WHERE YEAR(applied_date) >= 2018
	AND total_days_plan_review >= 0
	AND ABS(total_days_plan_review - days_plan_review_city - days_out_corrections) <= 1
GROUP BY slow
ORDER BY slow;
/** Slow = 6,179 (20.8%, close to E2's 21.0%).
 *  Review is ~88% of the cycle in both groups.
 *  City share of review drops from 66.6% to 51.0% in the slow group. Applicant held it longer in 49.7% of slow permits vs 19.6%.
 * Slow permits average 3.4 review rounds vs 2.3. Every extra round adds applicant time and another city review.
 *  So the slow tail is mostly extra correction rounds. **/

/** Block F2: the same split for the three large Building work types (D0).
 *  Question: is New construction slow (D1) because of the city or the applicant? **/
WITH ranked AS (
	SELECT
		PermitTypeDesc
		,cycle_days
		,total_days_plan_review
		,days_plan_review_city
		,days_out_corrections
		,ROW_NUMBER() OVER(PARTITION BY PermitTypeDesc ORDER BY cycle_days) AS rn_cycle
		,ROW_NUMBER() OVER(PARTITION BY PermitTypeDesc ORDER BY days_plan_review_city) AS rn_city
		,ROW_NUMBER() OVER(PARTITION BY PermitTypeDesc ORDER BY days_out_corrections) AS rn_applicant
		,COUNT(*) OVER(PARTITION BY PermitTypeDesc) AS n
	FROM permits_clean
	WHERE PermitTypeMapped = 'Building'
		AND PermitTypeDesc IN ('New', 'Addition/Alteration', 'Tenant Improvment')
		AND YEAR(applied_date) >= 2018
		AND total_days_plan_review >= 0
		AND ABS(total_days_plan_review - days_plan_review_city - days_out_corrections) <= 1
)
SELECT
	PermitTypeDesc
	,MAX(n) AS permits
	,MAX(CASE WHEN rn_cycle = CEIL(0.5 * n) THEN cycle_days END) AS median_cycle
	,MAX(CASE WHEN rn_city = CEIL(0.5 * n) THEN days_plan_review_city END) AS median_city
	,MAX(CASE WHEN rn_applicant = CEIL(0.5 * n) THEN days_out_corrections END) AS median_applicant
	,ROUND(100 * SUM(days_plan_review_city) / SUM(total_days_plan_review), 1) AS pct_review_city
	,ROUND(100 * SUM(days_out_corrections) / SUM(total_days_plan_review), 1) AS pct_review_applicant
	,ROUND(100 * SUM(cycle_days > 251) / COUNT(*), 1) AS pct_slow
FROM ranked
GROUP BY PermitTypeDesc
ORDER BY permits DESC;
/** New: cycle 236, city 147, applicant 45, 45.8% slow.
 * Addition/Alteration: 84, 45, 19, 11.3% slow. Tenant Improvment: 28, 12, 0, 0.8% slow.
 *  New's city time alone (147) is longer than a whole Addition/Alteration permit (84).
	New is slow mostly on the city side (3.3x Addition/Alteration); applicant side is 2.4x.
 * City days include queue time and bigger plans take longer to review, so this doesn't mean the city is inefficient. **/

/** Block G: trend by applied year.
 *  Right-censoring: the extract is dated 2026-07-29 and permits_clean is issued-only, so
 *  slow permits applied in 2025-2026 are not issued yet and missing. Those years look
 * faster than they are. Read 2024 with caution. 2025-2026 are too low to use. **/

/** Block G1: cycle time by applied year, all permits (2006+). **/
WITH ranked AS (
	SELECT
		YEAR(applied_date) AS year_applied
		,cycle_days
		,ROW_NUMBER() OVER(PARTITION BY YEAR(applied_date) ORDER BY cycle_days) AS rn
		,COUNT(*) OVER(PARTITION BY YEAR(applied_date)) AS n
	FROM permits_clean
)
SELECT
	year_applied
	,MAX(n) AS permits
	,MAX(CASE WHEN rn = CEIL(0.5 * n) THEN cycle_days END) AS median_days
	,MAX(CASE WHEN rn = CEIL(0.9 * n) THEN cycle_days END) AS p90_days
	,ROUND(100 * SUM(cycle_days > 251) / COUNT(*), 1) AS pct_slow
FROM ranked
GROUP BY year_applied
ORDER BY year_applied;
/** Permits sum to 133,560.
	Median dropped 23 -> 8 from 2006 to 2009 (recession), then climbed to 62 by 2022.
 *  Slow share peaked at 18.0% in 2018. 2017-2022 were 13-18%, 2006-2015 were 3-11%.
 * 2020 jumped 35 -> 48 (COVID) and kept going up after.
 *  2023-2024 dipped (median ~55). 2024 permits have had 575+ days to get issued, so the dip is probably partly real.
 *  2025-2026 are censored. No 2026 permit can be over 251 days yet. **/

/** Block G2: city vs applicant by applied year, plan-reviewed 2018+ (F scope).
 * Tests the D3 note (corrections share falling 2018 -> 2025): real change or censoring? **/
WITH ranked AS (
	SELECT
		YEAR(applied_date) AS year_applied
		,total_days_plan_review
		,days_plan_review_city
		,days_out_corrections
		,ROW_NUMBER() OVER(PARTITION BY YEAR(applied_date) ORDER BY days_plan_review_city) AS rn_city
		,ROW_NUMBER() OVER(PARTITION BY YEAR(applied_date) ORDER BY days_out_corrections) AS rn_applicant
		,COUNT(*) OVER(PARTITION BY YEAR(applied_date)) AS n
	FROM permits_clean
	WHERE YEAR(applied_date) >= 2018
		AND total_days_plan_review >= 0
		AND ABS(total_days_plan_review - days_plan_review_city - days_out_corrections) <= 1
)
SELECT
	year_applied
	,MAX(n) AS permits
	,MAX(CASE WHEN rn_city = CEIL(0.5 * n) THEN days_plan_review_city END) AS median_city
	,MAX(CASE WHEN rn_applicant = CEIL(0.5 * n) THEN days_out_corrections END) AS median_applicant
	,ROUND(100 * SUM(days_out_corrections) / SUM(total_days_plan_review), 1) AS pct_review_applicant
FROM ranked
GROUP BY year_applied
ORDER BY year_applied;
/** Permits sum to 29,761 (same as F1).
 *  Applicant share is flat at 39-49% from 2018 to 2024, then 34.7% (2025) and 28.4% (2026).
 *  So the D3 drop is censoring. Permits still in corrections aren't issued yet, so they're missing.
 * City median went 86 (2018) -> ~47 (2024), but 2018 was the first full year of tracking so I wouldn't lean on it.
 *  Use 2018-2024 for trends. **/
