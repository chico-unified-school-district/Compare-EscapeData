<#
.SYNOPSIS

.DESCRIPTION
This Script...
.EXAMPLE

.INPUTS
.OUTPUTS
.NOTES
.LINK
# Requires -Version 5.0
#>
[cmdletbinding()]
param (
 # Escape Employee Server
 [Parameter(Mandatory = $true)]
 [string]$EscapeServer,
 [Parameter(Mandatory = $true)]
 [string]$EscapeDatabase,
 [Parameter(Mandatory = $true)]
 [System.Management.Automation.PSCredential]$EscapeCredential,
 [Parameter(Mandatory = $true)]
 [System.Management.Automation.PSCredential]$MailCredential,
 [string[]]$CC,
 [Parameter(Mandatory = $true)]
 [string]$JobFile,
 # Run a 'Whatif' on commands - no data will be changed
 [Alias('wi')]
	[switch]$WhatIf
)

function Compare-EmpData ($previousData, $todaysData, $properties) {
 process {
  Write-Host ('{0}' -f $MyInvocation.MyCommand.Name)
  $compareParams = @{
   ReferenceObject  = $previousData
   DifferenceObject = $todaysData
   Property         = $properties
  }
  Compare-Object @compareParams
 }
}

function Clear-OldDataFiles {
 process {
  Write-Host ('{0}' -f $MyInvocation.MyCommand.Name)
  "Removing old .csv files..."
  $cutOff = (Get-Date).AddDays(-5)
  $oldCsvs = Get-ChildItem .\data -Filter *.csv | Where-Object { $_.LastWriteTime -le $cutOff }
  $oldCsvs | Remove-Item -Force -Confirm:$false -WhatIf:$WhatIf
 }
}

function Complete-Processing {
 begin {
  $i = 0
 }
 process {
  # Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.EmpId, $_.email) -Fore $infoClr
  $i++
  $msg = $MyInvocation.MyCommand.Name, $_.EmpId, $_.NameFull
  Write-host ('{0},{1},{2}' -f $msg) -Fore Magenta
 }
}

function Import-PreviousEmpData {
 $myFile = Get-ChildItem -Path .\data -Filter *.csv |
 Sort-Object LastWriteTime -Descending | Select-Object -First 1
 if (-not$myFile) {
  Write-Host ('{0},No Previous File' -f $MyInvocation.MyCommand.Name)
  return
 }
 Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $myFile)
 Import-Csv -Path .\data\$myFile
}

function Send-Notification {
 begin {
  $mailParams = @{
   From       = '<{0}>' -f $MailCredential.Username
   BodyAsHTML = $True
   SMTPServer = 'smtp.office365.com'
   Cred       = $MailCredential # use a valid Office365 account with Flow rules in place to prevent SPAM warnings.
   UseSSL     = $True
   Port       = 587
  }
 }
 process {
  $mailParams.Subject = '{0} - {1} {2}' -f $_.subject, $_.EmpId, $_.name
  $mailParams.Body = $_.html
  $mailParams.To = $_.to

  Write-Verbose ($mailParams.subject | Out-String)
  Write-Verbose ($mailParams.body | Out-String)
  Write-Host ( $mailParams | Out-String )

  $msg = $MyInvocation.MyCommand.Name, $_.EmpId, $_.name, $_.subject, ($_.to -join ',')
  Write-Host ('{0},{1},{2},{3}.{4}' -f $msg)
  if (!$WhatIf) { Send-MailMessage @mailParams }
 }
}

function Write-TodaysDataToFile ($data, $properties) {
 $exportFileName = 'emp_data_' + (Get-date -f yyyy-MM-dd) + '.csv'
 $data | Select-Object -Property $properties |
 Export-Csv -Path .\data\$exportFileName
}

function Format-NewDataSql ($baseSql, $atributes, $dateString) {
 $baseSql -f (($atributes -join "`n    ,"), $dateString)
}

function Format-Object ($properties) {
 begin { $properties += 'oldData', 'newData', 'basicEmployeeData', 'emailData' }
 process {
  $obj = '' | Select-Object $properties
  $obj.EmpId = $_.EmpId
  $obj.newData = $_
  $obj
 }
}

function Get-OriginalData ($csvData) {
 process {
  $empId = $_.EmpId
  $oldData = $csvData | Where-Object { $_.EmpId -eq $empId }
  if (!$oldData) { return } # skip if no old data. Usually means a brand new entry
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $empId) -F Green
  $_.oldData = $oldData
  $_
 }
}

function Get-ChangeTypes ($jobLibrary) {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.oldData.EmpId)

  foreach ($type in $jobLibrary) {
   # if the starting and new values match then flag that attribute for later processing
   $startVal = $type.startingValue
   $watchVal = $type.watchValue
   if ( ($_.oldData.($type.attribute) -eq $startVal) -or ($_.oldData.($type.attribute) -eq $watchVal)) {
    $_.($type.attribute) = $true
    continue
   }
   # if the value of this attribute changes at all flag it for later processing
   if ( $_.oldData.($type.attribute) -ne $_.newData.($type.attribute)) {
    $_.($type.attribute) = $true
   }
  }
  $_
 }
}

