<#
.SYNOPSIS

.DESCRIPTION
This Script...
.EXAMPLE

.INPUTS
.OUTPUTS
.NOTES
.LINK
# Thanks, Mathias!
# https://stackoverflow.com/questions/38241770/powershell-help-converting-hash-table-to-html
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

function Clear-OldDataFiles {
  process {
    Write-Host ('{0}' -f $MyInvocation.MyCommand.Name) -F DarkYellow
    $cutOff = (Get-Date).AddDays(-5)
    $oldCsvs = Get-ChildItem .\data -Filter *.csv | Where-Object { $_.LastWriteTime -le $cutOff }
    $oldCsvs | Remove-Item -Force -Confirm:$false -WhatIf:$WhatIf
  }
}

function Compare-EmpData ($oldData, $todaysData) {
  process {
    Write-Host ('{0}' -f $MyInvocation.MyCommand.Name) -F Green
    $properties = "EmpId", "EmploymentStatusCode", "SiteId", "EmploymentTypeCode", "JobClassDescr", "SiteDescr"
    $compareParams = @{
      ReferenceObject  = $oldData
      DifferenceObject = $todaysData
      Property         = $properties
    }
    Compare-Object @compareParams | Where-Object { $_.SideIndicator -eq '=>' } |
      Select-Object -Property $properties
  }
}

function Complete-Processing {
  process {
    Write-Host ('{0},{1},===============' -f $MyInvocation.MyCommand.Name, $_.EmpId) -F Blue
    Write-Verbose ($_ | Out-String)
  }
}

function Format-EmailObjs ($jobLibrary) {
  begin {
    $css = Get-Content -Path '.\html\style.css' -Raw
    $head = '<style TYPE="TEXT/CSS">' + $css + '</style>'
    $message = '<p>Hello,</p><p>The following employee information has recently been updated in Escape:</p>'
    $sig = Get-Content -Path '.\html\emailSig.html' -Raw
  }
  process {
    $emObjProperties = 'Name', 'Email', 'Type', 'Old', 'New'
    if ($_.leaveDate) { $emObjProperties += 'Leaving' }
    foreach ($job in $_.jobMatches) {
      Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.EmpID, $job.name)
      Write-Verbose ($MyInvocation.MyCommand.Name, 'Old Data', $_.oldData | out-string)
      Write-Verbose  ($MyInvocation.MyCommand.Name, 'New Data', $_.newData | out-string)

      $msgObj = '' | Select-Object -Property subject, to, html
      $msgObj.subject = $job.name + ' - ' + $_.basicEmployeeData.FullName
      $msgObj.to = $job.recipients

      $tableData = '' | Select-Object -Property $emObjProperties
      $tableData.'Name' = $_.basicEmployeeData.FullName
      $tableData.'Email' = $_.basicEmployeeData.EmailWork
      $tableData.'Type' = $job.name
      $tableData.'Old' = $_.oldData.($job.attribute)
      $tableData.'New' = $_.newData.($job.attribute)
      if ($_.leaveDate) { $tableData.'Leaving' = $_.leaveDate }

      $convertParams = @{
        Property    = $emObjProperties
        Head        = $head
        PreContent  = $message
        PostContent = $sig
      }
      $msgObj.html = $tableData | ConvertTo-Html @convertParams | Out-String
      # Write-Verbose ($msgObj.html | Out-String)
      # Add each block of email data to our object
      $_.emailData += $msgObj
    }
    $_
  }
}

function Format-Object {
  begin {
    $properties = 'EmpId', 'oldData', 'newData', 'basicEmployeeData', 'emailData', 'jobMatches', 'leaveDate'
  }
  process {
    $obj = '' | Select-Object $properties
    $obj.EmpId = $_.EmpID
    $obj.newData = $_
    $obj.jobMatches = @()
    $obj.emailData = @()
    $obj
  }
}

