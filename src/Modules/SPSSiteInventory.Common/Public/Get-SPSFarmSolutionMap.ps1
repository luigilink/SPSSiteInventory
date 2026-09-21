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

        IsCustom is auto-detected by default (custom unless the solution name matches a
        known Microsoft / out-of-the-box marker), so no per-client prefix list is needed.
        CustomSolutionPrefix remains as an optional override; AutoDetectCustom can be
        turned off to fall back to the legacy prefix-only behaviour.

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
        Optional list of case-insensitive name prefixes that force a solution to be flagged
        IsCustom = $true. This is now an *override* on top of auto-detection: you rarely
        need it, because a solution is treated as custom by default. Use it only to force
        a solution custom when auto-detection wrongly classifies it as Microsoft.

        .PARAMETER AutoDetectCustom
        When $true (default), a solution is treated as custom unless its name matches a
        known Microsoft / out-of-the-box marker (see Test-SPSMicrosoftSolution). This is
        what makes CustomSolutionPrefix optional: on a farm the solution store only holds
        solutions that were explicitly added, so "custom unless proven Microsoft" is the
        safe default and needs no per-client configuration. Set to $false to fall back to
        the legacy behaviour where only CustomSolutionPrefix decides IsCustom.

        .PARAMETER KnownMicrosoftPrefix
        Optional extra case-insensitive name prefixes to treat as Microsoft / out-of-the-box
        during auto-detection, merged with the built-in list. Use it to silence a known
        vendor package that should not count as custom.

        .EXAMPLE
        # Zero configuration: solutions are auto-classified as custom vs Microsoft.
        Get-SPSFarmSolutionMap

        .EXAMPLE
        # Force a solution custom even if auto-detection missed it.
        Get-SPSFarmSolutionMap -CustomSolutionPrefix @('contoso', 'inhouse')

        .EXAMPLE
        # Legacy behaviour: only the prefix list decides IsCustom.
        Get-SPSFarmSolutionMap -CustomSolutionPrefix @('contoso') -AutoDetectCustom:$false
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter()]
        [System.String[]]
        $CustomSolutionPrefix = @(),

        [Parameter()]
        [System.Boolean]
        $AutoDetectCustom = $true,

        [Parameter()]
        [System.String[]]
        $KnownMicrosoftPrefix = @()
    )

    $solutions = Get-SPSolution -ErrorAction Stop

    $map = foreach ($solution in $solutions) {
        $name = [string]$solution.Name

        # 1. Auto-detection: custom by default, unless the name looks Microsoft / OOTB.
        $isCustom = $false
        if ($AutoDetectCustom) {
            $isCustom = -not (Test-SPSMicrosoftSolution -Name $name -ExtraMicrosoftPrefix $KnownMicrosoftPrefix)
        }

        # 2. Explicit prefix override: force custom when the name matches a supplied prefix
        #    (works whether or not auto-detection is on).
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
