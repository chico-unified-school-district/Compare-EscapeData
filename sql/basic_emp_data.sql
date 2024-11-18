SELECT TOP 1 EmailWork,CONCAT(NameFirst,' ',NameLast) AS FullName
FROM vwHREmploymentList WHERE EmpId = {0};