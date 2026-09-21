function Get-SPSFarmSolutionMap {
    <#
        .SYNOPSIS
        Builds the map of farm solutions (WSP) and the feature IDs they deploy.

        .DESCRIPTION
        Enumerates the farm solutions with Get-SPSolution and, for each one, records the
        features it registers. The resulting map lets Get-SPSSiteCustomization flag any
        site that activates a feature coming from a custom full-trust solution (for
        example a well-known custom prefix such as an in-house product family), which is
        a strong "not portable to SharePoint Online" signal.

        Requires the SharePoint commands to be loaded (see Import-SPSSharePointCommand)
        and to run as the farm account on a farm server.

        Returns an array of PSCustomObject with SolutionName, SolutionId, Deployed,
        IsCustom and FeatureIds.

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

        $featureIds = @()
        try {
            $featureIds = @($solution.DeployedFeatures | ForEach-Object { $_.Id.ToString() })
        }
        catch {
            Write-Verbose -Message "Could not read features for solution '$name': $($_.Exception.Message)"
        }

        [PSCustomObject]@{
            SolutionName = $name
            SolutionId   = $solution.Id.ToString()
            Deployed     = [bool]$solution.Deployed
            IsCustom     = $isCustom
            FeatureIds   = $featureIds
        }
    }

    return @($map)
}
