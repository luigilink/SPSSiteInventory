function ConvertTo-SPSSignalNumber {
    <#
        .SYNOPSIS
        Normalizes a signal value into a number usable by the scoring engine.

        .DESCRIPTION
        Signals collected from a site can be booleans (a feature is present or not),
        integers (a count of workflows), or $null (the signal was not collected). This
        private helper converts any of those into a double so Measure-SPSSiteComplexity
        can treat them uniformly:

        - $null or empty     -> 0
        - $true / $false     -> 1 / 0
        - a numeric value    -> the number itself
        - anything else       -> 1 when non-empty, 0 otherwise

        .PARAMETER Value
        The raw signal value to normalize.
    #>
    [CmdletBinding()]
    [OutputType([System.Double])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Object]
        $Value
    )

    if ($null -eq $Value) { return 0 }

    if ($Value -is [bool]) { return [double]([int]$Value) }

    $parsed = 0.0
    if ([double]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }

    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return 0 }

    return 1
}
