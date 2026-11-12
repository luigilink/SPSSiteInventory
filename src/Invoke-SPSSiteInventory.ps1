<#
    .SYNOPSIS
    Inventories SharePoint Server site collections and scores their migration complexity.

    .DESCRIPTION
    Invoke-SPSSiteInventory is the entry point of the SPSSiteInventory toolkit. It:

    1. bootstraps logging and validates prerequisites;
    2. loads the SharePoint commands and the inventory settings;
    3. builds the farm-solution map (WSP -> full-trust code, features) to detect custom code and,
       with -ExportSolutionPackage or -SolutionPackagePath, inspects the WSP packages and
       matches them to the farm solutions;
    4. enumerates site collections (identity + volumetry);
    5. collects the customization signals of each site and reads the Business Connectivity
       Services (BCS) definitions, the Secure Store target applications and the profile property
       mappings of the farm;
    6. scores each site from 1 (Simple) to 4 (Blocking) and assigns a migration wave; with
       TargetMode = 'SharePointOnPrem' in the settings, the same four categories read as
       Modern-ready, Light remediation, Rebuild (SPFx) and Blocked;
    7. exports the scored inventory to CSV, JSON and a self-contained HTML report, the
       farm-solution map to its own CSV and JSON, and the inspected packages to theirs, in the
       OutputFolder of the settings, or in a Reports folder next to this script when it is
       empty (the logs go to a Logs folder next to it). The folder is created when the run
       starts.

    The tool is read-only: it never modifies the farm. Run it on a farm server, as the
    farm account, in an elevated Windows PowerShell 5.1 session.

    .PARAMETER ConfigPath
    Path to the inventory settings .psd1 file. Defaults to
    .\config\inventory-settings.psd1 next to this script.

    .PARAMETER ExportSolutionPackage
    Optional switch. Saves the package (WSP) of every farm solution in a temporary folder of the
    account that runs the scan, with SolutionFile.SaveAs, inspects the packages as
    -SolutionPackagePath does, and removes the folder as soon as they are read, also after an
    error or Ctrl+C. None goes in the reports folder, which is the one that you zip and send: only
    what the inspection found is in the reports. If the process is killed, the window is closed or
    security software keeps a file open, the folder stays: the log gives its path when the scan
    saves the packages, a warning says at the end when the folder could not be removed, and you
    remove it by hand. A package that cannot be saved is a warning of the log, not the end of the
    scan. The code of the solutions is written to disk for a moment, which security software may
    notice. It can be combined with -SolutionPackagePath.

    .PARAMETER SolutionPackagePath
    Optional. WSP files, folders that hold some (their subfolders too) or folders of expanded
    packages, to inspect with Get-SPSSolutionPackageInfo: the strong name of every assembly, the
    features (also those of a solution that is not deployed), the receivers and the .NET
    framework. The packages are matched to the farm solutions, shown in the HTML report and
    written to their own CSV and JSON files. Use it for packages that you already have, or that
    you want to keep: save them from the farm in a folder that is not the reports folder, for
    example with
    Get-SPSolution | ForEach-Object { $_.SolutionFile.SaveAs((Join-Path 'D:\Packages' $_.Name)) }.
    -ExportSolutionPackage does it for you, in a temporary folder. A package that cannot be read
    is a warning of the log, not the end of the scan. Without either parameter, the scan ends by
    telling how to inspect the packages, when the farm has solutions.

    .EXAMPLE
    .\Invoke-SPSSiteInventory.ps1

    .EXAMPLE
    .\Invoke-SPSSiteInventory.ps1 -ConfigPath D:\Config\inventory-settings.psd1

    .EXAMPLE
    .\Invoke-SPSSiteInventory.ps1 -ExportSolutionPackage

    .EXAMPLE
    .\Invoke-SPSSiteInventory.ps1 -SolutionPackagePath D:\Packages
