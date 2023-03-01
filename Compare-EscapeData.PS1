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
 [Parameter(Mandatory = $true)]
 [string[]]$To,
 # Run a 'Whatif' on commands - no data will be changed
 [Alias('wi')]
	[switch]$WhatIf
)

function Select-PriorSub {
 process {
  if ($_.EmploymentTypeCode -ne 'S') { return }
  if ($_.SideIndicator -ne '<=') { return }
  $msg = $MyInvocation.MyCommand.Name, $_.EmpId, $_.EmploymentTypeCode
  Write-Host ('{0},[{1}],[{2}]' -f $msg )
  $_
 }
}

function Select-NewRegular ($todaysData) {
 process {
  $id = $_.EmpId
  $emp = $todaysData.Where({ $_.EmpId -eq $id })
  if ($emp.EmploymentTypeCode -ne 'R') { return }
  $msg = $MyInvocation.MyCommand.Name, $emp.EmpId, $emp.EmploymentTypeCode
  Write-Host ('{0},[{1}],[{2}]' -f $msg )
  $emp
 }
}

function Compare-EmpData ($previousData, $todaysData) {
 process {
  Write-Host ('{0}' -f $MyInvocation.MyCommand.Name)
  $compareParams = @{
   ReferenceObject  = $previousData
   DifferenceObject = $todaysData
   Property         = 'EmpId', 'EmploymentTypeCode'
  }
  $result = Compare-Object @compareParams
  $result
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

function Get-TodaysEmpData {
 $escParams = @{
  Server     = $EscapeServer
  Database   = $EscapeDatabase
  Credential = $EscapeCredential
  Query      = Get-Content -Path .\sql\emp_data.sql -Raw
 }
 $msg = $MyInvocation.MyCommand.Name, $EscapeServer, $EscapeDatabase, $EscapeCredential.Username
 Write-Host ('{0},[{1}\{2}],[{3}]' -f $msg) -Fore Green
 $results = Invoke-SqlCmd @escParams
 Write-Host ('{0},Count: {1}' -f $MyInvocation.MyCommand.Name, $results.count) -Fore Green
 # Convert results to PSCustomObjects
 # $results | ConvertTo-Csv | ConvertFrom-Csv
 $results
}

function Import-PreviousEmpData {
 $myFile = Get-ChildItem -Path .\data -Filter *.csv |
 Sort-Object LastWriteTime -Descending |
 Select-Object -First 1
 if (-not$myFile) {
  Write-Host ('{0},No Previous File' -f $MyInvocation.MyCommand.Name)
  return
 }
 Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $myFile)
 Import-Csv -Path .\data\$myFile
}

function New-DataDir {
 process {
  if (Test-Path -Path .\data) { return }
  Write-Host ('{0}' -f $MyInvocation.MyCommand.Name)
  New-Item -ItemType Directory -Path .\data -Confirm:$false
 }
}

function Send-Notification {
 begin {
  $baseMessage = Get-Content -Path .\html\message.html -Raw
  $mailParams = @{
   From       = '<{0}>' -f $MailCredential.Username
   To         = $To
   BodyAsHTML = $True
   SMTPServer = 'smtp.office365.com'
   Cred       = $MailCredential # use a valid Office365 account with Flow rules in place to prevent SPAM warnings.
   UseSSL     = $True
   Port       = 587
  }
 }
 process {
  $mailParams.Subject = 'Sub to Regular - {0}' -f $_.FullName
  $bodyParams = $_.EmpId, $_.EmailWork, $_.EmailHome, $_.FullName, $_.EmploymentTypeCode, $_.JobClassDescr
  $mailParams.Body = $baseMessage -f $bodyParams

  Write-Verbose ($mailParams.subject | Out-String)
  Write-Verbose ($mailParams.body | Out-String)
  Write-Host ( $mailParams | Out-String )

  if ($WhatIf) { return }

  $msg = $MyInvocation.MyCommand.Name, $_.EmpId, $_.FullName, ($To -join ',')
  Write-Host ('{0},[{1}],[{2}],To[{3}]' -f $msg)
  Send-MailMessage @mailParams
 }
}

function Write-TodaysDataToFile ($data) {
 $exportFileName = 'emp_data_' + (Get-date -f yyyy-MM-dd) + '.csv'
 $data | Select-Object -Property EmpId, EmploymentTypeCode |
 Export-Csv -Path .\data\$exportFileName
}

# ==============================================================================================
# Imported Functions
. .\lib\Clear-SessionData.ps1
. .\lib\Load-Module.ps1
. .\lib\Show-BlockInfo.ps1
. .\lib\Show-TestRun.ps1

Show-BlockInfo Main
Clear-SessionData
Show-TestRun

'SqlServer' | Load-Module

New-DataDir
$previousData = Import-PreviousEmpData
$todaysData = Get-TodaysEmpData

if ($previousData -and $todaysData) {
 Compare-EmpData $previousData $todaysData | Select-PriorSub |
 Select-NewRegular $todaysData | Send-Notification
}

Write-TodaysDataToFile $todaysData
Clear-OldDataFiles

Clear-SessionData
Show-TestRun