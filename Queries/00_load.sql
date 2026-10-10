/** 00_load.sql - Seattle Building Permit Cycle-Time Analysis
 * Purpose: create permits_raw, an all-text staging table for the raw CSV.
 * Input:   Data/Raw/Building_Permits_20260729.csv (Seattle Open Data, downloaded 2026-07-29).
 * Output:  permits_raw (191,830 rows).
 * Load:    this script creates the empty table; the rows are loaded with the DBeaver import wizard
 *          into the EXISTING table (header row on, empty strings -> NULL on). Every column is
 *          VARCHAR/TEXT on purpose; types are assigned in 02_clean. 01_profile Block A verifies
 *          the empty-string -> NULL setting, which every later IS NULL check depends on.
 * Author:  Peter Jeong. **/

CREATE DATABASE IF NOT EXISTS seattle_building_permit;
USE seattle_building_permit;

DROP TABLE IF EXISTS permits_raw;

CREATE TABLE permits_raw (
	PermitNum VARCHAR(255),
	PermitClass VARCHAR(255),
	PermitClassMapped VARCHAR(255),
	PermitTypeMapped VARCHAR(255),
	PermitTypeDesc VARCHAR(255),
	Description TEXT,
	HousingUnits VARCHAR(255),
	HousingUnitsRemoved VARCHAR(255),
	HousingUnitsAdded VARCHAR(255),
	EstProjectCost VARCHAR(255),
	AppliedDate VARCHAR(255),
	IssuedDate VARCHAR(255),
	ExpiresDate VARCHAR(255),
	CompletedDate VARCHAR(255),
	StatusCurrent VARCHAR(255),
	RelatedMup VARCHAR(255),
	OriginalAddress1 VARCHAR(255),
	OriginalCity VARCHAR(255),
	OriginalState VARCHAR(255),
	OriginalZip VARCHAR(255),
	ContractorCompanyName VARCHAR(255),
	Link TEXT,
	Latitude VARCHAR(255),
	Longitude VARCHAR(255),
	Location1 VARCHAR(255),
	TotalDaysPlanReview VARCHAR(255),
	DaysInitialPlanReview VARCHAR(255),
	DaysPlanReviewCity VARCHAR(255),
	DaysOutCorrections VARCHAR(255),
	NumberReviewCycles VARCHAR(255),
	InitialReviewCompleteDate VARCHAR(255),
	PlanReviewCompleteDate VARCHAR(255),
	DaysIssuePermitCity VARCHAR(255),
	ReadyToIssueDate VARCHAR(255),
	Zoning VARCHAR(255),
	DwellingUnitType VARCHAR(255),
	StandardPlan VARCHAR(255),
	DependentBuilding VARCHAR(255),
	ParentPermitNum VARCHAR(255),
	HousingCategory VARCHAR(255)
);

/** Load checks (run after the import). **/
DESCRIBE permits_raw;

SELECT COUNT(*), COUNT(DISTINCT PermitNum) 
FROM permits_raw;

SELECT MIN(AppliedDate), MAX(AppliedDate)
FROM permits_raw;