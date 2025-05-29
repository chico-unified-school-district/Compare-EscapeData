SELECT EmpId
, EmailWork
, EmailHome
, CONCAT(NameFirst,' ',NameLast) AS FullName
, EmploymentTypeCode
, JobClassDescr
, SiteDescr
, DateTerminationLastDay
, DateTermination
FROM vwHREmploymentList WHERE EmpId = @id
-- WHERE EmailWork IS NOT NULL;