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
        - text that is a number -> that number, read with the invariant culture
        - anything else       -> 1 when non-empty, 0 otherwise

        A number is never converted to text and parsed back, and text is read with the
        invariant culture, so the result does not depend on the culture of the server. Parsing
        with the culture of the thread read 25.5 as 1 on a French server and 12.25 as 1225 on a
        German one, which made the size of a site collection count for nothing in the scoring.

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

    if ($Value -is [System.Double] -or $Value -is [System.Single] -or $Value -is [System.Decimal] -or
        $Value -is [System.Int16] -or $Value -is [System.Int32] -or $Value -is [System.Int64] -or
        $Value -is [System.UInt16] -or $Value -is [System.UInt32] -or $Value -is [System.UInt64] -or
        $Value -is [System.Byte] -or $Value -is [System.SByte]) {
        return [double]$Value
    }

    $parsed = 0.0
    $styles = [System.Globalization.NumberStyles]::Float -bor [System.Globalization.NumberStyles]::AllowThousands
    if ([double]::TryParse([string]$Value, $styles, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }

    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return 0 }

    return 1
}
