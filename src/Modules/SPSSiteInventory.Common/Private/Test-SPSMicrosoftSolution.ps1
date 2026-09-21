function Test-SPSMicrosoftSolution {
    <#
        .SYNOPSIS
        Tells whether a farm solution (WSP) name looks like a Microsoft / out-of-the-box
        solution rather than custom code.

        .DESCRIPTION
        Test-SPSMicrosoftSolution is a pure helper (no SharePoint calls) used to auto-detect
        custom solutions without any per-environment configuration. On a farm the solution
        store (Get-SPSolution) only holds solutions explicitly added with Add-SPSolution,
        so the safe default is "custom unless proven Microsoft". This function encodes the
        stable, shipped list of Microsoft / OOTB solution name markers; everything else is
        treated as custom.

        Returns $true when the name matches a known Microsoft / OOTB marker (i.e. NOT
        custom), $false otherwise (treat as custom). An empty name is treated as
        non-Microsoft ($false) so it does not silently drop out of the custom set.

        Private because it is an implementation detail of Get-SPSFarmSolutionMap.

        .PARAMETER Name
        The farm solution (WSP) name, e.g. 'microsoft.sharepoint.translation.wsp' or
        'contoso.intranet.wsp'.

        .PARAMETER ExtraMicrosoftPrefix
        Optional additional case-insensitive name prefixes to treat as Microsoft / OOTB,
        merged with the built-in list. Lets an environment silence a known vendor package
        without editing the module.

        .EXAMPLE
        Test-SPSMicrosoftSolution -Name 'microsoft.sharepoint.translation.wsp'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Position = 0)]
        [AllowNull()]
        [System.Object]
        $Name,

        [Parameter()]
        [System.String[]]
        $ExtraMicrosoftPrefix = @()
    )

    $solutionName = [string]$Name
    if ([string]::IsNullOrWhiteSpace($solutionName)) { return $false }

    $solutionName = $solutionName.Trim()

    # Built-in, shipped markers for Microsoft / out-of-the-box farm solutions. Kept broad
    # but specific enough not to swallow custom code. Case-insensitive.
    $microsoftPrefix = @(
        'microsoft.'
        'microsoft-'
        'osrc'                   # Office Server resource solutions
        'search-'
        'spscontentdeployment'
        'sts.wsp'
    )

    $allPrefix = @($microsoftPrefix + @($ExtraMicrosoftPrefix | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))

    foreach ($prefix in $allPrefix) {
        if ($solutionName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}
