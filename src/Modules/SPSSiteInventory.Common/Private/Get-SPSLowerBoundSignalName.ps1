function Get-SPSLowerBoundSignalName {
    <#
        .SYNOPSIS
        Lists the signals of a site collection whose count is a lower bound because a scan reached its cap.

        .DESCRIPTION
        The LowerBoundSignals column of the inventory record, and the signal of the same name that
        Get-SPSSiteCustomization returns, name those signals as the names of their columns separated by semicolons.
        This function reads that text the same way for every part of the report: it trims each name, leaves out an
        empty one and a name that is repeated, and keeps the order. A record that has no such column, such as one
        written by an earlier version, gives $null here: a $null and an empty text both give nothing.

        Private because it is an implementation detail of the HTML report and of the modern blockers. The result can
        be empty: wrap the call in @() to get an array.

        .PARAMETER Value
        The text of the LowerBoundSignals column or signal, or $null.

        .EXAMPLE
        Get-SPSLowerBoundSignalName -Value $record.LowerBoundSignals
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Value
    )

    $seen = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
    foreach ($part in ([System.String]$Value).Split(';')) {
        $name = $part.Trim()
        if ($name.Length -gt 0 -and $seen.Add($name)) {
            $name
        }
    }
}
