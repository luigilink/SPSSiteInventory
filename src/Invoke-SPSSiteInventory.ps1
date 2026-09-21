<#
    .SYNOPSIS
    Inventories SharePoint Server site collections and scores their migration complexity.

    .DESCRIPTION
    Invoke-SPSSiteInventory is the entry point of the SPSSiteInventory toolkit. It:

    1. bootstraps logging and validates prerequisites;
    2. loads the SharePoint commands and the inventory settings;
    3. builds the farm-solution map (WSP -> full-trust code, features) to detect custom code;
    4. enumerates site collections (identity + volumetry);
    5. collects the customization signals of each site;
    6. scores each site from 1 (Simple) to 4 (Blocking) and assigns a migration wave;
    7. exports the scored inventory to CSV, JSON and a self-contained HTML report, and the
       farm-solution map to its own CSV and JSON.

    The tool is read-only: it never modifies the farm. Run it on a farm server, as the
    farm account, in an elevated Windows PowerShell 5.1 session.

    .PARAMETER ConfigPath
    Path to the inventory settings .psd1 file. Defaults to
    .\config\inventory-settings.psd1 next to this script.

    .EXAMPLE
    .\Invoke-SPSSiteInventory.ps1

    .EXAMPLE
    .\Invoke-SPSSiteInventory.ps1 -ConfigPath D:\Config\inventory-settings.psd1
#>
#Requires -Version 5.1
[CmdletBinding()]
param
(
    [Parameter()]
    [System.String]
    $ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'config\inventory-settings.psd1')
)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Modules\SPSSiteInventory.Common\SPSSiteInventory.Common.psd1') -Force

$context = Initialize-SPSScript -ScriptName 'Invoke-SPSSiteInventory' -ScriptRoot $PSScriptRoot

try {
    Add-SPSInventoryEvent -Message "SPSSiteInventory $($context.Version) started by $($context.CurrentUser) on $($context.ServerTarget)." -Level Information
    Add-SPSInventoryEvent -Message "Loading settings from '$ConfigPath'." -Level Information
    $settings = Get-SPSInventorySetting -Path $ConfigPath

    Import-SPSSharePointCommand

    Add-SPSInventoryEvent -Message 'Building farm-solution map.' -Level Information
    $solutionMap = Get-SPSFarmSolutionMap -CustomSolutionPrefix $settings.CustomSolutionPrefix
    $customFeatureId = @($solutionMap | Where-Object { $_.IsCustom } | ForEach-Object { $_.FeatureIds } | Sort-Object -Unique)
    $fullTrustFeatureId = @($solutionMap | Where-Object { $_.IsFullTrustCode } | ForEach-Object { $_.FeatureIds } | Sort-Object -Unique)

    Add-SPSInventoryEvent -Message 'Enumerating site collections.' -Level Information
    $inventory = Get-SPSSiteInventory -WebApplicationUrl $settings.WebApplicationUrl

    $scored = foreach ($item in $inventory) {
        $site = Get-SPSite -Identity $item.Url -ErrorAction Stop
        try {
            $signals = Get-SPSSiteCustomization -Site $site -CustomFeatureId $customFeatureId -FullTrustFeatureId $fullTrustFeatureId
            $signals['SizeGB'] = $item.SizeGB

            $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $settings.Scoring

            [PSCustomObject]@{
                Url               = $item.Url
                Title             = $item.Title
                WebApp            = $item.WebApp
                ContentDb         = $item.ContentDb
                Template          = $item.Template
                SizeGB            = $item.SizeGB
                SubWebCount       = $item.SubWebCount
                LastModified      = $item.LastModified
                Workflow2010Count = $signals['Workflow2010Count']
                Workflow2013Count = $signals['Workflow2013Count']
                InfoPathFormCount = $signals['InfoPathFormCount']
                UsesFullTrustCode = $signals['UsesFullTrustCode']
                Category          = $result.Category
                CategoryName      = $result.CategoryName
                Score             = $result.Score
                Reasons           = ($result.Reasons -join '; ')
            }
        }
        finally {
            $site.Dispose()
        }
    }

    $waves = if ($settings.ContainsKey('MigrationWaves')) {
        @($settings.MigrationWaves)
    }
    else {
        @(
            @{ Wave = 1; Name = 'Quick wins'; Categories = @(1) }
            @{ Wave = 2; Name = 'Light remediation'; Categories = @(2) }
            @{ Wave = 3; Name = 'Rebuild'; Categories = @(3) }
            @{ Wave = 4; Name = 'Projects / blockers'; Categories = @(4) }
        )
    }
    $scored = @(Group-SPSMigrationWave -InputObject @($scored) -MigrationWaves $waves)

    $output = Export-SPSInventoryReport -InputObject @($scored) -OutputFolder $settings.OutputFolder -BaseName ('SPSSiteInventory-' + $settings.EnvName) -EnvName $settings.EnvName
    $solutionOutput = Export-SPSSolutionReport -InputObject @($solutionMap) -OutputFolder $settings.OutputFolder -BaseName ('SPSSiteInventory-' + $settings.EnvName)

    Add-SPSInventoryEvent -Message "Inventory complete. CSV: $($output.CsvPath) | JSON: $($output.JsonPath) | HTML: $($output.HtmlPath)" -Level Information
    Add-SPSInventoryEvent -Message "Farm-solution report. CSV: $($solutionOutput.CsvPath) | JSON: $($solutionOutput.JsonPath)" -Level Information
}
catch {
    Add-SPSInventoryEvent -Message "Inventory failed: $($_.Exception.Message)" -Level Error
    throw
}
finally {
    Stop-Transcript | Out-Null
}
