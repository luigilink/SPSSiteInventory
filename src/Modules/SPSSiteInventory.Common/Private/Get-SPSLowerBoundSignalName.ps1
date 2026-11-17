function Get-SPSLowerBoundSignalName {
    <#
        .SYNOPSIS
        Lists the signals of an inventory record whose count is a lower bound because a scan reached its cap.

        .DESCRIPTION
        The LowerBoundSignals column of the record names those signals, as the names of their columns separated by
        semicolons (Get-SPSSiteCustomization writes it). This function reads that text the same way for every part
        of the report: it trims each name, leaves out an empty one and a name that is repeated, and keeps the order.
        A record that has no such column, such as one written by an earlier version, or an empty one, gives nothing.

        Private because it is an implementation detail of the HTML report. The result can be empty: wrap the call
        in @() to get an array.

        .PARAMETER Record
        The inventory record of a site collection.

        .EXAMPLE
        Get-SPSLowerBoundSignalName -Record $record
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $Record
    )

    if ($null -eq $Record -or $null -eq $Record.PSObject.Properties['LowerBoundSignals']) {
        return
    }

    $seen = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
    foreach ($part in ([System.String]$Record.LowerBoundSignals).Split(';')) {
        $name = $part.Trim()
        if ($name.Length -gt 0 -and $seen.Add($name)) {
            $name
        }
    }
}
