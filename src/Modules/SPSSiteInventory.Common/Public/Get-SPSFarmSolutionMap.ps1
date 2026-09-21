function Get-SPSFarmSolutionMap {
    <#
        .SYNOPSIS
        Builds the map of farm solutions (WSP), what they deploy and how risky they are.

        .DESCRIPTION
        Enumerates the farm solutions with Get-SPSolution and, for each one, records the
        properties that characterize its migration risk without cracking the package:
        whether it deploys assemblies to the GAC (full-trust code), a CAS policy or a web
        application resource, its deployment state and reach (web applications, servers),
        and the features it registers (count, scopes, ids).

        This is the differentiator versus SMAT/SPMT: instead of only flagging that a site
        is customized, the map explains *what* the custom code is. A custom solution that
        deploys a global assembly (ContainsGlobalAssembly) is full-trust code and a hard
        blocker for SharePoint Online; a purely declarative farm solution is a lighter
        lift.

        The map lets Get-SPSSiteCustomization flag any site that activates a feature coming
        from a custom farm solution (UsesCustomFarmFeature) and, more specifically, from a
        custom full-trust solution (UsesFullTrustCode).

        Requires the SharePoint commands to be loaded (see Import-SPSSharePointCommand)
        and to run as the farm account on a farm server.

        Returns an array of PSCustomObject with SolutionName, SolutionId, Deployed,
        DeploymentState, IsCustom, ContainsGlobalAssembly, ContainsCasPolicy,
        ContainsWebApplicationResource, IsFullTrustCode, DeployedWebApplicationCount,
        DeployedServerCount, FeatureCount, FeatureScopes and FeatureIds. FeatureCount
        reflects the number of features the solution ships even when it is added but not
        deployed (the ids and scopes may still be empty until deployment).

        .PARAMETER CustomSolutionPrefix
        Optional list of case-insensitive name prefixes that mark a solution as custom
        (in-house). Solutions whose name starts with one of these prefixes are flagged
        IsCustom = $true. Keep this in the per-environment settings, never hard-coded.

        .EXAMPLE
        Get-SPSFarmSolutionMap -CustomSolutionPrefix @('contoso', 'inhouse')
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter()]
        [System.String[]]
        $CustomSolutionPrefix = @()
    )

    $solutions = Get-SPSolution -ErrorAction Stop

    $map = foreach ($solution in $solutions) {
        $name = [string]$solution.Name

        $isCustom = $false
        foreach ($prefix in $CustomSolutionPrefix) {
            if (-not [string]::IsNullOrWhiteSpace($prefix) -and
                $name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isCustom = $true
                break
            }
        }

        # Risk-characterizing properties exposed directly by SPSolution (no package
        # cracking). Read best-effort so one unreadable property does not drop the
        # solution from the map.
        $containsGlobalAssembly = $false
        $containsCasPolicy = $false
        $containsWebAppResource = $false
        $deploymentState = ''
        $deployedWebAppCount = 0
        $deployedServerCount = 0
        try { $containsGlobalAssembly = [bool]$solution.ContainsGlobalAssembly } catch { Write-Verbose -Message "Could not read ContainsGlobalAssembly for '$name': $($_.Exception.Message)" }
        try { $containsCasPolicy = [bool]$solution.ContainsCasPolicy } catch { Write-Verbose -Message "Could not read ContainsCasPolicy for '$name': $($_.Exception.Message)" }
        try { $containsWebAppResource = [bool]$solution.ContainsWebApplicationResource } catch { Write-Verbose -Message "Could not read ContainsWebApplicationResource for '$name': $($_.Exception.Message)" }
        try { $deploymentState = [string]$solution.DeploymentState } catch { Write-Verbose -Message "Could not read DeploymentState for '$name': $($_.Exception.Message)" }
        try { $deployedWebAppCount = @($solution.DeployedWebApplications).Count } catch { Write-Verbose -Message "Could not read DeployedWebApplications for '$name': $($_.Exception.Message)" }
        try { $deployedServerCount = @($solution.DeployedServers).Count } catch { Write-Verbose -Message "Could not read DeployedServers for '$name': $($_.Exception.Message)" }

        $featureIds = @()
        $featureScopes = @()
        $featureCount = 0
        try {
            $deployedFeatures = @($solution.DeployedFeatures)
            # Capture the count first: SPSolution.DeployedFeatures enumerates even when the
            # solution is not deployed, but reading each feature's Id/Scope can throw until
            # deployment. Keeping the count separate means a non-deployed solution still
            # reports how many features it ships.
            $featureCount = $deployedFeatures.Count

            $ids = [System.Collections.Generic.List[string]]::new()
            $scopes = [System.Collections.Generic.List[string]]::new()
            foreach ($feature in $deployedFeatures) {
                # Read each feature best-effort so one unreadable feature does not drop the
                # detail for the others.
                try { if ($feature.Id) { $ids.Add($feature.Id.ToString()) } }
                catch { Write-Verbose -Message "Could not read a feature Id for solution '$name': $($_.Exception.Message)" }
                try { $scope = [string]$feature.Scope; if ($scope) { $scopes.Add($scope) } }
                catch { Write-Verbose -Message "Could not read a feature Scope for solution '$name': $($_.Exception.Message)" }
            }
            $featureIds = @($ids)
            $featureScopes = @($scopes | Sort-Object -Unique)
        }
        catch {
            Write-Verbose -Message "Could not read features for solution '$name': $($_.Exception.Message)"
        }

        # Prefer the enumerated count; fall back to the number of ids actually read.
        if ($featureCount -lt $featureIds.Count) { $featureCount = $featureIds.Count }

        [PSCustomObject]@{
            SolutionName                   = $name
            SolutionId                     = $solution.Id.ToString()
            Deployed                       = [bool]$solution.Deployed
            DeploymentState                = $deploymentState
            IsCustom                       = $isCustom
            ContainsGlobalAssembly         = $containsGlobalAssembly
            ContainsCasPolicy              = $containsCasPolicy
            ContainsWebApplicationResource = $containsWebAppResource
            IsFullTrustCode                = ($isCustom -and $containsGlobalAssembly)
            DeployedWebApplicationCount    = $deployedWebAppCount
            DeployedServerCount            = $deployedServerCount
            FeatureCount                   = $featureCount
            FeatureScopes                  = $featureScopes
            FeatureIds                     = $featureIds
        }
    }

    return @($map)
}
