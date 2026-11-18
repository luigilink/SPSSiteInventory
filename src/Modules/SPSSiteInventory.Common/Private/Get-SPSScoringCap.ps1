function Get-SPSScoringCap {
    <#
        .SYNOPSIS
        Reads and validates the optional Caps of the Scoring section of the inventory settings.

        .DESCRIPTION
        What a signal adds to the score of a site collection is its weight multiplied by its value.
        With a large value, a signal can add more than a threshold of the categories on its own, and
        the category of that site collection then follows from that signal alone (the Score drivers
        section of the HTML report gives the share of each signal). Scoring.Caps limits it: it gives,
        for a signal, the most that the signal can add to the score of one site collection. A
        contribution above the cap is cut to the cap.

        There is no cap by default, also when the key is missing, and the scores are then those of the
        weights alone. A cap is a number greater than 0, and the signal must have an entry in
        Scoring.Weights, because a cap on any other name would do nothing and is most likely a typo.
        A value that is not a number, such as the string '5', is rejected instead of being coerced.

        Returns a hashtable of the capped signals (the names are not case-sensitive) and their caps, which
        is empty when there are none. A cap that is not valid throws, with a message that names it.

        Private because it is an implementation detail of the scoring and of the settings loader, which
        share it so that the validation lives in one place.

        .PARAMETER Scoring
        The Scoring section of the settings.

        .EXAMPLE
        (Get-SPSScoringCap -Scoring @{ Weights = @{ EventReceivers = 1.5 }; Caps = @{ EventReceivers = 5 } })['EventReceivers']
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Collections.IDictionary]
        $Scoring = @{}
    )

    $cap = @{}
    if ($null -eq $Scoring -or -not $Scoring.Contains('Caps') -or $null -eq $Scoring['Caps']) {
        return $cap
    }

    $caps = $Scoring['Caps']
    if ($caps -isnot [System.Collections.IDictionary]) {
        throw 'Scoring.Caps must be a hashtable of signal names and caps, for example @{ EventReceivers = 5 }.'
    }

    $weights = $Scoring['Weights']
    foreach ($entry in @($caps.GetEnumerator() | Sort-Object -Property { [System.String]$_.Key })) {
        $name = [System.String]$entry.Key
        $value = $entry.Value
        $isNumber = $value -is [System.Int32] -or $value -is [System.Int64] -or $value -is [System.Double] -or $value -is [System.Decimal] -or $value -is [System.Single]
        if (-not $isNumber -or [System.Double]::IsNaN([System.Double]$value) -or [System.Double]::IsInfinity([System.Double]$value) -or [System.Double]$value -le 0) {
            throw ('Scoring.Caps.{0} must be a number greater than 0: the most that the signal can add to the score of a site collection.' -f $name)
        }
        if ($weights -isnot [System.Collections.IDictionary] -or -not $weights.Contains($name)) {
            throw ('Scoring.Caps.{0} is not a signal of Scoring.Weights: check the name. A cap only applies to a signal that has a weight.' -f $name)
        }
        $cap[$name] = [System.Double]$value
    }

    return $cap
}
