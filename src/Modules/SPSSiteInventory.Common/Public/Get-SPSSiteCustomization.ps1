function Get-SPSSiteCustomization {
    <#
        .SYNOPSIS
        Collects the customization signals of a single site collection.

        .DESCRIPTION
        Inspects one site collection and returns the signals that drive the migration
        complexity score: workflow associations, sandbox solutions, custom master page,
        unique permissions, event receivers, and whether the site activates a feature
        that comes from a custom farm solution (correlated through the farm-solution map).

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
        WorkflowAssociationCount = 0
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
            $signals.WorkflowAssociationCount += @($web.WorkflowAssociations).Count

            foreach ($list in $web.Lists) {
                $signals.WorkflowAssociationCount += @($list.WorkflowAssociations).Count
                $signals.EventReceivers += @($list.EventReceivers).Count
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
