function Get-SPSSiteCustomization {
    <#
        .SYNOPSIS
        Collects the customization signals of a single site collection.

        .DESCRIPTION
        Inspects one site collection and returns the signals that drive the migration
        complexity score: 2010 vs 2013 workflows, InfoPath forms, IRM-enabled lists,
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

        IrmEnabledListCount counts lists and libraries where IRM is enabled. IsLockedSite
        and SiteLockState surface site lock status (ReadOnly / NoAdditions / NoAccess),
        which can block or delay migration.

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
        FileVersionCount, and MaxItemsForVersionScanPerLibrary.

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
        $LargeContentThresholds = @{}
    )

    $signals = @{
        Workflow2010Count        = 0
        Workflow2010RunningInstanceCount = 0
        Workflow2013Count        = 0
        Workflow2013RunningInstanceCount = 0
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

    $largeListItemThreshold = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'LargeListItemCount' -DefaultValue 5000 -MinimumValue 1)
    $largeListViewRowLimitThreshold = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'LargeListViewRowLimit' -DefaultValue 5000 -MinimumValue 1)
    $checkedOutFileThreshold = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'CheckedOutFileCount' -DefaultValue 1 -MinimumValue 1)
    $fileVersionThreshold = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'FileVersionCount' -DefaultValue 50 -MinimumValue 1)
    $maxItemsForVersionScan = [int](Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'MaxItemsForVersionScanPerLibrary' -DefaultValue 2000 -MinimumValue 1)
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
                    }
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    $signals.ContentTypeInventoryComplete = $false
                    Write-Warning -Message "Lists could not be fully enumerated on web '$($web.Url)': $($_.Exception.Message)"
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

    $signals.ContentTypeCount = $contentTypeIds.Count
    $signals.ContentTypes = $contentTypes.ToArray()
    $signals.LargeListExamples = $largeListExamples -join '; '
    $signals.LargeListViewExamples = $largeListViewExamples -join '; '
    $signals.CheckedOutFileExamples = $checkedOutFileExamples -join '; '
    $signals.FileVersionExamples = $fileVersionExamples -join '; '
    return $signals
}
