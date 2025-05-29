SELECT EmpId
, EmailWork
, EmailHome
, CONCAT(NameFirst,' ',NameLast) AS FullName
, EmploymentTypeCode
, JobClassDescr
, SiteDescr
, DateTerminationLastDay
, DateTermination
FROM vwHREmploymentList
WHERE (DateTerminationLastDay IS NOT NULL OR DateTermination IS NOT NULL)