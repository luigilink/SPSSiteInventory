<#
    .SYNOPSIS
    Checks that the host is ready to run SPSSiteInventory.

    .DESCRIPTION
    A quick, read-only readiness check to run before Invoke-SPSSiteInventory. It reports, one
    line per check with a status (OK, Warning, Error or Skipped):

    - the toolkit module, the PowerShell edition and version (Windows PowerShell 5.1 is
      expected) and whether the session is elevated;
    - the settings file: that it exists and loads, that its output folder is usable, and which
      blocking signals and weights of the example configuration it does not have yet;
    - SharePoint: whether it is installed (and its build), whether the SharePoint commands
      load, whether the farm can be reached, whether the account is a farm administrator and
      whether the web applications to scan exist.

    An error blocks the scan and a warning does not. The script exits with code 1 when there is
    an error, so that it can gate an automated run, and 0 otherwise. It changes nothing on the
    farm and writes no file.

    .PARAMETER ConfigPath
    Path to the inventory settings .psd1 file to check.

    .PARAMETER SkipSharePoint
    Skips the checks that need SharePoint, to check the host and the settings file on a machine
    that is not a farm server.

    .PARAMETER PassThru
    Returns a summary object (counts, IsReady and the checks) in addition to the report.

    .EXAMPLE
    .\Test-SPSSiteInventoryReadiness.ps1

    .EXAMPLE
    .\Test-SPSSiteInventoryReadiness.ps1 -ConfigPath D:\Config\inventory-settings.psd1 -SkipSharePoint
#>
#Requires -Version 5.1
[CmdletBinding()]
param
(
    [Parameter()]
    [System.String]
    $ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'config\inventory-settings.psd1'),

    [Parameter()]
    [switch]
    $SkipSharePoint,

    [Parameter()]
    [switch]
    $PassThru
)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Modules\SPSSiteInventory.Common\SPSSiteInventory.Common.psd1') -Force

$exampleConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'config\inventory-settings.example.psd1'
$check = @(Get-SPSReadinessCheck -ConfigPath $ConfigPath -ExampleConfigPath $exampleConfigPath -SkipSharePoint:$SkipSharePoint)
$summary = Write-SPSReadinessReport -Check $check

if ($PassThru) {
    Write-Output $summary
}

if (-not $summary.IsReady) {
    exit 1
}
