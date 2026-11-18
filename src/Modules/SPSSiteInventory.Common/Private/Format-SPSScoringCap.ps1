function Format-SPSScoringCap {
    <#
        .SYNOPSIS
        Says the caps of the scoring in one line, for the log.

        .DESCRIPTION
        Takes the hashtable that Get-SPSScoringCap returns and gives the signals in alphabetical order, each with
        its cap ("EventReceivers at most 4, Workflow2010Count at most 7.5"). The numbers are written with the
        invariant culture, up to two decimals, so that the log does not change with the server. Returns an empty
        string when there is no cap.

        Private because it is an implementation detail of the orchestrator, which logs the caps in force when
        a scan starts.

        .PARAMETER Cap
        The caps, as Get-SPSScoringCap returns them.

        .EXAMPLE
        Format-SPSScoringCap -Cap @{ EventReceivers = 4 }
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary]
        $Cap
    )

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $text = @($Cap.GetEnumerator() | Sort-Object -Property { [System.String]$_.Key } | ForEach-Object {
            '{0} at most {1}' -f $_.Key, ([System.Double]$_.Value).ToString('0.##', $invariant)
        })

    return ($text -join ', ')
}
