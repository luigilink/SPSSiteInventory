function Get-SPSYesNoPill {
    <#
        .SYNOPSIS
        Returns a Yes/No HTML pill span for a boolean-ish value.

        .DESCRIPTION
        Get-SPSYesNoPill is a pure helper (no SharePoint calls) used by the HTML report to
        render a coloured Yes/No badge from a truthy value. A true value renders a "yes"
        pill (or the class given by -TruePill), a false value renders a neutral "no" pill.

        Private because it is an implementation detail of ConvertTo-SPSInventoryHtml.

        .PARAMETER Value
        The value to interpret as a boolean. Uses PowerShell truthiness.

        .PARAMETER TruePill
        CSS pill class to use when the value is true. Defaults to 'yes'. Use 'warn' to draw
        attention with the moderate colour instead of the blocking colour.

        .EXAMPLE
        Get-SPSYesNoPill -Value $solution.IsFullTrustCode
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Position = 0)]
        [AllowNull()]
        [System.Object]
        $Value,

        [Parameter()]
        [System.String]
        $TruePill = 'yes'
    )

    if ($Value) {
        return ('<span class="pill {0}">Yes</span>' -f $TruePill)
    }

    return '<span class="pill no">No</span>'
}
