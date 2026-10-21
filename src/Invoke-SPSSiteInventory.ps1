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

$commonModule = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Modules\SPSSiteInventory.Common\SPSSiteInventory.Common.psd1') -Force -PassThru

$context = Initialize-SPSScript -ScriptName 'Invoke-SPSSiteInventory' -ScriptRoot $PSScriptRoot

try {
    Add-SPSInventoryEvent -Message "SPSSiteInventory $($context.Version) started by $($context.CurrentUser) on $($context.ServerTarget)." -Level Information
    Add-SPSInventoryEvent -Message "Loading settings from '$ConfigPath'." -Level Information
    $settings = Get-SPSInventorySetting -Path $ConfigPath

    Import-SPSSharePointCommand

    Add-SPSInventoryEvent -Message 'Building farm-solution map.' -Level Information
    $solutionMapParams = @{ CustomSolutionPrefix = $settings.CustomSolutionPrefix }
    if ($settings.ContainsKey('AutoDetectCustomSolutions')) {
        $solutionMapParams['AutoDetectCustom'] = [bool]$settings.AutoDetectCustomSolutions
    }
    if ($settings.ContainsKey('KnownMicrosoftSolutionPrefix')) {
        $solutionMapParams['KnownMicrosoftPrefix'] = $settings.KnownMicrosoftSolutionPrefix
    }
    $solutionMap = Get-SPSFarmSolutionMap @solutionMapParams
    $customFeatureId = @($solutionMap | Where-Object { $_.IsCustom } | ForEach-Object { $_.FeatureIds } | Sort-Object -Unique)
    $fullTrustFeatureId = @($solutionMap | Where-Object { $_.IsFullTrustCode } | ForEach-Object { $_.FeatureIds } | Sort-Object -Unique)

    Add-SPSInventoryEvent -Message 'Enumerating site collections.' -Level Information
    $inventory = @(Get-SPSSiteInventory -WebApplicationUrl $settings.WebApplicationUrl)
    if (@($inventory | Where-Object { $_.HasFbaZone }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'HasFbaZone') {
        Add-SPSInventoryEvent -Message 'FBA is configured, but HasFbaZone is not in Scoring.BlockingSignals. Add it to your settings to classify FBA as a SharePoint Online migration blocker.' -Level Warning
    }

    Add-SPSInventoryEvent -Message ("Discovered {0} site collection(s); collecting customization signals." -f @($inventory).Count) -Level Information
    $assessment = & $commonModule {
        param ($Inventory, $CustomFeatureId, $FullTrustFeatureId, $Scoring)
        Invoke-SPSiteAssessment -Inventory $Inventory -CustomFeatureId $CustomFeatureId -FullTrustFeatureId $FullTrustFeatureId -Scoring $Scoring
    } $inventory $customFeatureId $fullTrustFeatureId $settings.Scoring
    $scored = @($assessment.Inventory)
    $contentTypes = @($assessment.ContentTypes)
    if (@($scored | Where-Object { $_.IsLockedSite }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'IsLockedSite') {
        Add-SPSInventoryEvent -Message 'Locked site collections were detected, but IsLockedSite is not in Scoring.BlockingSignals. Add it to classify lock states as migration blockers.' -Level Warning
    }
    if (@($scored | Where-Object { [int]$_.IrmEnabledListCount -gt 0 }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'IrmEnabledListCount') {
        Add-SPSInventoryEvent -Message 'IRM-enabled lists were detected, but IrmEnabledListCount is not in Scoring.BlockingSignals. Add it to classify IRM-protected lists as migration blockers.' -Level Warning
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
    $scored = @(Group-SPSMigrationWave -InputObject $scored -MigrationWaves $waves)

    $output = Export-SPSInventoryReport -InputObject @($scored) -OutputFolder $settings.OutputFolder -BaseName ('SPSSiteInventory-' + $settings.EnvName) -EnvName $settings.EnvName -SolutionMap @($solutionMap) -ContentTypes $contentTypes
    $solutionOutput = Export-SPSSolutionReport -InputObject @($solutionMap) -OutputFolder $settings.OutputFolder -BaseName ('SPSSiteInventory-' + $settings.EnvName)

    Add-SPSInventoryEvent -Message "Inventory complete. CSV: $($output.CsvPath) | JSON: $($output.JsonPath) | HTML: $($output.HtmlPath)" -Level Information
    Add-SPSInventoryEvent -Message "Farm-solution report. CSV: $($solutionOutput.CsvPath) | JSON: $($solutionOutput.JsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "Content-type report. CSV: $($output.ContentTypesCsvPath) | JSON: $($output.ContentTypesJsonPath)" -Level Information
}
catch {
    Add-SPSInventoryEvent -Message "Inventory failed: $($_.Exception.Message)" -Level Error
    throw
}
finally {
    Stop-Transcript | Out-Null
}
