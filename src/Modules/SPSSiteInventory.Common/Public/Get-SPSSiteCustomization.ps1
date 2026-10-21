function Get-SPSSiteCustomization {
    <#
        .SYNOPSIS
        Collects the customization signals of a single site collection.

        .DESCRIPTION
        Inspects one site collection and returns the signals that drive the migration
        complexity score: 2010 vs 2013 workflows, InfoPath forms, IRM-enabled lists,
        site lock state, sandbox solutions, custom master page, unique permissions,
        custom event receivers, and whether the site activates a feature that comes from
        a custom farm solution (correlated through the farm-solution map).

        EventReceivers counts only custom event receivers (those registered from a
        non-Microsoft assembly). Out-of-the-box receivers on native lists are ignored so
        they do not inflate the score.

        Workflows are split by platform because their migration cost differs sharply:

        - Workflow2010Count counts classic SPWorkflowAssociation objects (the SharePoint
          2010 workflow platform, whose engine is retired in SharePoint Online, so those
          workflows always need a rebuild).
        - Workflow2013Count counts Workflow Manager subscriptions (the SharePoint 2013
          platform), read through WorkflowServicesManager. This is best-effort: when
          Workflow Manager is not connected the count stays at 0 rather than failing.

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
        $FullTrustFeatureId = @()
    )

    $signals = @{
        Workflow2010Count        = 0
        Workflow2013Count        = 0
        InfoPathFormCount        = 0
        IrmEnabledListCount      = 0
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

    try {
        $signals.SandboxSolutions = @($Site.Solutions).Count
    }
    catch {
        $signals.CustomizationInventoryComplete = $false
        Write-Warning -Message "Could not read sandbox solutions for site collection '$($Site.Url)': $($_.Exception.Message)"
    }

    try {
        $lockState = $null
        $lockStateProperty = $Site.PSObject.Properties['LockState']
        if ($null -ne $lockStateProperty -and $null -ne $lockStateProperty.Value) {
            $lockState = [string]$lockStateProperty.Value
        }

        if ([string]::IsNullOrWhiteSpace($lockState)) {
            $readOnlyProperty = $Site.PSObject.Properties['ReadOnly']
            if ($null -ne $readOnlyProperty -and $null -ne $readOnlyProperty.Value) {
                $lockState = if ([bool]$readOnlyProperty.Value) { 'ReadOnly' } else { 'Unlock' }
            }
        }

        if ([string]::IsNullOrWhiteSpace($lockState)) {
            $lockState = 'Unknown'
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
                # SharePoint can keep historical "previous version" associations; only active
                # associations should count toward migration complexity.
                $signals.Workflow2010Count += @(Get-SPSActiveWorkflowAssociations -WorkflowAssociations @($web.WorkflowAssociations)).Count

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

                        $signals.Workflow2010Count += @(Get-SPSActiveWorkflowAssociations -WorkflowAssociations @($list.WorkflowAssociations)).Count

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
                }
                catch {
                    $signals.CustomizationInventoryComplete = $false
                    Write-Warning -Message "Workflow Manager subscriptions could not be read on web '$($web.Url)': $($_.Exception.Message)"
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
    return $signals
}
