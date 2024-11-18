[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)]
 [string]$html
)

$tempFile = [System.IO.Path]::GetTempFileName() + ".html"
$html | Out-File -Encoding utf8 $tempFile

# Open the file in the default browser
Start-Process $tempFile