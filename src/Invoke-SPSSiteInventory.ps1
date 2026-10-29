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
       Services (BCS) definitions and the Secure Store target applications of the farm;
    6. scores each site from 1 (Simple) to 4 (Blocking) and assigns a migration wave; with
       TargetMode = 'SharePointOnPrem' in the settings, the same four categories read as
       Modern-ready, Light remediation, Rebuild (SPFx) and Blocked;
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
    $targetProfile = & $commonModule {
        param ($TargetMode)
        Get-SPSTargetProfile -TargetMode $TargetMode
    } $(if ($settings.ContainsKey('TargetMode')) { $settings.TargetMode } else { 'SharePointOnline' })
    $targetMode = $targetProfile.TargetMode
    Add-SPSInventoryEvent -Message ("Target mode: {0} ({1})." -f $targetMode, $targetProfile.DisplayName) -Level Information

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
    $scopeSettings = if ($settings.ContainsKey('Scope')) {
        $settings.Scope
    }
    else {
        @{}
    }
    $scopeOption = & $commonModule {
        param ($ScopeSettings)
        Get-SPSScopeOption -Settings $ScopeSettings
    } $scopeSettings
    $reportSettings = if ($settings.ContainsKey('Report')) {
        $settings.Report
    }
    else {
        @{}
    }
    $reportOption = & $commonModule {
        param ($ReportSettings)
        Get-SPSReportOption -Settings $ReportSettings
    } $reportSettings
    $exclusion = @{ PersonalSites = 0; SiteMasters = 0 }
    $inventory = @(Get-SPSSiteInventory -WebApplicationUrl $settings.WebApplicationUrl -TemplateParity $templateParity -IncludePersonalSite:$scopeOption.IncludePersonalSites -IncludeSiteMaster:$scopeOption.IncludeSiteMasters -Exclusion $exclusion)
    if ($exclusion.PersonalSites -gt 0 -or $exclusion.SiteMasters -gt 0) {
        $leftOut = @()
        $includeSetting = @()
        if ($exclusion.PersonalSites -gt 0) {
            $leftOut += '{0} personal site(s)' -f $exclusion.PersonalSites
            $includeSetting += 'Scope.IncludePersonalSites'
        }
        if ($exclusion.SiteMasters -gt 0) {
            $leftOut += '{0} site master(s)' -f $exclusion.SiteMasters
            $includeSetting += 'Scope.IncludeSiteMasters'
        }
        Add-SPSInventoryEvent -Message ('Left out {0}: they are not sites to migrate. Set {1} to $true in the settings to include them.' -f ($leftOut -join ' and '), ($includeSetting -join ' and ')) -Level Information
    }
    if ($targetMode -eq 'SharePointOnline' -and
        @($inventory | Where-Object { $_.HasFbaZone }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'HasFbaZone') {
        Add-SPSInventoryEvent -Message 'FBA is configured, but HasFbaZone is not in Scoring.BlockingSignals. Add it to your settings to classify FBA as a SharePoint Online migration blocker.' -Level Warning
    }
    if ($targetMode -eq 'SharePointOnline' -and
        @($inventory | Where-Object { $_.InventoryScope -ne 'WebApplication' -and $_.IsUnsupportedSiteTemplate }).Count -gt 0 -and
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
    $sharePointAlertSettings = if ($settings.ContainsKey('SharePointAlerts')) {
        $settings.SharePointAlerts
    }
    else {
        @{}
    }
    $assessment = & $commonModule {
        param ($Inventory, $CustomFeatureId, $FullTrustFeatureId, $Scoring, $LargeContentThresholds, $PermissionLevels, $SharePointAlertSettings, $TargetMode)
        Invoke-SPSiteAssessment -Inventory $Inventory -CustomFeatureId $CustomFeatureId -FullTrustFeatureId $FullTrustFeatureId -Scoring $Scoring -LargeContentThresholds $LargeContentThresholds -PermissionLevels $PermissionLevels -SharePointAlertSettings $SharePointAlertSettings -TargetMode $TargetMode
    } $inventory $customFeatureId $fullTrustFeatureId $settings.Scoring $largeContentThresholds $permissionLevels $sharePointAlertSettings $targetMode
    $scored = @($assessment.Inventory)
    $contentTypes = @($assessment.ContentTypes)
    $managedMetadataLists = @($assessment.ManagedMetadataLists)
    $externalLists = @($assessment.ExternalLists)
    $sharePointAlerts = @($assessment.SharePointAlerts)
    if ($targetMode -eq 'SharePointOnline' -and
        @($scored | Where-Object { $_.HasNoAccessLock }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'HasNoAccessLock' -and
        @($settings.Scoring.BlockingSignals) -notcontains 'IsLockedSite') {
        Add-SPSInventoryEvent -Message 'Site collections locked with NoAccess were detected, but HasNoAccessLock is not in Scoring.BlockingSignals. Add it to classify them as migration blockers: the migration tools cannot read them.' -Level Warning
    }
    if ($targetMode -eq 'SharePointOnline' -and
        @($scored | Where-Object { [int]$_.IrmEnabledListCount -gt 0 }).Count -gt 0 -and
        @($settings.Scoring.BlockingSignals) -notcontains 'IrmEnabledListCount') {
        Add-SPSInventoryEvent -Message 'IRM-enabled lists were detected, but IrmEnabledListCount is not in Scoring.BlockingSignals. Add it to classify IRM-protected lists as migration blockers.' -Level Warning
    }
    if ($targetMode -eq 'SharePointOnline' -and
        @($scored | Where-Object { [int]$_.ExternalListCount -gt 0 }).Count -gt 0 -and
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
        @($targetProfile.MigrationWave)
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

    # Secure Store target applications are farm-wide too; a failure here must not stop the site report either.
    Add-SPSInventoryEvent -Message 'Reading Secure Store target applications.' -Level Information
    $secureStore = [PSCustomObject]@{ Applications = @(); Complete = $false; Warnings = @() }
    try {
        $secureStore = Get-SPSSecureStoreApplication -WebApplicationUrl $settings.WebApplicationUrl
    }
    catch {
        Add-SPSInventoryEvent -Message "The Secure Store inventory failed: $($_.Exception.Message)" -Level Warning
    }
    foreach ($secureStoreWarning in @($secureStore.Warnings)) {
        Add-SPSInventoryEvent -Message $secureStoreWarning -Level Warning
    }

    if (@($sharePointAlerts | Where-Object { -not [string]::IsNullOrEmpty([string]$_.UserLoginName) }).Count -gt 0) {
        Add-SPSInventoryEvent -Message 'The SharePoint alerts files contain the login names of the alert owners, which are personal data. Set SharePointAlerts.IncludeUserLogin to $false in the settings to leave them out.' -Level Information
    }

    $solutionOutput = Export-SPSSolutionReport -InputObject @($solutionMap) -OutputFolder $settings.OutputFolder -BaseName ('SPSSiteInventory-' + $settings.EnvName)
    $output = Export-SPSInventoryReport -InputObject @($scored) -OutputFolder $settings.OutputFolder -BaseName ('SPSSiteInventory-' + $settings.EnvName) -EnvName $settings.EnvName -SolutionMap @($solutionMap) -ContentTypes $contentTypes -ManagedMetadataLists $managedMetadataLists -ExternalLists $externalLists -SharePointAlerts $sharePointAlerts -BcsApplications @($bcs.Applications) -BcsInventoryComplete ([bool]$bcs.Complete) -SecureStoreApplications @($secureStore.Applications) -SecureStoreInventoryComplete ([bool]$secureStore.Complete) -SolutionJsonPath $solutionOutput.JsonPath -ExcludedPersonalSiteCount ([int]$exclusion.PersonalSites) -ExcludedSiteMasterCount ([int]$exclusion.SiteMasters) -HtmlSplitThreshold $reportOption.HtmlSplitThreshold -HtmlRowsPerPage $reportOption.HtmlRowsPerPage -TargetMode $targetMode

    Add-SPSInventoryEvent -Message "Inventory complete. CSV: $($output.CsvPath) | JSON: $($output.JsonPath) | HTML: $($output.HtmlPath)" -Level Information
    if (@($output.HtmlPagePaths).Count -gt 0) {
        Add-SPSInventoryEvent -Message "The HTML report has more than $($reportOption.HtmlSplitThreshold) site collections, so it is split: open $($output.HtmlPath), the entry page, which links to its $(@($output.HtmlPagePaths).Count) table page(s) in the same folder. Keep the pages together. Report.HtmlSplitThreshold in the settings changes this." -Level Information
    }
    Add-SPSInventoryEvent -Message "Report pack. Sites: $($output.SitesJsonPath) | Auth: $($output.AuthJsonPath) | Workflows: $($output.WorkflowsJsonPath) | Apps: $($output.AppsJsonPath) | Publishing: $($output.PublishingJsonPath) | Permissions: $($output.PermissionsJsonPath) | IRM/Locks: $($output.IrmLocksJsonPath) | Large content: $($output.LargeContentJsonPath) | Collaboration: $($output.CollaborationJsonPath) | Alerts: $($output.AlertsJsonPath) | Alerts CSV: $($output.AlertsCsvPath) | Manifest: $($output.ManifestJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "Farm-solution report. CSV: $($solutionOutput.CsvPath) | JSON: $($solutionOutput.JsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "Content-type report. CSV: $($output.ContentTypesCsvPath) | JSON: $($output.ContentTypesJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "Managed metadata report. CSV: $($output.ManagedMetadataCsvPath) | JSON: $($output.ManagedMetadataJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "External list report. CSV: $($output.ExternalListsCsvPath) | JSON: $($output.ExternalListsJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "SharePoint alerts report. CSV: $($output.SharePointAlertsCsvPath) | JSON: $($output.SharePointAlertsJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "BCS report. CSV: $($output.BcsCsvPath) | JSON: $($output.BcsJsonPath)" -Level Information
    Add-SPSInventoryEvent -Message "Secure Store report. CSV: $($output.SecureStoreCsvPath) | JSON: $($output.SecureStoreJsonPath)" -Level Information
}
catch {
    Add-SPSInventoryEvent -Message "Inventory failed: $($_.Exception.Message)" -Level Error
    throw
}
finally {
    Stop-Transcript | Out-Null
}