function Get-BasicEmployeeData ($dbParams) {
 begin {
  $baseSql = Get-Content -Path .\sql\basic_emp_data.sql -Raw
 }
 process {
  $sql = $baseSql -f $_.EmpId
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $sql) -f Blue
  $data = Invoke-SqlCmd @dbParams -Query $sql | ConvertTo-Csv | ConvertFrom-Csv
  $_.basicEmployeeData = $data
  $_
 }
}

function Format-EmailObjs ($jobLibrary) {
 begin {
  $baseMessage = Get-Content -Path .\html\message.html -Raw
  $htmlStyle = Get-Content -Path .\html\style.html -Raw
 }
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, ($_.EmpId + ' ' + $type.attribute)) -F Green
  $_.emailData = '' | Select-Object -Property $jobLibrary.attribute

  foreach ($attrib in $jobLibrary.attribute) {

   if ($_.($attrib) -ne $true) { continue }

   $_.emailData.($attrib) = '' | Select-Object -Property name, empId, subject, to, html

   $job = $jobLibrary | Where-Object { $_.attribute -eq $attrib }
   $_.emailData.($attrib).name = $_.basicEmployeeData.FullName
   $_.emailData.($attrib).empId = $_.EmpId
   $_.emailData.($attrib).subject = $job.name
   $_.emailData.($attrib).to = ($job.recipients -split ',')

   $tableData = @{
    Name        = $_.basicEmployeeData.FullName
    Email       = $_.basicEmployeeData.EmailWork
    Type        = $job.name
    Attribute   = $job.attribute
    'Old Value' = $_.oldData.($attrib)
    'New Value' = $_.newData.($attrib)
   }
   # Thanks, Mathias!
   # https://stackoverflow.com/questions/38241770/powershell-help-converting-hash-table-to-html
   $tableHtml = New-Object psobject -Property $tableData |
   Select-Object Name, Email, Type, Attribute, 'Old Value', 'New Value' | ConvertTo-Html -Fragment

   $message = $baseMessage -f $htmlStyle, ($tableHtml | out-String)
   $_.emailData.($attrib).html = $message
   # Send each block of email data to the Send-MailMessage function
   $_.emailData.($attrib)
  }
 }
}

# ==============================================================================================
# Imported Functions
. .\lib\Clear-SessionData.ps1
. .\lib\Show-BlockInfo.ps1
. .\lib\Show-TestRun.ps1

Show-BlockInfo Main
Clear-SessionData
Show-TestRun

Import-Module -Name 'SqlServer' -Cmdlet 'Invoke-SqlCmd'

if (!(Test-Path -Path .\data)) { New-Item -ItemType Directory -Path .\data -Confirm:$false }
if (!(Test-Path -Path .\json)) { New-Item -ItemType Directory -Path .\json -Confirm:$false }

$jobs = Get-Content -Path $JobFile | ConvertFrom-JSON
# Write-Verbose ($jobs.jobLibrary | Out-String)

$trackedAttributes = $jobs.jobLibrary.attribute
$trackedAttributes += 'EmpId'

$dbParams = @{
 Server                 = $EscapeServer
 Database               = $EscapeDatabase
 Credential             = $EscapeCredential
 TrustServerCertificate = $true
}

# get csv
$recentCSVData = Import-PreviousEmpData
# get recent changes
$days = 10
$recentDateStr = 'AND DateTimeEdited > DATEADD(DAY,-{0},GETDATE())' -f $days
$latestDataSql = Format-NewDataSql (Get-Content .\sql\monitored_data.sql -Raw) $trackedAttributes $recentDateStr
# Write-Verbose ("`n", $latestDataSql, "===================================" | Out-String)
$latestData = Invoke-SqlCmd @dbParams -Query $latestDataSql
# get last 5 years data
$yearsBackDateStr = 'AND DateTimeEdited > DATEADD(YEAR,-5,GETDATE())'
$yearsBacksql = Format-NewDataSql (Get-Content .\sql\monitored_data.sql -Raw) $trackedAttributes $yearsBackDateStr
# Write-Verbose ("`n", $yearsBacksql | Out-String)
$yearsBackData = Invoke-SqlCmd @dbParams -Query $yearsBacksql

Write-Host ('Recent CSV count: ' + $recentCSVData.count) -F Blue
Write-Host (('Last {0} days count: ' -f $days) + $latestData.count) -F Green
Write-Host ('Past Years count: ' + $yearsBackData.count) -F Magenta

# =========== TEST ==============
# $recentCSVData = Import-Csv .\data\emp_data_2024-11-04.csv
# $latestData = Import-Csv .\data\emp_data_2024-11-05.csv
# =========== TEST ==============

if (!$recentCSVData) {
 # Write file and exit. Next run time will have actual data to compare
 Write-TodaysDataToFile $yearsBackData $trackedAttributes
 EXIT
}

Compare-EmpData $recentCSVData $latestData $trackedAttributes |
Where-Object { $_.SideIndicator -eq '=>' } |
Format-Object $trackedAttributes |
Get-OriginalData $recentCSVData |
Get-ChangeTypes $jobs.jobLibrary |
Get-BasicEmployeeData $dbParams |
Format-EmailObjs $jobs.jobLibrary |
Send-Notification

# TODO
Write-TodaysDataToFile $yearsBackData $trackedAttributes
Clear-OldDataFiles

Clear-SessionData
Show-TestRun