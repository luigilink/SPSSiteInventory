function Measure-SPSSiteComplexity {
    <#
        .SYNOPSIS
        Scores a site's migration complexity from its collected signals and a scoring
        configuration, returning a category from 1 (Simple) to 4 (Blocking).

        .DESCRIPTION
        Measure-SPSSiteComplexity is a pure function (no SharePoint calls) so it can be
        unit tested without a farm. It takes the customization signals collected for a
        single site and the Scoring section of the inventory settings, then:

        1. Computes a weighted numeric score from the Weights map. Each weight is
           multiplied by the matching signal value (booleans count as 1 when true).
        2. Maps the score to a category using the Thresholds map:
           - score below Moderate            -> category 1 (Simple)
           - score at or above Moderate       -> category 2 (Moderate)
           - score at or above Complex        -> category 3 (Complex)
        3. Applies hard override rules: if any signal listed in BlockingSignals is
           truthy, the category is forced to 4 (Blocking), whatever the score.

        Returns a PSCustomObject with Score, Category (1-4), CategoryName and Reasons
        (the human-readable drivers that pushed the site up).

        .PARAMETER Signals
        Hashtable of signals collected for the site (for example by
        Get-SPSSiteCustomization). Missing keys are treated as 0 / $false.

        .PARAMETER Scoring
        The Scoring hashtable from the inventory settings (Weights, Thresholds,
        BlockingSignals). See inventory-settings.example.psd1.

        .EXAMPLE
        $signals = @{ Workflow2013Count = 2; SandboxSolutions = 1 }
        Measure-SPSSiteComplexity -Signals $signals -Scoring $settings.Scoring
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Signals,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Scoring
    )

    $categoryNames = @{
        1 = 'Simple'
        2 = 'Moderate'
        3 = 'Complex'
        4 = 'Blocking'
    }

    $weights = if ($Scoring['Weights']) { $Scoring['Weights'] } else { @{} }
    $thresholds = if ($Scoring['Thresholds']) { $Scoring['Thresholds'] } else { @{} }
    $blockingSignals = if ($Scoring['BlockingSignals']) { @($Scoring['BlockingSignals']) } else { @() }

    $moderateThreshold = if ($null -ne $thresholds['Moderate']) { [double]$thresholds['Moderate'] } else { 1 }
    $complexThreshold = if ($null -ne $thresholds['Complex']) { [double]$thresholds['Complex'] } else { 6 }

    $reasons = [System.Collections.Generic.List[string]]::new()

    # 1. Weighted numeric score.
    $score = 0.0
    foreach ($signalName in $weights.Keys) {
        $weight = [double]$weights[$signalName]
        $value = ConvertTo-SPSSignalNumber -Value $Signals[$signalName]
        if ($value -ne 0 -and $weight -ne 0) {
            $contribution = $weight * $value
            $score += $contribution
            $reasons.Add(("{0}={1} (+{2})" -f $signalName, $value, [math]::Round($contribution, 2)))
        }
    }

    # 2. Map score to a base category.
    $category = 1
    if ($score -ge $moderateThreshold) { $category = 2 }
    if ($score -ge $complexThreshold) { $category = 3 }

    # 3. Hard blocking overrides.
    $isBlocked = $false
    foreach ($signalName in $blockingSignals) {
        if ((ConvertTo-SPSSignalNumber -Value $Signals[$signalName]) -gt 0) {
            $isBlocked = $true
            $reasons.Add(("blocking: {0}" -f $signalName))
        }
    }
    if ($isBlocked) { $category = 4 }

    return [PSCustomObject]@{
        Score        = [math]::Round($score, 2)
        Category     = $category
        CategoryName = $categoryNames[$category]
        Reasons      = $reasons.ToArray()
    }
}
