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
        DeployedServerCount, FeatureCount, FeatureScopes and FeatureIds. SPSolution has
        no property that lists its features, so they are the feature definitions that the
        farm has registered for the solution (Get-SPFeature, matched on its SolutionId),
        counted once by id. SharePoint registers them when the solution is deployed: a
        solution that is only added has none here, and the package says which features it
        would register (see Get-SPSSolutionPackageInfo).

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

    # The features of a solution are the feature definitions of the farm that carry its id. They are
    # read once for all the solutions, with no limit (the default one is 200), and counted by id, as a
    # definition appears once for each compatibility level that the farm has.
    $featureOfSolution = @{}
    try {
        foreach ($definition in @(Get-SPFeature -Limit All -ErrorAction Stop)) {
            try {
                $ownerId = $definition.SolutionId.ToString()
                $definitionId = $definition.Id.ToString()
                $definitionScope = [string]$definition.Scope
            }
            catch {
                Write-Verbose -Message "Could not read a feature definition of the farm: $($_.Exception.Message)"
                continue
            }
            if (-not $featureOfSolution.ContainsKey($ownerId)) {
                $featureOfSolution[$ownerId] = @{}
            }
            $featureOfSolution[$ownerId][$definitionId] = $definitionScope
        }
    }
    catch {
        Write-Warning -Message "Could not read the feature definitions of the farm, so FeatureCount, FeatureScopes and FeatureIds stay empty for every solution and no site collection can be flagged UsesCustomFarmFeature or UsesFullTrustCode: $($_.Exception.Message)"
    }

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

        $solutionId = $solution.Id.ToString()
        $featureIds = @()
        $featureScopes = @()
        if ($featureOfSolution.ContainsKey($solutionId)) {
            $feature = $featureOfSolution[$solutionId]
            $featureIds = @($feature.Keys | Sort-Object)
            $featureScopes = @($feature.Values | Where-Object { $_ } | Sort-Object -Unique)
        }
        $featureCount = $featureIds.Count

        [PSCustomObject]@{
            SolutionName                   = $name
            SolutionId                     = $solutionId
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
