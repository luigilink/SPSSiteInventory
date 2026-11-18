function Format-SPSScanTiming {
    <#
        .SYNOPSIS
        Writes the last line of the log of a scan: how long it took, in all and phase by phase.

        .DESCRIPTION
        The line reads "Scan finished in 19 min 04 s. By phase: Loading the settings and the SharePoint commands 12 s;
        Enumerating the site collections 41 s; ...", with the phases in the order they ran. Without a phase, only the
        total is given.

        Private because it is an implementation detail of the orchestrator.

        .PARAMETER Phase
        The rows of the phases, each with Name and Seconds (see Complete-SPSScanPhase).

        .PARAMETER Seconds
        The duration of the whole run, in seconds.

        .EXAMPLE
        Format-SPSScanTiming -Phase $rows -Seconds 1144
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Phase,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 3153600000)]
        [System.Double]
        $Seconds
    )

    $total = Format-SPSDuration -Seconds $Seconds
    $part = @($Phase | ForEach-Object { '{0} {1}' -f $_.Name, (Format-SPSDuration -Seconds ([System.Double]$_.Seconds)) })
    if ($part.Count -eq 0) {
        return 'Scan finished in {0}.' -f $total
    }

    return 'Scan finished in {0}. By phase: {1}.' -f $total, ($part -join '; ')
}