#>
#Requires -Version 5.1
[CmdletBinding()]
param
(
    [Parameter()]
    [System.String]
    $ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'config\inventory-settings.psd1'),

    [Parameter()]
    [System.String[]]
    $SolutionPackagePath,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $ExportSolutionPackage
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

    # The folder is created now, so that one that cannot be created stops the run before the scan and not when the reports are written.
    $outputFolder = & $commonModule {
        param ($Folder, $Root)
        Resolve-SPSOutputFolder -OutputFolder $Folder -ScriptRoot $Root -Create
    } $settings['OutputFolder'] $PSScriptRoot
    Add-SPSInventoryEvent -Message ("Report folder: '{0}'{1}." -f $outputFolder.Path, $(if ($outputFolder.IsDefault) { ' (OutputFolder is empty: the Reports folder next to the script)' } else { '' })) -Level Information

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

    # The packages are read now, so that a wrong path shows before the scan, and a failure here must not stop the site report.
    $solutionPackages = @()
    $packagePath = @($SolutionPackagePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    # The packages that the scan saves from the farm go in a temporary folder, never in the reports folder (the one that is zipped and sent), and are removed as soon as they are read.
    $exportFolder = $null
    $packageFolderLeft = $null
    if ($ExportSolutionPackage) {
        $exportFolder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('SPSSiteInventory-packages-' + [System.Guid]::NewGuid().ToString('N'))
    }
    try {
        $inspectPath = @($packagePath)
        $inspectLabel = @($packagePath | ForEach-Object { "'$_'" })
        if ($ExportSolutionPackage) {
            Add-SPSInventoryEvent -Message ("Saving the packages of the farm solutions in the temporary folder '{0}', to inspect them. The folder is removed as soon as they are read: if this run is stopped before that, remove it by hand." -f $exportFolder) -Level Information
            try {
                $packageExport = & $commonModule {
                    param ($Path)
                    Save-SPSFarmSolutionPackage -Path $Path
                } $exportFolder
                foreach ($exportFailure in @($packageExport.Failure)) {
                    Add-SPSInventoryEvent -Message ("The package of the farm solution '{0}' could not be saved: {1}" -f $exportFailure.Name, $exportFailure.Reason) -Level Warning
                }
                if ($packageExport.Requested -eq 0) {
                    Add-SPSInventoryEvent -Message 'The farm has no solution, so there is no package to save.' -Level Information
                }
                else {
                    Add-SPSInventoryEvent -Message ('{0} of {1} farm solution package(s) saved.' -f $packageExport.Saved, $packageExport.Requested) -Level Information
                }
                if ($packageExport.Saved -gt 0) {
                    $inspectPath += $exportFolder
                    $inspectLabel += 'the packages saved from the farm'
                }
            }
            catch {
                Add-SPSInventoryEvent -Message "The packages of the farm solutions could not be saved: $($_.Exception.Message)" -Level Warning
            }
        }
        if ($inspectPath.Count -gt 0) {
            Add-SPSInventoryEvent -Message ('Inspecting the solution packages in {0}.' -f ($inspectLabel -join ', ')) -Level Information
            try {
                $packageParams = @{ Path = $inspectPath; Recurse = $true; FarmSolutionMap = @($solutionMap) }
                if ($settings.ContainsKey('KnownMicrosoftSolutionPrefix')) {
                    $packageParams['KnownMicrosoftPrefix'] = $settings.KnownMicrosoftSolutionPrefix
                }
                $solutionPackages = @(Get-SPSSolutionPackageInfo @packageParams)
            }
            catch {
                Add-SPSInventoryEvent -Message "The solution package inspection failed: $($_.Exception.Message)" -Level Warning
            }
            # The package files are sent: the temporary folders of the scan are taken out of the text of the records, which quotes the path that an inspection could not read, before the log and the reports.
            & $commonModule {
                param ($Record, $Folder)
                Hide-SPSTemporaryPackagePath -Record $Record -Folder $Folder
            } $solutionPackages $exportFolder
            foreach ($solutionPackage in $solutionPackages) {
                if ($solutionPackage.Status -ne 'Inspected') {
                    Add-SPSInventoryEvent -Message ("Solution package '{0}' is {1}: {2}" -f $solutionPackage.PackageName, $solutionPackage.Status, $solutionPackage.Detail) -Level Warning
                }
            }
            Add-SPSInventoryEvent -Message ('{0} solution package(s) inspected: {1} custom, {2} with full-trust code, {3} not read in full.' -f $solutionPackages.Count, @($solutionPackages | Where-Object { $_.IsCustom }).Count, @($solutionPackages | Where-Object { $_.IsFullTrustCode }).Count, @($solutionPackages | Where-Object { $_.Status -ne 'Inspected' }).Count) -Level Information
        }
    }
    finally {
        if ($null -ne $exportFolder) {
            $removed = & $commonModule {
                param ($Path)
                Remove-SPSPackageWorkFolder -Path $Path
            } $exportFolder
            if (-not $removed) {
                $packageFolderLeft = $exportFolder
            }
        }
    }

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

    # The profile property mappings of the User Profile service are farm-wide too; a failure here must not stop the site report either.
    Add-SPSInventoryEvent -Message 'Reading the profile property mappings.' -Level Information
    $profileMappings = [PSCustomObject]@{ Mappings = @(); Complete = $false; Warnings = @() }
    try {
        $profileMappings = Get-SPSProfilePropertyMapping -WebApplicationUrl $settings.WebApplicationUrl
    }
    catch {
        Add-SPSInventoryEvent -Message "The profile property mapping inventory failed: $($_.Exception.Message)" -Level Warning
    }
    foreach ($profileWarning in @($profileMappings.Warnings)) {
        Add-SPSInventoryEvent -Message $profileWarning -Level Warning
    }

    if (@($sharePointAlerts | Where-Object { -not [string]::IsNullOrEmpty([string]$_.UserLoginName) }).Count -gt 0) {
        Add-SPSInventoryEvent -Message 'The SharePoint alerts files contain the login names of the alert owners, which are personal data. Set SharePointAlerts.IncludeUserLogin to $false in the settings to leave them out.' -Level Information
    }

    $solutionOutput = Export-SPSSolutionReport -InputObject @($solutionMap) -OutputFolder $outputFolder.Path -BaseName ('SPSSiteInventory-' + $settings.EnvName)
    # The package files and their section of the HTML report exist only when packages were inspected.
    $packageExportParams = @{}
    if ($solutionPackages.Count -gt 0) {
        $packageExportParams['SolutionPackages'] = @($solutionPackages)
    }
    $output = Export-SPSInventoryReport -InputObject @($scored) -OutputFolder $outputFolder.Path -BaseName ('SPSSiteInventory-' + $settings.EnvName) -EnvName $settings.EnvName -SolutionMap @($solutionMap) -ContentTypes $contentTypes -ManagedMetadataLists $managedMetadataLists -ExternalLists $externalLists -SharePointAlerts $sharePointAlerts -BcsApplications @($bcs.Applications) -BcsInventoryComplete ([bool]$bcs.Complete) -SecureStoreApplications @($secureStore.Applications) -SecureStoreInventoryComplete ([bool]$secureStore.Complete) -ProfilePropertyMappings @($profileMappings.Mappings) -ProfileInventoryComplete ([bool]$profileMappings.Complete) -SolutionJsonPath $solutionOutput.JsonPath -ExcludedPersonalSiteCount ([int]$exclusion.PersonalSites) -ExcludedSiteMasterCount ([int]$exclusion.SiteMasters) -HtmlSplitThreshold $reportOption.HtmlSplitThreshold -HtmlRowsPerPage $reportOption.HtmlRowsPerPage -TargetMode $targetMode @packageExportParams

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
    Add-SPSInventoryEvent -Message "Profile property mappings report. CSV: $($output.ProfileMappingsCsvPath) | JSON: $($output.ProfileMappingsJsonPath)" -Level Information
    if ($solutionPackages.Count -gt 0) {
        Add-SPSInventoryEvent -Message "Solution package report. CSV: $($output.SolutionPackagesCsvPath) | Assemblies: $($output.SolutionAssembliesCsvPath) | JSON: $($output.SolutionPackagesJsonPath)" -Level Information
    }
    elseif (-not $ExportSolutionPackage -and $packagePath.Count -eq 0 -and @($solutionMap).Count -gt 0) {
        Add-SPSInventoryEvent -Message ('The farm-solution report only gives what SharePoint says about each solution. The WSP packages say more: the strong name of every assembly, the features of a solution that is not deployed, the receivers and the .NET framework. To inspect them, run this script again with -ExportSolutionPackage: it saves the packages of the farm solutions in a temporary folder, reads them and removes the folder as soon as they are read, so that none goes in the reports folder. To inspect packages that you already have, give their folder to -SolutionPackagePath, or use Get-SPSSolutionPackageInfo alone. See the wiki page "Inspecting WSP packages offline".') -Level Information
    }
}
catch {
    Add-SPSInventoryEvent -Message "Inventory failed: $($_.Exception.Message)" -Level Error
    throw
}
finally {
    if ($null -ne $packageFolderLeft) {
        Add-SPSInventoryEvent -Message ("The temporary folder '{0}' still holds the packages of the farm solutions, because it could not be removed. Remove it by hand." -f $packageFolderLeft) -Level Warning
    }
    Stop-Transcript | Out-Null
}
