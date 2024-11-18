SELECT
    -- Fill in (0) with a list of fields to return
    {0}
FROM vwHREmploymentList
WHERE
    EmploymentStatusCode IN ('A','I','L','W','T')
    -- Fill in (1) with Date comparison to determine scope of results
    {1};