function Import-PreviousEmpData {
  $myFile = Get-ChildItem -Path .\data -Filter *.csv |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not$myFile) {
    Write-Host ('{0},No Previous File' -f $MyInvocation.MyCommand.Name)
    return
  }
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $myFile.VersionInfo.FileName) -F Green
  Import-Csv -Path $myFile.VersionInfo.FileName
}

function Send-Notification {
  begin {
    $mailParams = @{
      From       = '<{0}>' -f $MailCredential.Username
      CC         = $null
      BodyAsHTML = $True
      SMTPServer = 'smtp.office365.com'
      Cred       = $MailCredential # use a valid Office365 account with Flow rules in place to prevent SPAM warnings.
      UseSSL     = $True
      Port       = 587
    }
  }
  process {
    foreach ($emailJob in $_.emailData) {
      if (!$emailJob.to) {
        $msgVars = $MyInvocation.MyCommand.Name, $_.EmpID, $emailJob.subject
        return (Write-Host ('{0},{1},[{2}],No recipients listed in job' -f $msgVars) -f Red)
      }
      $mailParams.Subject = $emailJob.subject
      $mailParams.Body = $emailJob.html
      $mailParams.To = $emailJob.to
      if ($CC) { $mailParams.CC = $CC }

      Write-Verbose ($MyInvocation.MyCommand.Name, $mailParams.subject | Out-String)
      # Write-Verbose ($MyInvocation.MyCommand.Name, $mailParams.body | Out-String)
      Write-Verbose ( $mailParams | Out-String )
      # https://www.w3schools.com/html/tryit.asp?filename=tryhtml_editor

      $msg = $MyInvocation.MyCommand.Name, $_.EmpID, $mailParams.subject, ($mailParams.to -join ',')
      Write-Host ('{0},{1},[{2}],[{3}]' -f $msg) -F DarkGreen
      if (!$WhatIf) { Send-MailMessage @mailParams }
      $_
    }
  }
}

function Set-BasicEmployeeData ($dbParams) {
  begin {
    $baseSql = Get-Content -Path .\sql\basic_emp_data.sql -Raw
  }
  process {
    $sqlVars = "id=$($_.EmpID)"
    Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $sqlVars)
    $data = New-SqlOperation @dbParams -Query $baseSql -Parameters $sqlVars | ConvertTo-Csv | ConvertFrom-Csv
    $_.basicEmployeeData = $data
    $_
  }
}

function Set-LeaveDate {
  process {
    if (!$_.basicEmployeeData.DateTermination -and !$_.basicEmployeeData.DateTerminationLastDay) { return $_ }
    $myDate = if ($_.basicEmployeeData.DateTerminationLastDay -gt $_.basicEmployeeData.DateTermination ) {
      $_.basicEmployeeData.DateTerminationLastDay
    }
    else {
      $_.basicEmployeeData.DateTermination
    }
    if ((Get-Date $myDate) -lt (Get-Date)) { return $_ }
    $_.leaveDate = Get-Date $myDate -Format M/dd/yyyy
    Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.EmpId, $_.leaveDate) -F DarkGreen
    $_
  }
}

