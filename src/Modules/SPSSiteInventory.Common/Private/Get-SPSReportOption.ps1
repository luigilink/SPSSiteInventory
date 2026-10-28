function Get-SPSReportOption {
    <#
        .SYNOPSIS
        Reads and validates the Report section of the inventory settings.

        .DESCRIPTION
        The Report section tunes the HTML report. HtmlSplitThreshold (default 3000) is the number of
        site collections above which the report is split in several pages, an entry page and the
        table of the site collections on pages of their own; 0 never splits. HtmlRowsPerPage
        (default 500, from 50 to 5000) is the number of site collections that a table page of a split
        report holds at most. Both have their default also when the section is missing, as in a
        settings file of a version that did not have it. A value that is not a whole number in its
        range is rejected instead of being coerced: the text '3000' or a boolean would otherwise
        turn the split on or off without anybody having chosen it.

        Private because it is an implementation detail of the settings loader and of the
        orchestrator, which share it so that the defaults and the validation live in one place.

        .PARAMETER Settings
        The Report section, or nothing when the settings file has none.

        .EXAMPLE
        (Get-SPSReportOption -Settings @{ HtmlSplitThreshold = 0 }).HtmlSplitThreshold
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Collections.IDictionary]
        $Settings = @{}
    )

    $option = [ordered]@{
        HtmlSplitThreshold = 3000
        HtmlRowsPerPage = 500
    }
    $range = @{
        HtmlSplitThreshold = @(0, 10000000)
        HtmlRowsPerPage = @(50, 5000)
    }
    foreach ($name in @($option.Keys)) {
        if ($null -ne $Settings -and $Settings.Contains($name)) {
            $value = $Settings[$name]
            $isWholeNumber = $value -is [System.Int32] -or $value -is [System.Int64]
            if (-not $isWholeNumber -or $value -lt $range[$name][0] -or $value -gt $range[$name][1]) {
                throw ('Report.{0} must be a whole number from {1} to {2}.' -f $name, $range[$name][0], $range[$name][1])
            }
            $option[$name] = [System.Int32]$value
        }
    }

    [PSCustomObject]$option
}
