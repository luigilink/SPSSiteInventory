function Test-SPSFeatureActivated {
    <#
        .SYNOPSIS
        Tells whether a feature is activated in an SPFeatureCollection.

        .DESCRIPTION
        Walks a site-collection or web feature collection and compares each activated
        feature's DefinitionId with the requested feature ID (case-insensitive). A readable
        empty collection means the feature is off. A null collection is rejected because
        PowerShell turns an exception thrown by a property getter into $null, so treating
        it as "no features" would report an unreadable collection as a negative signal.
        Enumeration failures are not caught either, so the caller can report the read as
        partial.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Feature
        The SPSite.Features or SPWeb.Features collection.

        .PARAMETER FeatureId
        The feature definition GUID to look for, as a string.

        .EXAMPLE
        Test-SPSFeatureActivated -Feature $web.Features -FeatureId '94c94ca6-b32f-4da9-a9e3-1f3d343d7ecb'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Object]
        $Feature,

        [Parameter(Mandatory = $true)]
        [System.String]
        $FeatureId
    )

    if ($null -eq $Feature) {
        throw 'The feature collection is unavailable.'
    }

    foreach ($candidate in $Feature) {
        if ($null -ne $candidate -and
            $candidate.DefinitionId.ToString().Equals($FeatureId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}
