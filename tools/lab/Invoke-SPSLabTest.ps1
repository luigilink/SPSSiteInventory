<#
    .SYNOPSIS
    Tests a SPSSiteInventory release on a lab SharePoint farm: build test content, run the
    inventory, check the reports.

    .DESCRIPTION
    WRITES TO THE FARM (unlike the toolkit): it creates and removes site collections. Run it on a
    lab farm only, from the SharePoint Management Shell (Windows PowerShell 5.1, elevated), as the
    farm account.

    It runs these steps, one at a time with -Action or all in order with -Action All:

    1. Provision: writes the lab settings from the example configuration of the toolkit being
       tested, then creates one small site collection per scenario, named
       <web application>/sites/<prefix>-<scenario>, and marks it as a lab site.
    2. Inventory: runs Invoke-SPSSiteInventory.ps1 of the toolkit with the lab settings. The whole
       web application is scanned, so use a lab web application.
    3. Verify: checks the reports against what each scenario must produce and prints PASS, FAIL,
       INFO or SKIP for every check, with the assessment status of every lab site. The exit code is
       1 when a check fails.
    4. Remove: removes the lab site collections, and only those (the name prefix and the marker are
       both required). With -Action All, it runs only when -Cleanup is given.

    The scenarios are listed in the wiki page "Lab testing" and by Get-SPSLabScenario. Everything
    the script writes goes to -WorkFolder: the lab settings, the manifest and the reports.

    .PARAMETER Action
    The step to run. All runs Provision, Inventory and Verify, and Remove with -Cleanup.

    .PARAMETER WebApplicationUrl
    The URL of the lab web application. There is no default: name it on purpose.

    .PARAMETER ToolkitPath
    The folder of the toolkit to test: the extracted release, or the src folder of the repository.
    Defaults to the src folder of the repository that contains this script.

    .PARAMETER WorkFolder
    Where the lab settings, the manifest and the reports go. Defaults to .\SPSLab.

    .PARAMETER Prefix
    The prefix of the site collection names. Lowercase letters and digits.

    .PARAMETER Owner
    The owner of the site collections. Defaults to the current account.

    .PARAMETER Scenario
    The scenarios to build and check. Defaults to all of them.

    .PARAMETER Cleanup
    With -Action All, removes the lab site collections at the end.

    .PARAMETER Force
    Does not ask for a confirmation before each site collection is created or removed.

    .PARAMETER WhatIf
    Shows the site collections that would be created or removed, without creating or removing
    anything. The inventory step does not run.

    .EXAMPLE
    .\Invoke-SPSLabTest.ps1 -WebApplicationUrl https://lab.contoso.local -ToolkitPath C:\SPSSiteInventory

    .EXAMPLE
    .\Invoke-SPSLabTest.ps1 -Action Remove -WebApplicationUrl https://lab.contoso.local
#>
#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'This is an operator-facing lab script whose purpose is console output.')]
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
param
(
    [Parameter()]
    [ValidateSet('Provision', 'Inventory', 'Verify', 'Remove', 'All')]
    [System.String]
    $Action = 'All',

    [Parameter(Mandatory = $true)]
    [System.String]
    $WebApplicationUrl,

    [Parameter()]
    [System.String]
    $ToolkitPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src'),

    [Parameter()]
    [System.String]
    $WorkFolder = (Join-Path -Path (Get-Location).Path -ChildPath 'SPSLab'),

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9]{2,15}$')]
    [System.String]
    $Prefix = 'spslab',

    [Parameter()]
    [System.String]
    $Owner = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME),

    [Parameter()]
    [System.String[]]
    $Scenario,

    [Parameter()]
    [switch]
    $Cleanup,

    [Parameter()]
    [switch]
    $Force
)

$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'SPSInventoryLab.psm1') -Force

$toolkit = (Resolve-Path -LiteralPath $ToolkitPath).Path
$examplePath = Join-Path -Path $toolkit -ChildPath 'config\inventory-settings.example.psd1'
$inventoryScript = Join-Path -Path $toolkit -ChildPath 'Invoke-SPSSiteInventory.ps1'
foreach ($required in @($examplePath, $inventoryScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "'$required' does not exist: -ToolkitPath must be the folder of the toolkit (the extracted release, or src)."
    }
}

$manifestPath = Join-Path -Path $WorkFolder -ChildPath 'lab-manifest.json'
$settingsPath = Join-Path -Path $WorkFolder -ChildPath 'inventory-settings.lab.psd1'
$reportFolder = Join-Path -Path $WorkFolder -ChildPath 'Reports'
$confirm = @{}
if ($Force) {
    $confirm['Confirm'] = $false
}

$runProvision = $Action -in @('Provision', 'All')
$runInventory = $Action -in @('Inventory', 'All')
$runVerify = $Action -in @('Verify', 'All')
$runRemove = ($Action -eq 'Remove') -or ($Action -eq 'All' -and $Cleanup)
$failed = $false

Write-Host ''
Write-Host ('SPSSiteInventory lab - toolkit: {0} - web application: {1}' -f $toolkit, $WebApplicationUrl) -ForegroundColor Cyan

if ($runProvision -or $runInventory) {
    $null = New-SPSLabSettings -ExamplePath $examplePath -OutputPath $settingsPath -WebApplicationUrl $WebApplicationUrl -ReportFolder $reportFolder
    Write-Host ('Lab settings: {0}' -f $settingsPath) -ForegroundColor Cyan
}

if ($runProvision) {
    Write-Host ''
    Write-Host '== Provision ==' -ForegroundColor Cyan
    $manifest = New-SPSLabFixture -WebApplicationUrl $WebApplicationUrl -ManifestPath $manifestPath -Prefix $Prefix -Owner $Owner -Scenario $Scenario @confirm
    $manifest.Scenario | Format-Table -Property Name, Status, Detail -AutoSize | Out-String -Width 200 | Write-Host
    Write-Host ('Manifest: {0}' -f $manifestPath) -ForegroundColor Cyan
}

if ($runInventory -and -not $WhatIfPreference) {
    Write-Host ''
    Write-Host '== Inventory ==' -ForegroundColor Cyan
    & $inventoryScript -ConfigPath $settingsPath
}

if ($runVerify) {
    Write-Host ''
    Write-Host '== Verify ==' -ForegroundColor Cyan
    $result = @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder $reportFolder)
    $count = Write-SPSLabReport -Result $result
    if ($count.Fail -gt 0) {
        $failed = $true
    }
}

if ($runRemove) {
    Write-Host ''
    Write-Host '== Remove ==' -ForegroundColor Cyan
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $removed = Remove-SPSLabFixture -ManifestPath $manifestPath @confirm
    }
    else {
        $removed = Remove-SPSLabFixture -WebApplicationUrl $WebApplicationUrl -Prefix $Prefix @confirm
    }
    $removed | Format-Table -Property Url, Status, Detail -AutoSize | Out-String -Width 200 | Write-Host
}

if ($failed) {
    exit 1
}
