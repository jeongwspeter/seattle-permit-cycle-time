/** 01_profile.sql - Seattle Building Permit Cycle-Time Analysis
 * Purpose: profile permits_raw before cleaning: date coverage, statuses, and the date-less records.
 * Input:   permits_raw (191,830 rows, loaded by 00_load.sql).
 * Output:  no tables. Results recorded as comments under each query.
 * Run:     after 00_load.
 * Author:  Peter Jeong. **/

USE seattle_building_permit;

/** Block A: date coverage, and proof the import turned empty strings into NULL (both *_empty = 0). **/
SELECT
	COUNT(*) AS total_rows
	,COUNT(AppliedDate) AS applied_notnull
	,SUM(AppliedDate = '') AS applied_empty
	,COUNT(IssuedDate) AS issued_notnull
	,SUM(IssuedDate = '') AS issued_empty
	,COUNT(ReadyToIssueDate) AS readytoissue_notnull
	,COUNT(CompletedDate) AS completed_notnull
FROM permits_raw;

/** 45,544 rows lack AppliedDate. 52,434 rows lack IssuedDate. Both empty-string counts = 0. **/

/** Block B: applied x issued cross-tab. One damaged population or two? **/
WITH labeled AS (
	SELECT
		CASE WHEN AppliedDate IS NULL THEN 'no applied' ELSE 'has applied' END AS applied_state
		,CASE WHEN IssuedDate IS NULL THEN 'no issued' ELSE 'has issued' END AS issued_state
	FROM permits_raw 
)
SELECT
	applied_state
	,issued_state
	,COUNT(*) AS permits
FROM labeled
GROUP BY applied_state, issued_state
ORDER BY applied_state, issued_state;

/** Margins match Block A (146,286 / 45,544 applied; 191,830 total). Verified.
 * Both dates (analyzable): 137,375.
 * Applied, never issued: 8,911 (not all backlog: 4,247 were canceled or withdrawn, see Block D).
 * Issued, no applied date: 2,021.
 * Neither date ("ghosts"): 43,523, 22.7% of the table. One concentrated population, not two. **/

/** Block C: StatusCurrent mix on the raw table. Includes ghosts, so not the analysis mix (see 02_clean Block E). **/

SELECT 
	StatusCurrent
	,COUNT(*) AS permits
	,ROUND((COUNT(*) / (SELECT COUNT(*) FROM permits_raw)) * 100, 1) AS pct
FROM permits_raw
GROUP BY StatusCurrent 
ORDER BY permits DESC;

/** Block D: status x date state. Each row's four date columns sum to permits. **/
SELECT 
	StatusCurrent
	,COUNT(*) AS permits
	,SUM(AppliedDate IS NULL AND IssuedDate IS NULL) AS no_dates
	,SUM(AppliedDate IS NOT NULL AND IssuedDate IS NOT NULL) AS analyzable
	,SUM(AppliedDate IS NOT NULL AND IssuedDate IS NULL) AS applied_only
	,SUM(AppliedDate IS NULL AND IssuedDate IS NOT NULL) AS issued_only
FROM permits_raw
GROUP BY StatusCurrent 
ORDER BY no_dates DESC;
/** Missingness is structural: seven in-workflow statuses are ~100% dateless; Expired and Issued are ~0%.
 * Completed: 86.2% analyzable (114,898 of 133,220). **/

/** Block E1: do the ghosts carry any other lifecycle field? **/
SELECT
	COUNT(*) AS ghosts
	,COUNT(ExpiresDate) AS has_expires
	,COUNT(CompletedDate) AS has_completed
	,COUNT(ReadyToIssueDate) AS has_readytoissue
	,COUNT(InitialReviewCompleteDate) AS has_initialreview
	,COUNT(TotalDaysPlanReview) AS has_planreview_days
FROM permits_raw
WHERE AppliedDate IS NULL AND IssuedDate IS NULL;
/** 43,523 ghosts. Plan-review days 0; any other date under 0.3%. Stubs that left no trace in this system. **/

/** Block E2: ghosts by class and type, plus a sample. **/
SELECT 
	PermitClassMapped
	,PermitTypeMapped
	,COUNT(*) AS ghosts
FROM permits_raw
WHERE AppliedDate IS NULL AND IssuedDate IS NULL
GROUP BY PermitClassMapped, PermitTypeMapped
ORDER BY ghosts DESC;

SELECT PermitNum, StatusCurrent, PermitTypeMapped, LEFT(Description, 60) AS descr
FROM permits_raw
WHERE AppliedDate IS NULL AND IssuedDate IS NULL 
LIMIT 20;

/** Block F0: ghost share by permit type. Prediction: ECA/Shoreline ~100%, Building ~15-20%. **/
SELECT
	PermitTypeMapped
	,COUNT(*) AS total
	,SUM(AppliedDate IS NULL AND IssuedDate IS NULL) as ghosts
	,ROUND(SUM(AppliedDate IS NULL AND IssuedDate IS NULL)/COUNT(*) * 100, 1) AS pct_ghost
FROM permits_raw
GROUP BY PermitTypeMapped
ORDER BY ghosts DESC;

/** ECA/Shoreline 100.0% ghosts (18,756): HIT, out of scope entirely.
 * Building 13.7% ghosts (21,170 of 153,998): just under the 15-20% predicted.
 * Grading 46.9%, Demolition 19.3%, Roof 0.5%. **/

