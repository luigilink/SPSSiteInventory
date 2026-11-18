function Format-SPSDuration {
    <#
        .SYNOPSIS
        Writes a number of seconds as a short duration for the log.

        .DESCRIPTION
        Under 10 seconds the text keeps one decimal when there is one ("0.4 s", "3.4 s"). From 10 seconds on it gives
        whole seconds ("38 s"), then minutes and seconds ("2 min 05 s"), then hours, minutes and seconds
        ("1 h 03 min 12 s"). The seconds are rounded before the text is cut, so that 59.6 seconds read "1 min 00 s"
        and not "60 s". The numbers are written with the invariant culture: the log does not change with the language
        of the server.

        Private because it is an implementation detail of the log of the scan.

        .PARAMETER Seconds
        The number of seconds, 0 or more.

        .EXAMPLE
        Format-SPSDuration -Seconds 125
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 3153600000)]
        [System.Double]
        $Seconds
    )

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $tenths = [System.Math]::Round($Seconds, 1, [System.MidpointRounding]::AwayFromZero)
    if ($tenths -lt 10) {
        return '{0} s' -f $tenths.ToString('0.#', $invariant)
    }

    $whole = [System.Int64][System.Math]::Round($Seconds, 0, [System.MidpointRounding]::AwayFromZero)
    $minutePart = [System.Int64][System.Math]::Floor(($whole % 3600) / 60)
    $secondPart = $whole % 60
    if ($whole -lt 60) {
        return '{0} s' -f $whole
    }
    if ($whole -lt 3600) {
        return '{0} min {1} s' -f $minutePart, $secondPart.ToString('00', $invariant)
    }

    return '{0} h {1} min {2} s' -f [System.Int64][System.Math]::Floor($whole / 3600), $minutePart.ToString('00', $invariant), $secondPart.ToString('00', $invariant)
}
