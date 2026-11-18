function Get-SPSScoreDriver {
    <#
        .SYNOPSIS
        Tells which signals make the score of an inventory, by signal and by category.

        .DESCRIPTION
        Feeds the Score drivers section of the HTML report. The score of a site collection is the sum of the
        weights of its signals, each one multiplied by the value of the signal (see Measure-SPSSiteComplexity),
        so one signal that has a large value and a large weight can hold most of it. Measure-SPSSiteComplexity
        writes what each signal added to the Reasons field of the record ("EventReceivers=121 (+181.5)", and
        "blocking: HasFbaZone" for a blocking signal), and this function reads that field, so it needs neither
        the settings nor any other field. Any other text of the field, such as the warnings of the assessment,
        is ignored. When a cap of Scoring.Caps cut what a signal added, the reason says so ("EventReceivers=121
        (+5, capped from 181.5)"): the contribution is the capped one, as in the score, and the site
        collection is counted in CappedSiteCount.

        The reasons round each contribution to two decimals, so a signal that adds less than 0.005 is written as
        (+0). Such a contribution cannot be told from nothing: it is not counted as a signal, and a site
        collection whose score has no signal that can be read is counted in Unresolved instead of Scored.

        It looks at the site collections that were assessed (a failed assessment has no score, and a web
        application row is not a site collection) and returns:

        - Assessed, Scored, Unresolved and TotalScore: the site collections that have a category, those of
          them that have at least one signal that can be read, those that have a score but none (the
          contributions were rounded to zero, or the reasons are missing), and the sum of what the signals
          added;
        - Signal: one row for each signal that added something to at least one site collection, with its
          Name, SiteCount, Total (what it added in all of them), Share (its part of TotalScore, from 0 to 1),
          TopSiteCount (the site collections where it added the most; a tie goes to the first name) and
          CappedSiteCount (the site collections where its cap cut what it added), the largest Total first;
        - Category: one row for each category that has a site collection, in the order of the categories,
          with its Category number, CategoryName, SiteCount, MinScore and MaxScore (the lowest and the highest
          Score of the record), Signal (the three that added the most in those site collections, each with its
          Name and its Share of what they added there) and Blocking (the blocking signals of those site
          collections, each with its Name and SiteCount, the most frequent first).

        The function is pure: it reads no farm. The numbers of the reasons are read with the invariant
        culture, as Measure-SPSSiteComplexity writes them.

        Private because it is an implementation detail of the HTML report.

        .PARAMETER InputObject
        The scored inventory records.

        .EXAMPLE
        (Get-SPSScoreDriver -InputObject $scored).Signal | Format-Table Name, Share, TopSiteCount
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $InputObject
    )

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $contributionPattern = [System.Text.RegularExpressions.Regex]::new('^(?<name>[^=;|]+)=(?<value>\S+) \(\+(?<amount>-?\d+(?:\.\d+)?)(?<capped>, capped from -?\d+(?:\.\d+)?)?\)$')
    $blockingPrefix = 'blocking: '
    $byValueThenName = @(@{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key } })

    $signalTotal = @{}
    $signalSite = @{}
    $signalTop = @{}
    $signalCapped = @{}
    $categoryData = @{}
    $assessed = 0
    $scored = 0
    $unresolved = 0
    $totalScore = 0.0

    foreach ($record in $InputObject) {
        if ($null -eq $record) {
            continue
        }
        if ($null -ne $record.PSObject.Properties['InventoryScope'] -and [string]$record.InventoryScope -eq 'WebApplication') {
            continue
        }
        if ([string]$record.AssessmentStatus -eq 'Failed') {
            continue
        }
        $categoryNumber = 0
        if ($null -ne $record.PSObject.Properties['Category'] -and $null -ne $record.Category) {
            $categoryNumber = [int]$record.Category
        }
        if ($categoryNumber -le 0) {
            continue
        }
        $assessed++

        $contribution = @{}
        $cappedName = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
        $blockingName = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
        $reasonText = (@($record.Reasons) | ForEach-Object { [string]$_ }) -join '; '
        foreach ($part in ($reasonText -split '; ')) {
            $match = $contributionPattern.Match($part)
            if ($match.Success) {
                $amount = [double]::Parse($match.Groups['amount'].Value, $invariant)
                # (+0) is a contribution that the reasons rounded away: it is not a signal that can be read.
                if ($amount -ne 0) {
                    $contribution[$match.Groups['name'].Value] = $amount
                    if ($match.Groups['capped'].Success) {
                        [void]$cappedName.Add($match.Groups['name'].Value)
                    }
                }
            }
            elseif ($part.StartsWith($blockingPrefix, [System.StringComparison]::Ordinal)) {
                [void]$blockingName.Add($part.Substring($blockingPrefix.Length).Trim())
            }
        }

        $score = 0.0
        if ($null -ne $record.PSObject.Properties['Score'] -and $null -ne $record.Score) {
            try { $score = [double]$record.Score } catch { $score = 0.0 }
        }
        if (-not $categoryData.ContainsKey($categoryNumber)) {
            $categoryData[$categoryNumber] = @{
                Name = [string]$record.CategoryName; Count = 0; Min = $score; Max = $score; Total = 0.0
                Signal = @{}; Blocking = @{}
            }
        }
        $category = $categoryData[$categoryNumber]
        $category.Count++
        if ($score -lt $category.Min) { $category.Min = $score }
        if ($score -gt $category.Max) { $category.Max = $score }
        foreach ($name in $blockingName) {
            $category.Blocking[$name] = 1 + [int]$category.Blocking[$name]
        }

        if ($contribution.Count -eq 0) {
            if ($score -gt 0) {
                $unresolved++
            }
            continue
        }
        $scored++
        $top = @($contribution.GetEnumerator() | Sort-Object -Property $byValueThenName | Select-Object -First 1)[0]
        $signalTop[$top.Key] = 1 + [int]$signalTop[$top.Key]
        foreach ($name in $contribution.Keys) {
            $amount = [double]$contribution[$name]
            $signalTotal[$name] = [double]$signalTotal[$name] + $amount
            $signalSite[$name] = 1 + [int]$signalSite[$name]
            if ($cappedName.Contains($name)) {
                $signalCapped[$name] = 1 + [int]$signalCapped[$name]
            }
            $category.Signal[$name] = [double]$category.Signal[$name] + $amount
            $category.Total += $amount
            $totalScore += $amount
        }
    }

    $signalRow = @(
        foreach ($name in $signalTotal.Keys) {
            [PSCustomObject]@{
                Name            = [string]$name
                SiteCount       = [int]$signalSite[$name]
                Total           = [double]$signalTotal[$name]
                Share           = if ($totalScore -gt 0) { [double]$signalTotal[$name] / $totalScore } else { 0.0 }
                TopSiteCount    = [int]$signalTop[$name]
                CappedSiteCount = [int]$signalCapped[$name]
            }
        }
    ) | Sort-Object -Property @{ Expression = { $_.Total }; Descending = $true }, @{ Expression = { $_.Name } }

    $categoryRow = @(
        foreach ($number in ($categoryData.Keys | Sort-Object)) {
            $category = $categoryData[$number]
            [PSCustomObject]@{
                Category     = [int]$number
                CategoryName = [string]$category.Name
                SiteCount    = [int]$category.Count
                MinScore     = [double]$category.Min
                MaxScore     = [double]$category.Max
                Signal       = @(
                    $category.Signal.GetEnumerator() | Sort-Object -Property $byValueThenName | Select-Object -First 3 | ForEach-Object {
                        [PSCustomObject]@{ Name = [string]$_.Key; Share = if ($category.Total -gt 0) { [double]$_.Value / $category.Total } else { 0.0 } }
                    }
                )
                Blocking     = @(
                    $category.Blocking.GetEnumerator() | Sort-Object -Property $byValueThenName | ForEach-Object {
                        [PSCustomObject]@{ Name = [string]$_.Key; SiteCount = [int]$_.Value }
                    }
                )
            }
        }
    )

    return [PSCustomObject]@{
        Assessed   = $assessed
        Scored     = $scored
        Unresolved = $unresolved
        TotalScore = $totalScore
        Signal     = @($signalRow)
        Category   = @($categoryRow)
    }
}
