function ConvertTo-SPSSizeText {
    <#
        .SYNOPSIS
        Formats a size in GB for the summary and the tables of the HTML report.

        .DESCRIPTION
        Rounds to two decimals and drops the trailing zeros. A size that is not zero but rounds to
        zero is shown as '< 0.01', so that a farm of small site collections does not read as empty.
        The text does not depend on the culture.

        Private because it is an implementation detail of the HTML report.

        .PARAMETER SizeGB
        The size in GB.

        .EXAMPLE
        ConvertTo-SPSSizeText -SizeGB 0.0042
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Double]
        $SizeGB
    )

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $rounded = [math]::Round($SizeGB, 2)
    if ($rounded -gt 0) {
        return $rounded.ToString('0.##', $invariant)
    }
    if ($SizeGB -gt 0) {
        return '< 0.01'
    }
    return '0'
}
