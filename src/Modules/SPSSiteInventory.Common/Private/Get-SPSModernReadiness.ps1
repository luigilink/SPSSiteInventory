function Get-SPSModernReadiness {
    <#
        .SYNOPSIS
        Summarizes the blockers of the modern experience of an inventory, by kind and by site collection.

        .DESCRIPTION
        Feeds the Modern experience readiness section of the HTML report. For every site collection that
        was assessed (a failed assessment has no signals and is only counted), it asks Get-SPSModernBlocker
        which kinds of blocker the site collection has, from the fields of its record, and returns:

        - Assessed, NotAssessed and WithBlocker: the site collections that were assessed, the ones that
          failed (their records are not looked at) and the assessed ones that have at least one blocker;
        - Kind: one row per kind of blocker, in a fixed order, also when no site collection has it, with
          its Name, Label, Unit, the number of site collections that have it (SiteCount) and the items
          behind it in all of them (Items, null for the custom master page, which is a state);
        - Site: the site collections that have a blocker, the most kinds first, then the highest score,
          then by URL, at most MaxSite of them, each with its Url, Title, AssessmentStatus, Category,
          CategoryName, Score, Count (the number of kinds) and Text (what Get-SPSModernBlocker says);
        - SiteTotal: how many site collections have a blocker, which is more than Site holds when the list
          is cut.

        The counts of a site collection whose assessment is partial are lower bounds, and Site says so
        through its AssessmentStatus. Web application rows (InventoryScope WebApplication) are ignored.
        The function is pure: it reads no farm.

        Private because it is an implementation detail of the HTML report.

        .PARAMETER InputObject
        The scored inventory records.

        .PARAMETER MaxSite
        How many site collections Site holds at most. Defaults to 100.

        .EXAMPLE
        (Get-SPSModernReadiness -InputObject $scored).Kind | Format-Table Label, SiteCount, Items
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $InputObject,

        [Parameter()]
        [ValidateRange(1, 1000000)]
        [System.Int32]
        $MaxSite = 100
    )

    $signalName = @(
        'CustomMasterPage', 'AlternateCssUrlCount', 'PublishingInfrastructureEnabled', 'PublishingWebCount',
        'XsltListViewCount', 'ScriptWebPartCount', 'ClassicExperienceOptOutCount', 'ClassicExperienceListCount'
    )

    # Every kind present, to take their names, their labels and their units, in their order.
    $everyKind = @{}
    foreach ($name in $signalName) { $everyKind[$name] = 1 }
    $kindDefinition = @((Get-SPSModernBlocker -Signals $everyKind).Kind)

    $kindSite = @{}
    $kindItems = @{}
    foreach ($definition in $kindDefinition) {
        $kindSite[$definition.Name] = 0
        $kindItems[$definition.Name] = 0.0
    }

    $assessed = 0
    $notAssessed = 0
    $site = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $InputObject) {
        if ($null -eq $record -or ($null -ne $record.PSObject.Properties['InventoryScope'] -and [string]$record.InventoryScope -eq 'WebApplication')) {
            continue
        }
        if ([string]$record.AssessmentStatus -eq 'Failed') {
            $notAssessed++
            continue
        }
        $assessed++

        $signals = @{}
        foreach ($name in $signalName) {
            $signals[$name] = if ($null -ne $record.PSObject.Properties[$name]) { $record.$name } else { $null }
        }
        $blocker = Get-SPSModernBlocker -Signals $signals
        if ($blocker.Count -eq 0) {
            continue
        }

        foreach ($kind in $blocker.Kind) {
            $kindSite[$kind.Name]++
            if ($null -ne $kind.Items) {
                $kindItems[$kind.Name] += $kind.Items
            }
        }
        $site.Add([PSCustomObject]@{
                Url              = [string]$record.Url
                Title            = [string]$record.Title
                AssessmentStatus = [string]$record.AssessmentStatus
                Category         = $record.Category
                CategoryName     = [string]$record.CategoryName
                Score            = ConvertTo-SPSSignalNumber -Value $record.Score
                Count            = $blocker.Count
                Text             = $blocker.Summary
            })
    }

    $sorted = @($site | Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.Score }; Descending = $true }, @{ Expression = { $_.Url } })

    return [PSCustomObject]@{
        Assessed    = $assessed
        NotAssessed = $notAssessed
        WithBlocker = $sorted.Count
        Kind        = @(
            foreach ($definition in $kindDefinition) {
                [PSCustomObject]@{
                    Name      = $definition.Name
                    Label     = $definition.Label
                    Unit      = $definition.Unit
                    SiteCount = $kindSite[$definition.Name]
                    Items     = if ($null -eq $definition.Items) { $null } else { $kindItems[$definition.Name] }
                }
            }
        )
        Site        = @($sorted | Select-Object -First $MaxSite)
        SiteTotal   = $sorted.Count
    }
}
