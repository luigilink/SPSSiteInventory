<#
    .SYNOPSIS
    Checks that the host meets the SPSSiteInventory prerequisites.

    .DESCRIPTION
    A quick, read-only readiness check to run before Invoke-SPSSiteInventory. It reports:

    - the PowerShell edition and version (Windows PowerShell 5.1 is expected);
    - whether SharePoint is installed (and its build number);
    - whether the SharePoint commands can be loaded;
    - whether the settings file exists.

    It changes nothing on the farm and returns a PSCustomObject summarizing the checks.

    .PARAMETER ConfigPath
    Path to the inventory settings .psd1 file to check for existence.

    .EXAMPLE
    .\Test-SPSSiteInventoryReadiness.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param
(
    [Parameter()]
    [System.String]
    $ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'config\inventory-settings.psd1')
)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Modules\SPSSiteInventory.Common\SPSSiteInventory.Common.psd1') -Force

$editionName = $PSVersionTable.PSEdition
$psVersion = $PSVersionTable.PSVersion.ToString()
$isWindowsPowerShell51 = ($PSVersionTable.PSVersion.Major -eq 5)

$productVersion = Get-SPSInstalledProductVersion
$sharePointInstalled = ($null -ne $productVersion)
$buildNumber = if ($sharePointInstalled) {
    '{0}.{1}.{2}.{3}' -f $productVersion.ProductMajorPart, $productVersion.ProductMinorPart, $productVersion.ProductBuildPart, $productVersion.ProductPrivatePart
}
else {
    'not installed'
}

$commandsLoadable = $false
if ($sharePointInstalled) {
    try {
        Import-SPSSharePointCommand
        $commandsLoadable = $null -ne (Get-Command -Name 'Get-SPWebApplication' -ErrorAction SilentlyContinue)
    }
    catch {
        Write-Warning -Message "SharePoint commands could not be loaded: $($_.Exception.Message)"
    }
}

$configExists = Test-Path -Path $ConfigPath

$result = [PSCustomObject]@{
    PowerShellEdition     = $editionName
    PowerShellVersion     = $psVersion
    IsWindowsPowerShell51 = $isWindowsPowerShell51
    SharePointInstalled   = $sharePointInstalled
    SharePointBuild       = $buildNumber
    CommandsLoadable      = $commandsLoadable
    ConfigFileExists      = $configExists
    ConfigPath            = $ConfigPath
}

Write-Output $result

if (-not $isWindowsPowerShell51) {
    Write-Warning -Message 'SPSSiteInventory targets Windows PowerShell 5.1 (SharePoint snap-in requirement). Run it with powershell.exe, not pwsh.'
}
if (-not $configExists) {
    Write-Warning -Message "Settings file not found at '$ConfigPath'. Copy config\inventory-settings.example.psd1 and adjust it."
}
