function Get-SPSSiteCustomization {
    <#
        .SYNOPSIS
        Collects the customization signals of a single site collection.

        .DESCRIPTION
        Inspects one site collection and returns the signals that drive the migration
        complexity score: 2010 vs 2013 workflows, InfoPath forms, sandbox solutions,
        custom master page, unique permissions, event receivers, and whether the site
        activates a feature that comes from a custom farm solution (correlated through the
        farm-solution map).

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

        The returned hashtable is designed to be passed straight to
        Measure-SPSSiteComplexity. Signal collection is best-effort: a failure to read one
        signal logs a verbose message and leaves that signal at its default rather than
        aborting the whole site.

        Requires the SharePoint commands (see Import-SPSSharePointCommand) and to run as
        the farm account on a farm server.

        .PARAMETER Site
        The SPSite object to inspect (from Get-SPSite or a web application's Sites
        collection).

        .PARAMETER CustomFeatureId
        Optional list of feature IDs known to come from custom farm solutions (typically
        built from Get-SPSFarmSolutionMap). A site activating one of these is flagged with
        the UsesCustomFarmFeature signal, which the scoring config can treat as blocking.

        .EXAMPLE
        $map = Get-SPSFarmSolutionMap -CustomSolutionPrefix @('contoso')
        $customIds = $map | Where-Object IsCustom | ForEach-Object FeatureIds
        Get-SPSSite 'https://intranet/sites/team' | ForEach-Object {
            Get-SPSSiteCustomization -Site $_ -CustomFeatureId $customIds
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
        $CustomFeatureId = @()
    )

    $signals = @{
        Workflow2010Count        = 0
        Workflow2013Count        = 0
        InfoPathFormCount        = 0
        SandboxSolutions         = 0
        CustomMasterPage         = $false
        UniquePermissionsCount   = 0
        EventReceivers           = 0
        UsesCustomFarmFeature    = $false
    }

    try {
        $signals.SandboxSolutions = @($Site.Solutions).Count
    }
    catch {
        Write-Verbose -Message "Could not read sandbox solutions for '$($Site.Url)': $($_.Exception.Message)"
    }

    $customFeatureSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$CustomFeatureId, [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($web in $Site.AllWebs) {
        try {
            # SharePoint 2010 platform: classic workflow associations at web and list scope.
            $signals.Workflow2010Count += @($web.WorkflowAssociations).Count

            foreach ($list in $web.Lists) {
                $signals.Workflow2010Count += @($list.WorkflowAssociations).Count
                $signals.EventReceivers += @($list.EventReceivers).Count

                # InfoPath detection: an InfoPath form library (XMLForm base template) or
                # a list whose forms were customized with InfoPath (the _ipfs_* marker
                # properties are stamped on the list root folder). InfoPath Forms Services
                # is retired and unavailable in SharePoint Online.
                $listTitle = $list.Title
                try {
                    if ($list.BaseTemplate -eq [Microsoft.SharePoint.SPListTemplateType]::XMLForm) {
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
                    Write-Verbose -Message "Could not read InfoPath state on list '$listTitle': $($_.Exception.Message)"
                }
            }

            # SharePoint 2013 platform: Workflow Manager subscriptions. Best-effort - the
            # type may be unavailable or Workflow Manager may not be connected, in which
            # case the count stays at 0 instead of failing the whole site.
            try {
                $workflowManager = [Microsoft.SharePoint.WorkflowServices.WorkflowServicesManager]::new($web)
                if ($workflowManager.IsConnected) {
                    $subscriptions = $workflowManager.GetWorkflowSubscriptionService().EnumerateSubscriptions()
                    $signals.Workflow2013Count += @($subscriptions).Count
                }
            }
            catch {
                Write-Verbose -Message "Could not read 2013 workflow subscriptions on web '$($web.Url)': $($_.Exception.Message)"
            }

            if ($web.HasUniqueRoleAssignments) {
                $signals.UniquePermissionsCount += @($web.RoleAssignments).Count
            }

            $master = [string]$web.CustomMasterUrl
            if ($master -and $master -notmatch 'seattle\.master|oslo\.master|v4\.master') {
                $signals.CustomMasterPage = $true
            }

            if ($customFeatureSet.Count -gt 0) {
                foreach ($feature in $web.Features) {
                    if ($customFeatureSet.Contains($feature.DefinitionId.ToString())) {
                        $signals.UsesCustomFarmFeature = $true
                        break
                    }
                }
            }
        }
        catch {
            Write-Verbose -Message "Signal collection issue on web '$($web.Url)': $($_.Exception.Message)"
        }
        finally {
            $web.Dispose()
        }
    }

    return $signals
}
