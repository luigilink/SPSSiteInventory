function Get-SPSSiteCustomization {
    <#
        .SYNOPSIS
        Collects the customization signals of a single site collection.

        .DESCRIPTION
        Inspects one site collection and returns the signals that drive the migration
        complexity score: 2010 vs 2013 workflows, app inventory and app-web signals,
        publishing and customized-page signals, InfoPath forms, IRM-enabled lists,
        large-content migration risks (large lists/views, checked-out files, file
        versions), site lock state, sandbox solutions, custom master page, unique
        permissions, custom event receivers, and whether the site activates a feature
        that comes from a custom farm solution (correlated through the farm-solution
        map).

        EventReceivers counts only custom event receivers (those registered from a
        non-Microsoft assembly). Out-of-the-box receivers on native lists are ignored so
        they do not inflate the score.

        Workflows are split by platform because their migration cost differs sharply:

        - Workflow2010Count counts classic SPWorkflowAssociation objects (the SharePoint
          2010 workflow platform, whose engine is retired in SharePoint Online, so those
          workflows always need a rebuild).
        - Workflow2010RunningInstanceCount counts active 2010 workflow instances where
          runtime counters are exposed by the platform.
        - Workflow2013Count counts Workflow Manager subscriptions (the SharePoint 2013
          platform), read through WorkflowServicesManager. This is best-effort: when
          Workflow Manager is not connected the count stays at 0 rather than failing.
        - Workflow2013RunningInstanceCount counts active Workflow Manager instances where
          the instance API is available.

        InfoPathFormCount counts the InfoPath-driven lists and libraries on the site
        (InfoPath form libraries, and lists whose forms were customized with InfoPath).
        InfoPath Forms Services is retired and has no equivalent in SharePoint Online, so
        those forms must be rebuilt (Power Apps) - often a migration blocker.

        IrmEnabledListCount counts lists and libraries where IRM is enabled. SiteLockState
        is the lock state of the site collection (Unlock, NoAdditions, ReadOnly, NoAccess or
        Unknown) and IsLockedSite is true for any state other than Unlock and Unknown. Only a
        NoAccess lock makes the site unreadable, so that the migration tools skip it:
        HasNoAccessLock flags it, and the example configuration treats it as blocking.
        NoAdditions and ReadOnly restrict changes, not reading, and are often a deliberate
        migration freeze.

        PublishingInfrastructureEnabled, PublishingWebCount, PublishingPageCount and
        PublishingPageLayoutCount describe classic publishing dependencies: the
        Publishing Infrastructure site feature, the webs that activate the Publishing
        feature, the items in their Pages libraries and the distinct page layouts those
        pages use. Publishing sites usually need extensive remediation, so these are
        weighted rather than blocking by default.

        CustomizedPageCount counts customized (unghosted) pages at the root of each web,
        for example a default.aspx edited with SharePoint Designer. Migration reverts
        them to their default state. Files last modified by the System Account are
        ignored, and list view and form pages are not scanned.

        CustomPermissionLevelCount counts the distinct custom permission levels defined in
        the site collection (the root web and any web with unique permission levels).
        Levels SharePoint provisions are recognized by type and by name, see the
        PermissionLevels parameter. EmailEnabledListCount counts lists with incoming
        e-mail enabled (an e-mail alias is set), a feature SharePoint Online does not
        offer. HtmlFileCount counts .htm and .html files in document libraries, but only
        when ScanHtmlFile is set because they matter only where the web application uses
        Permissive browser file handling; SharePoint Online enforces Strict, so those
        files prompt a download instead of opening in the browser. System catalogs
        (/_catalogs/) are skipped.

        ManagedMetadataListCount counts the lists and libraries with at least one visible
        managed metadata column (Enterprise Keywords included), ManagedMetadataColumnCount
        counts those columns and ManagedMetadataTermSetCount the distinct term sets they
        use. Those lists depend on the term store, so they are best migrated together with
        it. ManagedMetadataLists holds one row per list, like the SMAT Managed Metadata
        Columns report; term set IDs are read from the field definitions, so the term
        store service is not called and term set names are not resolved.

        ExternalListCount counts the external lists on the site: lists backed by a
        Business Connectivity Services (BCS) external content type, whose items stay in
        the external system. BCS is retired in SharePoint Online, so those lists and the
        BCS applications behind them cannot be migrated there.
        ExternalLists holds one row per list with the BCS binding SharePoint stores with
        it (LOB system instance, entity namespace and entity name), like the SMAT
        External List report. The binding is read from the list definition, so neither
        the Business Data Connectivity service nor the external system is called. A list
        whose binding cannot be read is still counted, so it cannot hide a blocking
        signal; its row is left out and the collection is marked partial.

        SharePointAlertCount counts the alerts on the site: the "Alert Me" subscriptions
        of every user, in every web. Migration tools do not migrate them and SharePoint
        Online retired them from July 2026, so each notification has to be replaced (a
        SharePoint rule or a Power Automate flow); the count is informational and is not
        scored by default.
        SharePointAlerts holds one row per alert, like the SMAT Alerts report: where it
        applies (web, list or item), what triggers it, how often it is sent, its status
        and its owner. The rows are capped per site (MaxAlertRowsPerSite) while the count
        stays exact; an alert that cannot be read, or rows left out by the cap, mark the
        collection partial. The login name of the owner of each alert is personal data:
        SharePointAlertSettings can turn it off, and the owners are then not looked up.

        The returned hashtable is designed to be passed straight to
        Measure-SPSSiteComplexity. CustomizationInventoryComplete is false when a signal
        cannot be read; partial results are returned with warnings rather than aborting
        collection of the remaining site data.

        ContentTypes contains web definitions and list bindings, including standard
        types. ContentTypeCount counts distinct web-definition IDs in the collection;
        ListContentTypeBindingCount counts list bindings, not distinct designs or items.
        ContentTypeInventoryComplete is false and a warning is emitted when collection
        is partial. Content-type presence alone is not a migration blocker.

        Requires the SharePoint commands (see Import-SPSSharePointCommand) and to run as
        the farm account on a farm server.

        .PARAMETER Site
        The SPSite object to inspect (from Get-SPSite or a web application's Sites
        collection).

        .PARAMETER CustomFeatureId
        Optional list of feature IDs known to come from custom farm solutions (typically
        built from Get-SPSFarmSolutionMap). A site activating one of these is flagged with
        the UsesCustomFarmFeature signal, which the scoring config can treat as blocking.

        .PARAMETER FullTrustFeatureId
        Optional list of feature IDs known to come from custom *full-trust* solutions
        (solutions that deploy a global assembly, i.e. IsFullTrustCode in the farm-solution
        map). A site activating one of these is flagged with the UsesFullTrustCode signal,
        a strong "not portable to SharePoint Online" indicator that the scoring config can
        treat as blocking.

        .PARAMETER LargeContentThresholds
        Optional thresholds for large-content parity signals:
        LargeListItemCount, LargeListViewRowLimit, CheckedOutFileCount,
        FileVersionCount, and MaxItemsForVersionScanPerLibrary. Also reads
        MaxItemsForPublishingPageScanPerLibrary, which caps how many pages per Pages
        library are read to count page layouts, and MaxItemsForHtmlFileScanPerLibrary,
        which caps how many .htm and .html files are counted per library.
        MaxAlertRowsPerSite caps how many alert rows are exported per site collection.

        .PARAMETER PermissionLevels
        Optional permission-level settings. BuiltInNames lists permission level names to
        treat as provisioned by SharePoint, in addition to the English names built in
        (View Only, Approve, Manage Hierarchy, Restricted Interfaces for Translation,
        Moderate, Records Center Web Service Submitters). Add the localized names on a
        non-English farm, otherwise those levels are reported as custom.

        .PARAMETER SharePointAlertSettings
        Optional SharePointAlerts settings. IncludeUserLogin (default $true) says whether the
        login name of the owner of each alert is collected; a value that is not a boolean is
        rejected.

        .PARAMETER ScanHtmlFile
        Counts .htm and .html files in document libraries. Set it for sites of a web
        application whose browser file handling is Permissive.

        .EXAMPLE
        $map = Get-SPSFarmSolutionMap -CustomSolutionPrefix @('contoso')
        $customIds = $map | Where-Object IsCustom | ForEach-Object FeatureIds
        $fullTrustIds = $map | Where-Object IsFullTrustCode | ForEach-Object FeatureIds
        Get-SPSSite 'https://intranet/sites/team' | ForEach-Object {
            Get-SPSSiteCustomization -Site $_ -CustomFeatureId $customIds -FullTrustFeatureId $fullTrustIds
        }
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Site,

        [Parameter()]
        [System.String[]]
        $CustomFeatureId = @(),

        [Parameter()]
        [System.String[]]
        $FullTrustFeatureId = @(),

        [Parameter()]
        [System.Collections.IDictionary]
        $LargeContentThresholds = @{},

        [Parameter()]
        [System.Collections.IDictionary]
        $PermissionLevels = @{},

        [Parameter()]
        [System.Collections.IDictionary]
        $SharePointAlertSettings = @{},

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $ScanHtmlFile
    )

    $signals = @{
        Workflow2010Count        = 0
        Workflow2010RunningInstanceCount = 0
        Workflow2013Count        = 0
        Workflow2013RunningInstanceCount = 0
        AppInstanceCount         = 0
        AppWebCount              = 0
        AppInstanceExamples      = ''
        PublishingInfrastructureEnabled = $false
        PublishingWebCount       = 0
        PublishingPageCount      = 0
        PublishingPageLayoutCount = 0
        PublishingPageLayoutExamples = ''
        CustomizedPageCount      = 0
        CustomizedPageExamples   = ''
        CustomPermissionLevelCount = 0
        CustomPermissionLevelExamples = ''
        EmailEnabledListCount    = 0
        EmailEnabledListExamples = ''
        HtmlFileCount            = 0
        HtmlFileExamples         = ''
        ManagedMetadataListCount = 0
        ManagedMetadataColumnCount = 0
        ManagedMetadataTermSetCount = 0
        ManagedMetadataExamples  = ''
        ExternalListCount        = 0
        ExternalListExamples     = ''
        SharePointAlertCount     = 0
        InfoPathFormCount        = 0
        IrmEnabledListCount      = 0
        IsLargeSite              = $false
        LargeListCount           = 0
        LargeListExamples        = ''
        LargeListViewCount       = 0
        LargeListViewExamples    = ''
        CheckedOutFileCount      = 0
        CheckedOutFileExamples   = ''
        FileVersionCount         = 0
        FileVersionExamples      = ''
        IsLockedSite             = $false
        HasNoAccessLock          = $false
        SiteLockState            = 'Unknown'
        SandboxSolutions         = 0
        CustomMasterPage         = $false
        UniquePermissionsCount   = 0
        EventReceivers           = 0
        UsesCustomFarmFeature    = $false
        UsesFullTrustCode        = $false
        CustomizationInventoryComplete = $true
        ContentTypeCount         = 0
        ListContentTypeBindingCount = 0
        ContentTypeInventoryComplete = $true
    }
    $contentTypes = [System.Collections.Generic.List[object]]::new()
    $contentTypeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $largeListExamples = [System.Collections.Generic.List[string]]::new()
    $largeListViewExamples = [System.Collections.Generic.List[string]]::new()
    $checkedOutFileExamples = [System.Collections.Generic.List[string]]::new()
    $fileVersionExamples = [System.Collections.Generic.List[string]]::new()
    $appInstanceExamples = [System.Collections.Generic.List[string]]::new()
    $customizedPageExamples = [System.Collections.Generic.List[string]]::new()
    $customPermissionLevels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $customPermissionLevelExamples = [System.Collections.Generic.List[string]]::new()
    $emailEnabledListExamples = [System.Collections.Generic.List[string]]::new()
    $htmlFileExamples = [System.Collections.Generic.List[string]]::new()
    $managedMetadataLists = [System.Collections.Generic.List[object]]::new()
    $managedMetadataExamples = [System.Collections.Generic.List[string]]::new()
    $managedMetadataTermSets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $externalLists = [System.Collections.Generic.List[object]]::new()
    $externalListExamples = [System.Collections.Generic.List[string]]::new()
    $externalListCount = 0
    $sharePointAlerts = [System.Collections.Generic.List[object]]::new()
    $alertUserLogins = @{}
    $includeAlertUserLogin = (Get-SPSSharePointAlertOption -Settings $SharePointAlertSettings).IncludeUserLogin
    $alertRowsLeftOut = $false
    $unreadableAlertCount = 0
    $maxAlertWarnings = 5
    $publishingLayouts = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $largeListItemThreshold = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'LargeListItemCount' -DefaultValue 5000 -MinimumValue 1)
    $largeListViewRowLimitThreshold = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'LargeListViewRowLimit' -DefaultValue 5000 -MinimumValue 1)
    $checkedOutFileThreshold = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'CheckedOutFileCount' -DefaultValue 1 -MinimumValue 1)
    $fileVersionThreshold = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'FileVersionCount' -DefaultValue 50 -MinimumValue 1)
    $maxItemsForVersionScan = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'MaxItemsForVersionScanPerLibrary' -DefaultValue 2000 -MinimumValue 1)
    $maxPublishingPageScan = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'MaxItemsForPublishingPageScanPerLibrary' -DefaultValue 2000 -MinimumValue 1)
    # Well-known SharePoint Server IDs: Publishing Infrastructure (site feature),
    # Publishing (web feature) and the Pages library list template.
    $publishingInfrastructureFeatureId = 'f6924d36-2fa8-4f0b-b16d-06b7250180fa'
    $publishingWebFeatureId = '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'
    $pagesLibraryTemplateId = 850
    $maxHtmlFileScan = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'MaxItemsForHtmlFileScanPerLibrary' -DefaultValue 2000 -MinimumValue 1)
    $maxAlertRows = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'MaxAlertRowsPerSite' -DefaultValue 5000 -MinimumValue 1)
    # Names SharePoint provisions with a None type, in English; PermissionLevels.BuiltInNames adds localized ones.
    $builtInPermissionLevelNames = @(
        'View Only', 'Approve', 'Manage Hierarchy', 'Restricted Interfaces for Translation',
        'Moderate', 'Records Center Web Service Submitters'
    )
    if ($PermissionLevels.Contains('BuiltInNames') -and $null -ne $PermissionLevels['BuiltInNames']) {
        $builtInPermissionLevelNames += @($PermissionLevels['BuiltInNames'] | ForEach-Object { [string]$_ })
    }
    $setQueryProperty = {
        param([object]$QueryObject, [string]$PropertyName, [object]$Value)
        if ($null -ne $QueryObject.PSObject.Properties[$PropertyName]) {
            $QueryObject.$PropertyName = $Value
        }
        else {
            $QueryObject | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $Value -Force
        }
    }
    $newPagedQuery = {
        param([uint32]$RowLimit, [string]$QueryText = '')
        $spQueryType = [Type]::GetType('Microsoft.SharePoint.SPQuery, Microsoft.SharePoint', $false)
        $queryObject = if ($null -ne $spQueryType) { New-Object -TypeName Microsoft.SharePoint.SPQuery } else { [PSCustomObject]@{} }
        & $setQueryProperty $queryObject 'RowLimit' $RowLimit
        & $setQueryProperty $queryObject 'ViewAttributes' "Scope='RecursiveAll'"
        if ($QueryText) {
            & $setQueryProperty $queryObject 'Query' $QueryText
        }
        & $setQueryProperty $queryObject 'ListItemCollectionPosition' $null
        return $queryObject
    }
    $getBatchItems = {
        param([object]$Batch)
        if ($null -eq $Batch) { return @() }
        if ($null -ne $Batch.PSObject.Properties['Items']) {
            return @($Batch.Items)
        }
        if ($Batch -is [System.Collections.IEnumerable] -and -not ($Batch -is [string])) {
            return @($Batch)
        }
        return @()
    }
    $getBatchPosition = {
        param([object]$Batch)
        if ($null -eq $Batch) { return $null }
        if ($null -ne $Batch.PSObject.Properties['ListItemCollectionPosition']) {
            return $Batch.ListItemCollectionPosition
        }
        return $null
    }
    $getFileIdentity = {
        param([object]$FileObject, [object]$FallbackObject)
        if ($FileObject -is [string] -and -not [string]::IsNullOrWhiteSpace($FileObject)) {
            return [string]$FileObject
        }
        if ($null -ne $FileObject) {
            if ($null -ne $FileObject.PSObject.Properties['ServerRelativeUrl'] -and $FileObject.ServerRelativeUrl) { return [string]$FileObject.ServerRelativeUrl }
            if ($null -ne $FileObject.PSObject.Properties['Url'] -and $FileObject.Url) { return [string]$FileObject.Url }
            if ($null -ne $FileObject.PSObject.Properties['UniqueId'] -and $FileObject.UniqueId) { return [string]$FileObject.UniqueId }
            if ($null -ne $FileObject.PSObject.Properties['Name'] -and $FileObject.Name) { return [string]$FileObject.Name }
        }
        if ($null -ne $FallbackObject) {
            if ($null -ne $FallbackObject.PSObject.Properties['Url'] -and $FallbackObject.Url) { return [string]$FallbackObject.Url }
            if ($null -ne $FallbackObject.PSObject.Properties['ServerRelativeUrl'] -and $FallbackObject.ServerRelativeUrl) { return [string]$FallbackObject.ServerRelativeUrl }
            if ($null -ne $FallbackObject.PSObject.Properties['Name'] -and $FallbackObject.Name) { return [string]$FallbackObject.Name }
        }
        return $null
    }

    try {
        $signals.SandboxSolutions = @($Site.Solutions).Count
    }
    catch {
        $signals.CustomizationInventoryComplete = $false
        Write-Warning -Message "Could not read sandbox solutions for site collection '$($Site.Url)': $($_.Exception.Message)"
    }

    try {
        $readLockedProperty = $Site.PSObject.Properties['ReadLocked']
        $writeLockedProperty = $Site.PSObject.Properties['WriteLocked']
        $readOnlyProperty = $Site.PSObject.Properties['ReadOnly']

        $hasReadLocked = $null -ne $readLockedProperty -and $null -ne $readLockedProperty.Value
        $hasWriteLocked = $null -ne $writeLockedProperty -and $null -ne $writeLockedProperty.Value
        $hasReadOnly = $null -ne $readOnlyProperty -and $null -ne $readOnlyProperty.Value

        $lockState = 'Unknown'
        if ($hasReadLocked -and [bool]$Site.ReadLocked) {
            $lockState = 'NoAccess'
        }
        elseif ($hasWriteLocked -and [bool]$Site.WriteLocked) {
            $lockState = 'NoAdditions'
        }
        elseif ($hasReadOnly -and [bool]$Site.ReadOnly) {
            $lockState = 'ReadOnly'
        }
        elseif ($hasReadLocked -and $hasWriteLocked -and $hasReadOnly) {
            $lockState = 'Unlock'
        }

        $signals.SiteLockState = $lockState
        $signals.IsLockedSite = -not (
            $lockState.Equals('Unlock', [System.StringComparison]::OrdinalIgnoreCase) -or
            $lockState.Equals('Unknown', [System.StringComparison]::OrdinalIgnoreCase))
        $signals.HasNoAccessLock = $lockState.Equals('NoAccess', [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        $signals.CustomizationInventoryComplete = $false
        $signals.SiteLockState = 'Unknown'
        Write-Warning -Message "Could not read lock state for site collection '$($Site.Url)': $($_.Exception.Message)"
    }

    $customFeatureSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$CustomFeatureId, [System.StringComparer]::OrdinalIgnoreCase)
    $fullTrustFeatureSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$FullTrustFeatureId, [System.StringComparer]::OrdinalIgnoreCase)

    # Site-scoped features live on the site collection, not on any web. Inspect them once
    # here so a full-trust WSP that ships a Site-scope feature is not missed (SPWeb.Features
    # below only covers Web-scope features).
    if ($customFeatureSet.Count -gt 0 -or $fullTrustFeatureSet.Count -gt 0) {
        try {
            foreach ($feature in $Site.Features) {
                $featureId = $feature.DefinitionId.ToString()
                if ($customFeatureSet.Contains($featureId)) { $signals.UsesCustomFarmFeature = $true }
                if ($fullTrustFeatureSet.Contains($featureId)) { $signals.UsesFullTrustCode = $true }
                if ($signals.UsesCustomFarmFeature -and $signals.UsesFullTrustCode) { break }
            }
        }
        catch {
            $signals.CustomizationInventoryComplete = $false
            Write-Warning -Message "Could not read site-scoped features for site collection '$($Site.Url)': $($_.Exception.Message)"
        }
    }

    try {
        $signals.PublishingInfrastructureEnabled = Test-SPSFeatureActivated -Feature $Site.Features -FeatureId $publishingInfrastructureFeatureId
    }
    catch {
        $signals.CustomizationInventoryComplete = $false
        Write-Warning -Message "Could not read the publishing infrastructure feature for site collection '$($Site.Url)': $($_.Exception.Message)"
    }

    try {
        $siteWebs = $Site.AllWebs
        if ($null -eq $siteWebs) {
            throw "The web collection is unavailable for '$($Site.Url)'."
        }
        foreach ($web in $siteWebs) {
            try {
                try {
                    $webContentTypes = $web.ContentTypes
                    if ($null -eq $webContentTypes) {
                        throw "Content-type definitions are unavailable on '$($web.Url)'."
                    }
                    foreach ($contentType in $webContentTypes) {
                        $record = ConvertTo-SPSContentTypeRecord -ContentType $contentType -SiteUrl $Site.Url -WebUrl $web.Url -Scope Web
                        $contentTypes.Add($record)
                        [void]$contentTypeIds.Add($record.ContentTypeId)
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    $signals.ContentTypeInventoryComplete = $false
                    Write-Warning -Message "Content-type definitions could not be fully read on '$($web.Url)': $($_.Exception.Message)"
                }

                try {
                    $isAppWeb = $false
                    if ($null -ne $web.PSObject.Properties['IsAppWeb'] -and $null -ne $web.IsAppWeb) {
                        $isAppWeb = [bool]$web.IsAppWeb
                    }
                    elseif ($null -ne $web.PSObject.Properties['WebTemplate'] -and $web.WebTemplate) {
                        $isAppWeb = ([string]$web.WebTemplate).Equals('APP', [System.StringComparison]::OrdinalIgnoreCase)
                    }

                    if ($isAppWeb) {
                        $signals.AppWebCount++
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    Write-Warning -Message "Could not read app-web state on '$($web.Url)': $($_.Exception.Message)"
                }

                try {
                    $webAppInstances = @(Get-SPAppInstance -Web $web -ErrorAction Stop)
                    foreach ($appInstance in $webAppInstances) {
                        if ($null -eq $appInstance) {
                            continue
                        }

                        $signals.AppInstanceCount++
                        if ($appInstanceExamples.Count -ge 5) {
                            continue
                        }

                        $appName = ''
                        foreach ($propertyName in @('Title', 'DisplayName', 'AppPrincipalTitle', 'ProductTitle', 'Name')) {
                            if ($null -ne $appInstance.PSObject.Properties[$propertyName] -and $appInstance.$propertyName) {
                                $appName = [string]$appInstance.$propertyName
                                break
                            }
                        }
                        if ([string]::IsNullOrWhiteSpace($appName) -and
                            $null -ne $appInstance.PSObject.Properties['AppId'] -and $appInstance.AppId) {
                            $appName = [string]$appInstance.AppId
                        }
                        if ([string]::IsNullOrWhiteSpace($appName)) {
                            $appName = 'Unknown app instance'
                        }

                        $appInstanceExamples.Add(('{0} ({1})' -f $appName, $web.Url))
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    Write-Warning -Message "Could not read app instances on '$($web.Url)': $($_.Exception.Message)"
                }

                $isPublishingWeb = $false
                try {
                    $isPublishingWeb = Test-SPSFeatureActivated -Feature $web.Features -FeatureId $publishingWebFeatureId
                    if ($isPublishingWeb) {
                        $signals.PublishingWebCount++
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    Write-Warning -Message "Could not read the publishing feature on '$($web.Url)': $($_.Exception.Message)"
                }

                try {
                    # A getter failure surfaces as $null, so an unreadable collection must not look empty.
                    $rootFiles = $web.Files
                    if ($null -eq $rootFiles) {
                        throw "The root file collection is unavailable on '$($web.Url)'."
                    }
                    foreach ($rootFile in $rootFiles) {
                        try {
                            if (-not (Test-SPSCustomizedPageFile -File $rootFile)) {
                                continue
                            }

                            $signals.CustomizedPageCount++
                            $pageIdentity = [string](& $getFileIdentity $rootFile $null)
                            if (-not [string]::IsNullOrWhiteSpace($pageIdentity) -and $customizedPageExamples.Count -lt 5) {
                                $customizedPageExamples.Add($pageIdentity)
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            $fileLabel = [string](& $getFileIdentity $rootFile $null)
                            if ([string]::IsNullOrWhiteSpace($fileLabel)) {
                                $fileLabel = 'an unidentified file'
                            }
                            Write-Warning -Message "Could not read the customized page status of '$fileLabel' at the root of '$($web.Url)': $($_.Exception.Message)"
                        }
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    Write-Warning -Message "Could not read customized pages at the root of '$($web.Url)': $($_.Exception.Message)"
                }

                try {
                    $isRootWeb = $web.IsRootWeb
                    $hasUniqueDefinitions = $web.HasUniqueRoleDefinitions
                    if ($null -eq $isRootWeb -or $null -eq $hasUniqueDefinitions) {
                        throw "The permission level ownership could not be read on '$($web.Url)'."
                    }

                    # A web that inherits its permission levels shares its parent's, so only owners are read.
                    if ($isRootWeb -or $hasUniqueDefinitions) {
                        $roleDefinitions = $web.RoleDefinitions
                        if ($null -eq $roleDefinitions) {
                            throw "The permission levels are unavailable on '$($web.Url)'."
                        }
                        foreach ($roleDefinition in $roleDefinitions) {
                            try {
                                if (-not (Test-SPSCustomPermissionLevel -RoleDefinition $roleDefinition -BuiltInName $builtInPermissionLevelNames)) {
                                    continue
                                }

                                $levelName = [string]$roleDefinition.Name
                                if ($customPermissionLevels.Add($levelName) -and $customPermissionLevelExamples.Count -lt 5) {
                                    $customPermissionLevelExamples.Add(('{0} ({1})' -f $levelName, $web.Url))
                                }
                            }
                            catch {
                                $signals.CustomizationInventoryComplete = $false
                                Write-Warning -Message "Could not classify a permission level on '$($web.Url)': $($_.Exception.Message)"
                            }
                        }
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    Write-Warning -Message "Could not read the permission levels on '$($web.Url)': $($_.Exception.Message)"
                }

                # SharePoint 2010 platform: classic workflow associations at web and list scope.
                # Keep definition counts tied to active associations only, but include historical
                # associations for running-instance totals because previous versions can still run.
                $allWebWorkflowAssociations = @($web.WorkflowAssociations)
                $webWorkflowAssociations = @(Get-SPSActiveWorkflowAssociations -WorkflowAssociations $allWebWorkflowAssociations)
                $signals.Workflow2010Count += $webWorkflowAssociations.Count
                $signals.Workflow2010RunningInstanceCount += Get-SPSWorkflowAssociationRunningCount -WorkflowAssociations $allWebWorkflowAssociations

                try {
                    $webLists = $web.Lists
                    if ($null -eq $webLists) {
                        throw "The list collection is unavailable on '$($web.Url)'."
                    }
                    foreach ($list in $webLists) {
                        try {
                            $listContentTypes = $list.ContentTypes
                            if ($null -eq $listContentTypes) {
                                throw "Content-type bindings are unavailable on list '$($list.Title)'."
                            }
                            foreach ($contentType in $listContentTypes) {
                                $record = ConvertTo-SPSContentTypeRecord -ContentType $contentType -SiteUrl $Site.Url -WebUrl $web.Url -Scope List -ListTitle $list.Title -ListUrl $list.RootFolder.ServerRelativeUrl
                                $contentTypes.Add($record)
                                $signals.ListContentTypeBindingCount++
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            $signals.ContentTypeInventoryComplete = $false
                            Write-Warning -Message "Content-type bindings could not be fully read on list '$($list.Title)' in '$($web.Url)': $($_.Exception.Message)"
                        }

                        $allListWorkflowAssociations = @($list.WorkflowAssociations)
                        $listWorkflowAssociations = @(Get-SPSActiveWorkflowAssociations -WorkflowAssociations $allListWorkflowAssociations)
                        $signals.Workflow2010Count += $listWorkflowAssociations.Count
                        $signals.Workflow2010RunningInstanceCount += Get-SPSWorkflowAssociationRunningCount -WorkflowAssociations $allListWorkflowAssociations

                        # Count only custom event receivers. Out-of-the-box lists carry many
                        # native receivers from Microsoft assemblies that are not a migration
                        # concern; counting them inflates the score and wrongly promotes stock sites.
                        foreach ($receiver in $list.EventReceivers) {
                            if (Test-SPSCustomAssembly -Assembly $receiver.Assembly) {
                                $signals.EventReceivers++
                            }
                        }

                        # InfoPath forms use an XMLForm library or _ipfs_* root-folder markers.
                        $listTitle = $list.Title
                        try {
                            if ([string]$list.BaseTemplate -eq 'XMLForm') {
                                $signals.InfoPathFormCount++
                            }
                            else {
                                $listProperties = $list.RootFolder.Properties
                                if ($listProperties -and $listProperties.ContainsKey('_ipfs_infopathenabled') -and
                                    [string]$listProperties['_ipfs_infopathenabled'] -eq 'True') {
                                    $signals.InfoPathFormCount++
                                }
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            Write-Warning -Message "Could not read InfoPath state on list '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                        }

                        try {
                            $irmEnabled = $false
                            $irmEnabledProperty = $list.PSObject.Properties['IrmEnabled']
                            if ($null -ne $irmEnabledProperty -and $null -ne $list.IrmEnabled) {
                                $irmEnabled = [bool]$list.IrmEnabled
                            }
                            elseif ($null -ne $list.PSObject.Properties['InformationRightsManagementSettings'] -and
                                $null -ne $list.InformationRightsManagementSettings) {
                                $irmSettings = $list.InformationRightsManagementSettings
                                if ($null -ne $irmSettings.PSObject.Properties['IrmEnabled'] -and
                                    $null -ne $irmSettings.IrmEnabled) {
                                    $irmEnabled = [bool]$irmSettings.IrmEnabled
                                }
                                elseif ($null -ne $irmSettings.PSObject.Properties['Enable'] -and
                                    $null -ne $irmSettings.Enable) {
                                    $irmEnabled = [bool]$irmSettings.Enable
                                }
                            }

                            if ($irmEnabled) {
                                $signals.IrmEnabledListCount++
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            Write-Warning -Message "Could not read IRM state on list '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                        }

                        $listItemCount = $null
                        try {
                            if ($null -eq $list.PSObject.Properties['ItemCount']) {
                                throw "List item count is unavailable on '$listTitle'."
                            }
                            $listItemCount = [int]$list.ItemCount
                            if ($listItemCount -ge $largeListItemThreshold) {
                                $signals.LargeListCount++
                                if ($largeListExamples.Count -lt 5) {
                                    $largeListExamples.Add(('{0} ({1})' -f $listTitle, $listItemCount))
                                }
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            Write-Warning -Message "Could not read list item count on '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                        }

                        try {
                            $views = $list.Views
                            if ($null -eq $views) {
                                throw "List views are unavailable on '$listTitle'."
                            }
                            if ($null -ne $listItemCount -and $listItemCount -ge $largeListItemThreshold) {
                                foreach ($view in $views) {
                                    $rowLimit = 0
                                    if ($null -ne $view.PSObject.Properties['RowLimit'] -and $null -ne $view.RowLimit) {
                                        $rowLimit = [int]$view.RowLimit
                                    }
                                    if ($rowLimit -ge $largeListViewRowLimitThreshold) {
                                        $signals.LargeListViewCount++
                                        if ($largeListViewExamples.Count -lt 5) {
                                            $viewTitle = if ($view.PSObject.Properties['Title']) { [string]$view.Title } else { 'Unnamed view' }
                                            $largeListViewExamples.Add(('{0}/{1} ({2})' -f $listTitle, $viewTitle, $rowLimit))
                                        }
                                    }
                                }
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            Write-Warning -Message "Could not read list views on '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                        }

                        $isDocumentLibrary = [string]$list.BaseTemplate -eq '101' -or
                            ($null -ne $list.PSObject.Properties['BaseType'] -and [string]$list.BaseType -eq 'DocumentLibrary')
                        $libraryCheckedOutKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        try {
                            if ($null -ne $list.PSObject.Properties['CheckedOutFiles'] -and $null -ne $list.CheckedOutFiles) {
                                foreach ($checkedOutFile in @($list.CheckedOutFiles)) {
                                    $fileKey = & $getFileIdentity $checkedOutFile $null
                                    if (-not [string]::IsNullOrWhiteSpace($fileKey)) {
                                        [void]$libraryCheckedOutKeys.Add($fileKey)
                                    }
                                }
                            }

                            if ($isDocumentLibrary -and $null -ne $list.PSObject.Methods['GetItems']) {
                                $checkoutQuery = & $newPagedQuery -RowLimit 200 -QueryText '<Where><IsNotNull><FieldRef Name="CheckoutUser" /></IsNotNull></Where>'
                                $checkoutPosition = $null
                                do {
                                    & $setQueryProperty $checkoutQuery 'ListItemCollectionPosition' $checkoutPosition
                                    $checkoutBatch = $list.GetItems($checkoutQuery)
                                    foreach ($checkedOutItem in (& $getBatchItems $checkoutBatch)) {
                                        $itemFile = if ($null -ne $checkedOutItem.PSObject.Properties['File']) { $checkedOutItem.File } else { $null }
                                        $fileKey = & $getFileIdentity $itemFile $checkedOutItem
                                        if (-not [string]::IsNullOrWhiteSpace($fileKey)) {
                                            [void]$libraryCheckedOutKeys.Add($fileKey)
                                        }
                                    }
                                    $checkoutPosition = & $getBatchPosition $checkoutBatch
                                } while ($null -ne $checkoutPosition)
                            }
                            elseif ($isDocumentLibrary -and $null -ne $list.PSObject.Properties['Items'] -and $null -ne $list.Items) {
                                foreach ($checkedOutItem in @($list.Items)) {
                                    $itemFile = if ($null -ne $checkedOutItem.PSObject.Properties['File']) { $checkedOutItem.File } else { $null }
                                    if ($null -eq $itemFile) { continue }
                                    $isCheckedOut = $false
                                    if ($null -ne $itemFile.PSObject.Properties['CheckOutType'] -and
                                        $null -ne $itemFile.CheckOutType -and
                                        [string]$itemFile.CheckOutType -ne '' -and
                                        [string]$itemFile.CheckOutType -ne 'None' -and
                                        [string]$itemFile.CheckOutType -ne '0') {
                                        $isCheckedOut = $true
                                    }
                                    elseif ($null -ne $itemFile.PSObject.Properties['CheckoutUser'] -and $null -ne $itemFile.CheckoutUser) {
                                        $isCheckedOut = $true
                                    }
                                    elseif ($null -ne $itemFile.PSObject.Properties['CheckOutUser'] -and $null -ne $itemFile.CheckOutUser) {
                                        $isCheckedOut = $true
                                    }
                                    elseif ($null -ne $checkedOutItem.PSObject.Properties['CheckoutUser'] -and $null -ne $checkedOutItem.CheckoutUser) {
                                        $isCheckedOut = $true
                                    }

                                    if ($isCheckedOut) {
                                        $fileKey = & $getFileIdentity $itemFile $checkedOutItem
                                        if (-not [string]::IsNullOrWhiteSpace($fileKey)) {
                                            [void]$libraryCheckedOutKeys.Add($fileKey)
                                        }
                                    }
                                }
                            }

                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            Write-Warning -Message "Could not read checked-out files on '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                        }
                        finally {
                            $checkedOutFilesCount = $libraryCheckedOutKeys.Count
                            $signals.CheckedOutFileCount += $checkedOutFilesCount
                            if ($checkedOutFilesCount -ge $checkedOutFileThreshold -and $checkedOutFileExamples.Count -lt 5) {
                                $checkedOutFileExamples.Add(('{0} ({1})' -f $listTitle, $checkedOutFilesCount))
                            }
                        }

                        try {
                            if ($isDocumentLibrary) {
                                $scanCount = 0
                                $hasUnscannedItems = $false
                                if ($null -ne $list.PSObject.Methods['GetItems']) {
                                    $versionQuery = & $newPagedQuery -RowLimit 200
                                    $versionPosition = $null
                                    do {
                                        & $setQueryProperty $versionQuery 'ListItemCollectionPosition' $versionPosition
                                        $versionBatch = $list.GetItems($versionQuery)
                                        foreach ($item in (& $getBatchItems $versionBatch)) {
                                            if ($scanCount -ge $maxItemsForVersionScan) {
                                                $hasUnscannedItems = $true
                                                break
                                            }
                                            $scanCount++
                                            if ($null -eq $item.PSObject.Properties['File'] -or $null -eq $item.File) {
                                                continue
                                            }
                                            $fileVersionCount = @($item.File.Versions).Count
                                            if ($fileVersionCount -ge $fileVersionThreshold) {
                                                $signals.FileVersionCount++
                                                if ($fileVersionExamples.Count -lt 5) {
                                                    $fileUrl = & $getFileIdentity $item.File $item
                                                    $fileVersionExamples.Add(('{0} ({1})' -f $fileUrl, $fileVersionCount))
                                                }
                                            }
                                        }
                                        $versionPosition = & $getBatchPosition $versionBatch
                                        if ($scanCount -ge $maxItemsForVersionScan -and $null -ne $versionPosition) {
                                            $hasUnscannedItems = $true
                                        }
                                    } while ($null -ne $versionPosition -and $scanCount -lt $maxItemsForVersionScan)
                                }
                                else {
                                    foreach ($item in @($list.Items)) {
                                        if ($scanCount -ge $maxItemsForVersionScan) {
                                            $hasUnscannedItems = $true
                                            break
                                        }
                                        $scanCount++
                                        if ($null -eq $item.PSObject.Properties['File'] -or $null -eq $item.File) {
                                            continue
                                        }
                                        $fileVersionCount = @($item.File.Versions).Count
                                        if ($fileVersionCount -ge $fileVersionThreshold) {
                                            $signals.FileVersionCount++
                                            if ($fileVersionExamples.Count -lt 5) {
                                                $fileUrl = & $getFileIdentity $item.File $item
                                                $fileVersionExamples.Add(('{0} ({1})' -f $fileUrl, $fileVersionCount))
                                            }
                                        }
                                    }
                                }

                                if ($hasUnscannedItems) {
                                    $signals.CustomizationInventoryComplete = $false
                                    Write-Warning -Message "File-version scan stopped on '$listTitle' in web '$($web.Url)' after $maxItemsForVersionScan item(s). Increase LargeContentThresholds.MaxItemsForVersionScanPerLibrary to scan more items."
                                }
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            Write-Warning -Message "Could not scan file versions on '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                        }

                        $isPagesLibrary = $false
                        if ($isPublishingWeb) {
                            try {
                                $baseTemplate = $list.BaseTemplate
                                if ($null -eq $baseTemplate) {
                                    throw "The list template is unavailable on '$listTitle'."
                                }
                                $isPagesLibrary = [int]$baseTemplate -eq $pagesLibraryTemplateId
                            }
                            catch {
                                $signals.CustomizationInventoryComplete = $false
                                Write-Warning -Message "Could not read the list template on '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                            }
                        }

                        if ($isPagesLibrary) {
                            try {
                                $pagesItemCount = $list.ItemCount
                                if ($null -eq $pagesItemCount) {
                                    $signals.CustomizationInventoryComplete = $false
                                    Write-Warning -Message "The item count is unavailable on Pages library '$listTitle' in web '$($web.Url)'; PublishingPageCount may be understated."
                                }
                                else {
                                    $signals.PublishingPageCount += [int]$pagesItemCount
                                }

                                # Files only (FSObjType 0) and just the layout column keep the scan light.
                                $pageQuery = & $newPagedQuery -RowLimit 200 -QueryText '<Where><Eq><FieldRef Name="FSObjType" /><Value Type="Integer">0</Value></Eq></Where>'
                                & $setQueryProperty $pageQuery 'ViewFields' '<FieldRef Name="PublishingPageLayout" />'
                                & $setQueryProperty $pageQuery 'ViewFieldsOnly' $true
                                $pageScanCount = 0
                                $pagesWithLayout = 0
                                $hasUnscannedPages = $false
                                $pagePosition = $null
                                do {
                                    & $setQueryProperty $pageQuery 'ListItemCollectionPosition' $pagePosition
                                    $pageBatch = $list.GetItems($pageQuery)
                                    foreach ($pageItem in (& $getBatchItems $pageBatch)) {
                                        if ($pageScanCount -ge $maxPublishingPageScan) {
                                            $hasUnscannedPages = $true
                                            break
                                        }
                                        $pageScanCount++
                                        $layoutIdentity = ConvertTo-SPSPageLayoutIdentity -LayoutValue $pageItem['PublishingPageLayout']
                                        if ($null -eq $layoutIdentity) {
                                            continue
                                        }
                                        $pagesWithLayout++
                                        if ($publishingLayouts.ContainsKey($layoutIdentity.Key)) {
                                            $publishingLayouts[$layoutIdentity.Key].PageCount++
                                        }
                                        else {
                                            $publishingLayouts[$layoutIdentity.Key] = [PSCustomObject]@{ Name = $layoutIdentity.Name; PageCount = 1 }
                                        }
                                    }
                                    $pagePosition = & $getBatchPosition $pageBatch
                                    if ($pageScanCount -ge $maxPublishingPageScan -and $null -ne $pagePosition) {
                                        $hasUnscannedPages = $true
                                    }
                                } while ($null -ne $pagePosition -and $pageScanCount -lt $maxPublishingPageScan)

                                if ($hasUnscannedPages) {
                                    $signals.CustomizationInventoryComplete = $false
                                    Write-Warning -Message "Publishing page layout scan stopped on '$listTitle' in web '$($web.Url)' after $maxPublishingPageScan item(s). Increase LargeContentThresholds.MaxItemsForPublishingPageScanPerLibrary to scan more pages."
                                }
                                # A failed field read comes back as $null, so a library where no page reports a layout is suspect.
                                if ($pageScanCount -gt 0 -and $pagesWithLayout -eq 0) {
                                    $signals.CustomizationInventoryComplete = $false
                                    Write-Warning -Message "No page layout could be read from the $pageScanCount page(s) scanned on '$listTitle' in web '$($web.Url)'; PublishingPageLayoutCount may be understated."
                                }
                            }
                            catch {
                                $signals.CustomizationInventoryComplete = $false
                                Write-Warning -Message "Could not scan publishing pages on '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                            }
                        }

                        try {
                            # The alias says e-mail is enabled (CanReceiveEmail only says the type supports it).
                            # A null alias is valid, so read it strictly to tell it from a failed read.
                            $emailAlias = Get-SPSPropertyValue -InputObject $list -Name 'EmailAlias'
                            if (-not [string]::IsNullOrWhiteSpace([string]$emailAlias)) {
                                $signals.EmailEnabledListCount++
                                if ($emailEnabledListExamples.Count -lt 5) {
                                    $emailEnabledListExamples.Add(('{0} ({1})' -f $listTitle, $list.RootFolder.ServerRelativeUrl))
                                }
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            Write-Warning -Message "Could not read the incoming e-mail setting on list '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                        }

                        try {
                            $managedMetadataRecord = ConvertTo-SPSManagedMetadataListRecord -List $list -SiteUrl $Site.Url -WebUrl $web.Url
                            if ($null -ne $managedMetadataRecord) {
                                $managedMetadataLists.Add($managedMetadataRecord)
                                $signals.ManagedMetadataColumnCount += $managedMetadataRecord.ManagedMetadataColumnCount
                                foreach ($termSetId in ($managedMetadataRecord.TermSetIds -split '; ')) {
                                    if ($termSetId) {
                                        [void]$managedMetadataTermSets.Add($termSetId)
                                    }
                                }
                                if ($managedMetadataExamples.Count -lt 5) {
                                    $managedMetadataExamples.Add(('{0} ({1})' -f $listTitle, ($managedMetadataRecord.ManagedMetadataColumns -replace '; ', ', ')))
                                }
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            Write-Warning -Message "Could not read the managed metadata columns on list '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                        }

                        try {
                            if (Test-SPSExternalList -List $list) {
                                # Count the list before reading its binding: an unreadable binding must not hide a blocking signal.
                                $externalListCount++
                                $externalListExample = '{0} (binding unreadable)' -f $listTitle
                                try {
                                    $externalListRecord = ConvertTo-SPSExternalListRecord -List $list -SiteUrl $Site.Url -WebUrl $web.Url
                                    $externalLists.Add($externalListRecord)
                                    $externalListExample = '{0} ({1}.{2})' -f $listTitle, $externalListRecord.EntityNamespace, $externalListRecord.Entity
                                }
                                catch {
                                    $signals.CustomizationInventoryComplete = $false
                                    Write-Warning -Message "Could not read the external data source of list '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                                }
                                if ($externalListExamples.Count -lt 5) {
                                    $externalListExamples.Add($externalListExample)
                                }
                            }
                        }
                        catch {
                            $signals.CustomizationInventoryComplete = $false
                            Write-Warning -Message "Could not read the external data source of list '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                        }

                        if ($ScanHtmlFile -and $isDocumentLibrary -and [string]$list.RootFolder.ServerRelativeUrl -notmatch '/_catalogs/') {
                            try {
                                $htmlQuery = & $newPagedQuery -RowLimit 200 -QueryText '<Where><Or><Eq><FieldRef Name="File_x0020_Type" /><Value Type="Text">htm</Value></Eq><Eq><FieldRef Name="File_x0020_Type" /><Value Type="Text">html</Value></Eq></Or></Where>'
                                & $setQueryProperty $htmlQuery 'ViewFields' '<FieldRef Name="FileRef" />'
                                & $setQueryProperty $htmlQuery 'ViewFieldsOnly' $true
                                # The file type column is not indexed; an override lets farm administrators pass the list view threshold.
                                & $setQueryProperty $htmlQuery 'QueryThrottleMode' 'Override'
                                $htmlScanCount = 0
                                $hasUnscannedHtml = $false
                                $htmlPosition = $null
                                do {
                                    & $setQueryProperty $htmlQuery 'ListItemCollectionPosition' $htmlPosition
                                    $htmlBatch = $list.GetItems($htmlQuery)
                                    foreach ($htmlItem in (& $getBatchItems $htmlBatch)) {
                                        if ($htmlScanCount -ge $maxHtmlFileScan) {
                                            $hasUnscannedHtml = $true
                                            break
                                        }
                                        $htmlScanCount++
                                        $signals.HtmlFileCount++
                                        if ($htmlFileExamples.Count -lt 5) {
                                            $htmlIdentity = [string](& $getFileIdentity $htmlItem.File $htmlItem)
                                            if (-not [string]::IsNullOrWhiteSpace($htmlIdentity)) {
                                                $htmlFileExamples.Add($htmlIdentity)
                                            }
                                        }
                                    }
                                    $htmlPosition = & $getBatchPosition $htmlBatch
                                    if ($htmlScanCount -ge $maxHtmlFileScan -and $null -ne $htmlPosition) {
                                        $hasUnscannedHtml = $true
                                    }
                                } while ($null -ne $htmlPosition -and $htmlScanCount -lt $maxHtmlFileScan)

                                if ($hasUnscannedHtml) {
                                    $signals.CustomizationInventoryComplete = $false
                                    Write-Warning -Message "HTML file scan stopped on '$listTitle' in web '$($web.Url)' after $maxHtmlFileScan file(s). Increase LargeContentThresholds.MaxItemsForHtmlFileScanPerLibrary to count more files."
                                }
                            }
                            catch {
                                $signals.CustomizationInventoryComplete = $false
                                Write-Warning -Message "Could not scan HTML files on '$listTitle' in web '$($web.Url)': $($_.Exception.Message)"
                            }
                        }
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    $signals.ContentTypeInventoryComplete = $false
                    Write-Warning -Message "Lists could not be fully enumerated on web '$($web.Url)': $($_.Exception.Message)"
                }

                # SPWeb.Alerts covers every user. The count stays exact; rows stop at the per-site cap.
                try {
                    $webAlerts = $web.Alerts
                    if ($null -eq $webAlerts) {
                        throw 'The alert collection is unavailable.'
                    }
                    $webAlertCount = Get-SPSPropertyValue -InputObject $webAlerts -Name 'Count'
                    if ($null -eq $webAlertCount) {
                        throw 'The alert count could not be read.'
                    }
                    $signals.SharePointAlertCount += [int]$webAlertCount

                    if ([int]$webAlertCount -gt 0) {
                        foreach ($webAlert in $webAlerts) {
                            if ($sharePointAlerts.Count -ge $maxAlertRows) {
                                $alertRowsLeftOut = $true
                                break
                            }
                            try {
                                $sharePointAlerts.Add((ConvertTo-SPSSharePointAlertRecord -Alert $webAlert -SiteUrl $Site.Url -WebUrl $web.Url -IncludeUserLogin $includeAlertUserLogin -UserLoginCache $alertUserLogins))
                            }
                            catch {
                                $signals.CustomizationInventoryComplete = $false
                                $unreadableAlertCount++
                                # A systematic failure would otherwise warn once per alert, and a site can hold thousands.
                                if ($unreadableAlertCount -le $maxAlertWarnings) {
                                    Write-Warning -Message "Could not read an alert on web '$($web.Url)': $($_.Exception.Message)"
                                }
                            }
                        }
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    Write-Warning -Message "Could not read the alerts on web '$($web.Url)': $($_.Exception.Message)"
                }

                # SharePoint 2013 platform: Workflow Manager subscriptions. An unavailable
                # optional API stays best-effort; a connected read failure is incomplete data.
                try {
                    $workflowSubscriptionCount = Get-SPSWorkflowSubscriptionCount -Web $web
                    if ($null -ne $workflowSubscriptionCount) {
                        $signals.Workflow2013Count += [int]$workflowSubscriptionCount
                    }

                    $workflowRunningCount = Get-SPSWorkflowRunningInstanceCount -Web $web
                    if ($null -ne $workflowRunningCount) {
                        $signals.Workflow2013RunningInstanceCount += [int]$workflowRunningCount
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    Write-Warning -Message "Workflow Manager subscriptions or running instances could not be read on web '$($web.Url)': $($_.Exception.Message)"
                }

                if ($web.HasUniqueRoleAssignments) {
                    $signals.UniquePermissionsCount += @($web.RoleAssignments).Count
                }

                $master = [string]$web.CustomMasterUrl
                if ($master -and $master -notmatch 'seattle\.master|oslo\.master|v4\.master') {
                    $signals.CustomMasterPage = $true
                }

                if (($customFeatureSet.Count -gt 0 -or $fullTrustFeatureSet.Count -gt 0) -and
                    -not ($signals.UsesCustomFarmFeature -and $signals.UsesFullTrustCode)) {
                    foreach ($feature in $web.Features) {
                        $featureId = $feature.DefinitionId.ToString()
                        if ($customFeatureSet.Contains($featureId)) {
                            $signals.UsesCustomFarmFeature = $true
                        }
                        if ($fullTrustFeatureSet.Contains($featureId)) {
                            $signals.UsesFullTrustCode = $true
                        }
                        if ($signals.UsesCustomFarmFeature -and $signals.UsesFullTrustCode) {
                            break
                        }
                    }
                }
            }
            catch {
                $signals.CustomizationInventoryComplete = $false
                $signals.ContentTypeInventoryComplete = $false
                Write-Warning -Message "Signal collection issue on web '$($web.Url)': $($_.Exception.Message)"
            }
            finally {
                try {
                    $web.Dispose()
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    Write-Warning -Message "Could not dispose web '$($web.Url)': $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        $signals.CustomizationInventoryComplete = $false
        $signals.ContentTypeInventoryComplete = $false
        Write-Warning -Message "Webs could not be fully enumerated for '$($Site.Url)': $($_.Exception.Message)"
    }

    if ($alertRowsLeftOut) {
        $signals.CustomizationInventoryComplete = $false
        Write-Warning -Message "Alert rows stopped after $maxAlertRows on site '$($Site.Url)'; SharePointAlertCount stays exact. Increase LargeContentThresholds.MaxAlertRowsPerSite to export more."
    }
    if ($unreadableAlertCount -gt $maxAlertWarnings) {
        Write-Warning -Message "$($unreadableAlertCount - $maxAlertWarnings) more alert(s) could not be read on site '$($Site.Url)'; only the first $maxAlertWarnings are reported."
    }

    $signals.ContentTypeCount = $contentTypeIds.Count
    $signals.ContentTypes = $contentTypes.ToArray()
    $signals.LargeListExamples = $largeListExamples -join '; '
    $signals.LargeListViewExamples = $largeListViewExamples -join '; '
    $signals.CheckedOutFileExamples = $checkedOutFileExamples -join '; '
    $signals.FileVersionExamples = $fileVersionExamples -join '; '
    $signals.AppInstanceExamples = $appInstanceExamples -join '; '
    $signals.CustomizedPageExamples = $customizedPageExamples -join '; '
    $signals.CustomPermissionLevelCount = $customPermissionLevels.Count
    $signals.CustomPermissionLevelExamples = $customPermissionLevelExamples -join '; '
    $signals.EmailEnabledListExamples = $emailEnabledListExamples -join '; '
    $signals.HtmlFileExamples = $htmlFileExamples -join '; '
    $signals.ManagedMetadataListCount = $managedMetadataLists.Count
    $signals.ManagedMetadataTermSetCount = $managedMetadataTermSets.Count
    $signals.ManagedMetadataExamples = $managedMetadataExamples -join '; '
    $signals.ManagedMetadataLists = $managedMetadataLists.ToArray()
    $signals.ExternalListCount = $externalListCount
    $signals.ExternalListExamples = $externalListExamples -join '; '
    $signals.ExternalLists = $externalLists.ToArray()
    $signals.SharePointAlerts = $sharePointAlerts.ToArray()
    $signals.PublishingPageLayoutCount = $publishingLayouts.Count
    $signals.PublishingPageLayoutExamples = @(
        $publishingLayouts.Values |
            Sort-Object -Property @{ Expression = { $_.PageCount }; Descending = $true }, @{ Expression = { $_.Name } } |
            Select-Object -First 5 |
            ForEach-Object { '{0} ({1})' -f $_.Name, $_.PageCount }
    ) -join '; '
    return $signals
}