function Set-JobMatches ($jobLibrary) {
  process {
    foreach ($job in $jobLibrary) {
      # Skip job if site(s) do not match
      if ($job.includedSites -and ($job.includedSites -notcontains $_.oldData.SiteId) -and ($job.includedSites -notcontains $_.newData.SiteId) ) {
        Write-Verbose ('{0},{1},{2},No site match found - Skipping.' -f $MyInvocation.MyCommand.Name, $_.EmpID, $job.name)
        continue
      }
      # Detect change of specific attribute
      if ((!$job.oldValues) -and (!$Job.newValues)) {

        if ($_.oldData.($job.attribute) -notmatch '\w') {
          Write-Host ('{0},{1},{2},Old Data empty.' -f $MyInvocation.MyCommand.Name, $_.EmpID, $job.name) -F DarkYellow
          continue
        }

        if ($_.oldData.($job.attribute) -ne $_.newData.($job.attribute) -and ($_.newData.($job.attribute).Trim() -match '\w')) {
          Write-Host ('{0},{1},Job MATCH: [{2}]' -f $MyInvocation.MyCommand.Name, $_.oldData.EmpId, $job.name) -F DarkCyan
          $_.jobMatches += $job
          continue
        }
      }
      # Add the current type to the jobMatches array for email processing
      if (( $job.oldValues -contains $_.oldData.($job.attribute)) -and ($job.newValues -contains $_.newData.($job.attribute))) {
        Write-Host ('{0},{1},Job MATCH: [{2}]' -f $MyInvocation.MyCommand.Name, $_.oldData.EmpId, $job.name) -F Cyan
        $_.jobMatches += $job
      }
    }
    # Only pass the current object to next step if any job match occurs
    if ($_.jobMatches) { $_ }
  }
}

function Set-OldData ($csvData) {
  process {
    $empId = $_.EmpID
    $oldData = $csvData | Where-Object { $_.EmpID -eq $empId }
    if (!$oldData) {
      Write-Host ('{0},{1},Skipping new entry' -f $MyInvocation.MyCommand.Name, $empId) -F DarkCyan
      return
    }
    $_.oldData = $oldData
    $_
  }
}

function Write-TodaysDataToFile ($data, $fileName) {
  if (@($data).count -eq 0) { EXIT }
  if (Test-Path -Path .\data\$fileName) {
    # Prevent overwrites
    return (Write-Host ('{0},{1}, File already exists - Skipping export' -f $MyInvocation.MyCommand.Name, $fileName) -F DarkYellow)
  }
  $data | Export-Csv -Path .\data\$fileName
}

Import-Module CommonScriptFunctions
Import-Module -Name dbatools -Cmdlet Invoke-DbaQuery, Set-DbatoolsConfig

Show-BlockInfo Main
Clear-SessionData
if ($WhatIf) { Show-TestRun }

Show-BlockInfo 'Create Folders'
New-Item -ItemType Directory -Name data -Force | Out-Null
New-Item -ItemType Directory -Name json -Force | Out-Null

Show-BlockInfo 'Import Jobs'
$jobs = Get-Content -Path $JobFile | ConvertFrom-JSON
Write-Verbose ($jobs.jobLibrary | Out-String)

$dbParams = @{
  Server     = $EscapeServer
  Database   = $EscapeDatabase
  Credential = $EscapeCredential
}

Show-BlockInfo 'Get Old and New Data'
$oldData = Import-PreviousEmpData
$newData = New-SqlOperation @dbParams -Query (Get-Content .\sql\emp_data.sql -Raw) | ConvertTo-Csv | ConvertFrom-Csv

# =========== TEST ==============
# $oldData = Import-Csv .\data\emp_data_old.csv
# $newData = Import-Csv .\data\emp_data_new.csv
# =========== TEST ==============

$exportFileName = 'emp_data_' + (Get-date -f yyyy-MM-dd) + '.csv'

if (!$oldData) {
  "Writing previous data file and exiting. Next run time will have actual data to compare"
  Write-TodaysDataToFile $newData $exportFileName
  EXIT
}

Write-Host ('Old Data count: ' + @($oldData).count) -F Blue
Write-Host ('New Data count: ' + @($newData).count) -F Magenta

Compare-EmpData $oldData $newData |
  Format-Object |
    Set-OldData $oldData |
      Set-JobMatches $jobs.jobLibrary |
        Set-BasicEmployeeData $dbParams |
          Set-LeaveDate |
            Format-EmailObjs $jobs.jobLibrary |
              Send-Notification |
                Complete-Processing

# TODO
# Write-TodaysDataToFile $newData $exportFileName
Clear-OldDataFiles

Clear-SessionData
if ($WhatIf) { Show-TestRun }
