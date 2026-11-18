function Complete-SPSScanPhase {
    <#
        .SYNOPSIS
        Ends a phase of the scan: logs how long it took, records it, and starts the clock of the next one.

        .DESCRIPTION
        The orchestrator runs the scan in phases (the farm-solution map, the enumeration of the site collections, the
        collection of the signals, and so on). When one ends, this function stops its stopwatch, adds a row with the name
        of the phase and its seconds to the list that the manifest gets, writes one line in the log, and restarts the
        stopwatch, so that the next phase starts from 0 and the phases follow one another.

        Private because it is an implementation detail of the orchestrator.

        .PARAMETER Name
        The name of the phase, as it reads in the log and in the manifest.

        .PARAMETER Stopwatch
        The stopwatch of the phase. It is restarted.

        .PARAMETER Timing
        The list that receives a row with Name and Seconds for each phase.

        .PARAMETER Detail
        What the phase handled, for the log, such as "34 site collection(s)". Optional.

        .EXAMPLE
        Complete-SPSScanPhase -Name 'Enumerating the site collections' -Stopwatch $watch -Timing $rows -Detail '34 site collection(s)'
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]
        $Stopwatch,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]]
        $Timing,

        [Parameter()]
        [System.String]
        $Detail = ''
    )

    $Stopwatch.Stop()
    $seconds = [System.Math]::Round($Stopwatch.Elapsed.TotalSeconds, 1)
    $Timing.Add([PSCustomObject]@{ Name = $Name; Seconds = $seconds })

    $duration = Format-SPSDuration -Seconds $seconds
    $message = if ([System.String]::IsNullOrWhiteSpace($Detail)) { '{0}: done in {1}.' -f $Name, $duration } else { '{0}: done in {1} ({2}).' -f $Name, $duration, $Detail }
    Add-SPSInventoryEvent -Message $message -Level Information | Out-Host

    $Stopwatch.Restart()
}
