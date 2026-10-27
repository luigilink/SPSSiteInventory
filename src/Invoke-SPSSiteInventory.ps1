<#
    .SYNOPSIS
    Inventories SharePoint Server site collections and scores their migration complexity.

    .DESCRIPTION
    Invoke-SPSSiteInventory is the entry point of the SPSSiteInventory toolkit. It:

    1. bootstraps logging and validates prerequisites;
    2. loads the SharePoint commands and the inventory settings;
    3. builds the farm-solution map (WSP -> full-trust code, features) to detect custom code;
    4. enumerates site collections (identity + volumetry);
    5. collects the customization signals of each site and reads the Business Connectivity
       Services (BCS) definitions of the farm;
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
    $templateParity = if ($settings.ContainsKey('TemplateParity')) {
        $settings.TemplateParity
    }
    else {
        @{}
    }
    $inventory = @(Get-SPSSiteInventory -WebApplicationUrl $settings.WebApplicationUrl -TemplateParity $templateParity)
    if (@($inventory | Where-Object { $_.HasFbaZone }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'HasFbaZone') {
        Add-SPSInventoryEvent -Message 'FBA is configured, but HasFbaZone is not in Scoring.BlockingSignals. Add it to your settings to classify FBA as a SharePoint Online migration blocker.' -Level Warning
    }
    if (@($inventory | Where-Object { $_.InventoryScope -ne 'WebApplication' -and $_.IsUnsupportedSiteTemplate }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'IsUnsupportedSiteTemplate') {
        Add-SPSInventoryEvent -Message 'Unsupported site templates were detected, but IsUnsupportedSiteTemplate is not in Scoring.BlockingSignals. Add it to classify unsupported templates as migration blockers.' -Level Warning
    }

    Add-SPSInventoryEvent -Message ("Discovered {0} site collection(s); collecting customization signals." -f @($inventory).Count) -Level Information
    $largeContentThresholds = if ($settings.ContainsKey('LargeContentThresholds')) {
        $settings.LargeContentThresholds
    }
    else {
        @{}
    }
    $permissionLevels = if ($settings.ContainsKey('PermissionLevels')) {
        $settings.PermissionLevels
    }
    else {
        @{}
    }
    $assessment = & $commonModule {
        param ($Inventory, $CustomFeatureId, $FullTrustFeatureId, $Scoring, $LargeContentThresholds, $PermissionLevels)
        Invoke-SPSiteAssessment -Inventory $Inventory -CustomFeatureId $CustomFeatureId -FullTrustFeatureId $FullTrustFeatureId -Scoring $Scoring -LargeContentThresholds $LargeContentThresholds -PermissionLevels $PermissionLevels
    } $inventory $customFeatureId $fullTrustFeatureId $settings.Scoring $largeContentThresholds $permissionLevels
    $scored = @($assessment.Inventory)
    $contentTypes = @($assessment.ContentTypes)
    $managedMetadataLists = @($assessment.ManagedMetadataLists)
    $externalLists = @($assessment.ExternalLists)
    $sharePointAlerts = @($assessment.SharePointAlerts)
    if (@($scored | Where-Object { $_.IsLockedSite }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'IsLockedSite') {
        Add-SPSInventoryEvent -Message 'Locked site collections were detected, but IsLockedSite is not in Scoring.BlockingSignals. Add it to classify lock states as migration blockers.' -Level Warning
    }
    if (@($scored | Where-Object { [int]$_.IrmEnabledListCount -gt 0 }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'IrmEnabledListCount') {
        Add-SPSInventoryEvent -Message 'IRM-enabled lists were detected, but IrmEnabledListCount is not in Scoring.BlockingSignals. Add it to classify IRM-protected lists as migration blockers.' -Level Warning
    }
    if (@($scored | Where-Object { [int]$_.ExternalListCount -gt 0 }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'ExternalListCount') {
        Add-SPSInventoryEvent -Message 'External lists were detected, but ExternalListCount is not in Scoring.BlockingSignals. Add it to classify external lists, which cannot be recreated in SharePoint Online because BCS is retired there, as migration blockers.' -Level Warning
    }
    $assessedSites = @($scored | Where-Object { $_.InventoryScope -ne 'WebApplication' -and $_.AssessmentStatus -ne 'Failed' })
    if ($assessedSites.Count -gt 0 -and
        @($assessedSites | Where-Object { [int]$_.CustomPermissionLevelCount -gt 0 }).Count -ge ($assessedSites.Count / 2)) {
        Add-SPSInventoryEvent -Message 'Half or more of the site collections report custom permission levels. SharePoint provisions levels such as View Only and Manage Hierarchy under localized names; add the names used on your farm to PermissionLevels.BuiltInNames.' -Level Warning
    }
    if (@($scored | Where-Object { $_.TemplateLanguageReviewRequired }).Count -gt 0) {
        Add-SPSInventoryEvent -Message 'Some site template languages require review. Check TemplateLanguage* fields in the report before planning migration waves.' -Level Warning
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

    # BCS definitions are farm-wide; a failure here must not stop the site report.
    Add-SPSInventoryEvent -Message 'Reading Business Connectivity Services definitions.' -Level Information
    $bcs = [PSCustomObject]@{ Applications = @(); Complete = $false; Warnings = @() }
    try {
        $bcs = Get-SPSBcsApplication -WebApplicationUrl $settings.WebApplicationUrl
    }
    catch {
        Add-SPSInventoryEvent -Message "The BCS inventory failed: $($_.Exception.Message)" -Level Warning
    }
    foreach ($bcsWarning in @($bcs.Warnings)) {
        Add-SPSInventoryEvent -Message $bcsWarning -Level Warning
    }

    $solutionOutput = Export-SPSSolutionReport -InputObject @($solutionMap) -OutputFolder $settings.OutputFolder -BaseName ('SPSSiteInventory-' + $settings.EnvName)
    $output = Export-SPSInventoryReport -InputObject @($scored) -OutputFolder $settings.OutputFolder -BaseName ('SPSSiteInventory-' + $settings.EnvName) -EnvName $settings.EnvName -SolutionMap @($solutionMap) -ContentTypes $contentTypes -ManagedMetadataLists $managedMetadataLists -ExternalLists $externalLists -SharePointAlerts $sharePointAlerts -BcsApplications @($bcs.Applications) -BcsInventoryComplete ([bool]$bcs.Complete) -SolutionJsonPath $solutionOutput.JsonPath

    Add-SPSInventoryEvent -Message "Inventory complete. CSV: $($output.CsvPath) | JSON: $($output.JsonPath) | HTML: $($output.HtmlPath)" -Level Information
    Add-SPSInventoryEvent -Message "Report pack. Sites: $($output.SitesJsonPath) | Auth: $($output.AuthJsonPath) | Workflows: $($output.WorkflowsJsonPath) | Apps: $($output.AppsJsonPath) | Publishing: $($output.PublishingJsonPath) | Permissions: $($output.PermissionsJsonPath) | IRM/Locks: $($output.IrmLocksJsonPath) | Large content: $($output.LargeContentJsonPath) | Alerts: $($output.AlertsJsonPath) | Alerts CSV: $($output.AlertsCsvPath) | Manifest: $($output.ManifestJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "Farm-solution report. CSV: $($solutionOutput.CsvPath) | JSON: $($solutionOutput.JsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "Content-type report. CSV: $($output.ContentTypesCsvPath) | JSON: $($output.ContentTypesJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "Managed metadata report. CSV: $($output.ManagedMetadataCsvPath) | JSON: $($output.ManagedMetadataJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "External list report. CSV: $($output.ExternalListsCsvPath) | JSON: $($output.ExternalListsJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "SharePoint alerts report. CSV: $($output.SharePointAlertsCsvPath) | JSON: $($output.SharePointAlertsJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "BCS report. CSV: $($output.BcsCsvPath) | JSON: $($output.BcsJsonPath)" -Level Information
}
catch {
    Add-SPSInventoryEvent -Message "Inventory failed: $($_.Exception.Message)" -Level Error
    throw
}
finally {
    Stop-Transcript | Out-Null
}
