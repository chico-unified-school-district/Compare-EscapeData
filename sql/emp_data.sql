SELECT
    EmpId
    , TRIM(EmploymentStatusCode) AS EmploymentStatusCode
    , TRIM(SiteId) AS SiteId
    , TRIM(SiteDescr) AS SiteDescr
    , TRIM (EmploymentTypeCode) AS EmploymentTypeCode
    , JobClassDescr
FROM vwHREmploymentList
WHERE
 EmailWork LIKE '%@%'
ORDER BY EmpId