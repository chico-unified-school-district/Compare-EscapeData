SELECT
    EmpId
    , EmailWork
    , EmailHome
    , CONCAT(NameFirst,' ',NameLast) AS FullName
    , EmploymentTypeCode
    , JobClassDescr
FROM vwHREmploymentList
WHERE
    EmploymentStatusCode IN ('A','I','L','W')
    AND
    (EmploymentTypeCode IS NOT NULL AND EmploymentTypeCode <> '')
-- AND EmploymentTypeCode = 'S'
ORDER BY EmpId;