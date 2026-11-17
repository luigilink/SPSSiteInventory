# Behavior tests for the Workflow associations section of ConvertTo-SPSInventoryHtml (pure HTML rendering, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    $script:Site = [PSCustomObject]@{
        InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/team'; Title = 'Team'; WebApp = 'Intranet'
        AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
    }

    function New-Row {
        param (
            [string]$Site = 'https://intranet/sites/team', [string]$Web = 'https://intranet/sites/team', [string]$Scope = 'List', [string]$List = 'Documents',
            [string]$Name = 'Approval', [bool]$Counted = $true, [int]$Running = 0
        )
        [PSCustomObject]@{ SiteUrl = $Site; WebUrl = $Web; Scope = $Scope; ListTitle = $List; ListUrl = '/sites/team/Shared Documents'; WorkflowName = $Name; Counted = $Counted; RunningInstances = $Running }
    }

    function Get-Report {
        param ([object[]]$Row, [hashtable]$Extra = @{})
        $parameters = @{ InputObject = @($script:Site); WorkflowAssociations = $Row }
        foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
        ConvertTo-SPSInventoryHtml @parameters
    }

    function Get-Section {
        param ([string]$Html)
        [regex]::Match($Html, '(?s)<h2 id="workflow-associations">.*?(?=<h2 |<div class="footer">)').Value
    }

    function Get-RowHtml {
        param ([string]$Section)
        @([regex]::Matches($Section, '(?s)<tr><td>.*?</tr>') | ForEach-Object { $_.Value })
    }

    function Get-Cell {
        param ([string]$Row)
        @([regex]::Matches($Row, '(?s)<td[^>]*>(.*?)</td>') | ForEach-Object { $_.Groups[1].Value })
    }

    # The cells of the rows of the section, one array for each row. A function that returns one row gives a string, so the rows are collected first.
    function Get-RowCell {
        param ([string]$Html)
        $rows = @(Get-RowHtml -Section (Get-Section -Html $Html))
        foreach ($row in $rows) { , @(Get-Cell -Row $row) }
    }
}

Describe 'ConvertTo-SPSInventoryHtml workflow associations' {
    It 'adds no section and no link when no row is given' -ForEach @(
        @{ Case = 'the parameter is left out'; Row = $null }
        @{ Case = 'an empty list'; Row = @() }
        @{ Case = 'a list that has only a null'; Row = @($null) }
    ) {
        $html = if ($null -eq $Row) { ConvertTo-SPSInventoryHtml -InputObject @($script:Site) } else { Get-Report -Row $Row }

        $html | Should -Not -Match 'id="workflow-associations"' -Because $Case
        $html | Should -Not -Match 'href="#workflow-associations"' -Because $Case
        $html | Should -Not -Match 'Workflow associations</h2>'
    }

    It 'adds the section, with a link in the navigation' {
        $html = Get-Report -Row @((New-Row))

        $html | Should -Match '<a href="#workflow-associations">Workflow associations</a>'
        $html | Should -Match '<h2 id="workflow-associations">Workflow associations</h2>'
        $html | Should -Match '<table class="workflowassociations">'
        $html | Should -Match '<thead><tr><th>Site collection</th><th>Web</th><th>List or library</th><th>Workflow</th><th>Counted</th><th class="num">Running instances</th></tr></thead>'
    }

    It 'puts the section after the event receivers' {
        $receiver = [PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/team'; Assembly = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'; AssemblyName = 'Contoso.Intranet'
            AssemblyVersion = '1.0.0.0'; PublicKeyToken = '0123456789abcdef'; Class = 'Contoso.Intranet.ItemReceiver'; ReceiverCount = 1; ListCount = 1
            EventTypes = 'ItemAdded'; FirstListUrl = '/sites/team/Lists/Tasks'; SolutionMatch = 'NotChecked'; FarmSolutionName = ''; PackageName = ''
        }

        $html = Get-Report -Row @((New-Row)) -Extra @{ EventReceiverClasses = @($receiver) }

        $html.IndexOf('id="custom-event-receivers"') | Should -BeGreaterThan 0
        $html.IndexOf('id="custom-event-receivers"') | Should -BeLessThan $html.IndexOf('id="workflow-associations"')
        $html | Should -Match '<a href="#custom-event-receivers">Event receivers</a>\s*<a href="#workflow-associations">Workflow associations</a>'
    }

    It 'counts the associations, the counted ones, the running instances and the site collections' {
        $row = @(
            (New-Row -Site 'https://intranet/sites/a' -Name 'Approval' -Running 5)
            (New-Row -Site 'https://intranet/sites/a' -Name 'Approval (Previous Version: 1)' -Counted $false -Running 4)
            (New-Row -Site 'https://intranet/sites/b' -Name 'Review' -Running 1)
        )

        $section = Get-Section -Html (Get-Report -Row $row)

        $section | Should -Match '<div class="summary-total"><strong>3</strong> association\(s\) &middot; <strong>2</strong> counted &middot; <strong>10</strong> running instance\(s\) &middot; <strong>2</strong> site collection\(s\)</div>'
    }

    It 'does not count the same site collection twice, whatever the case of its URL' {
        $row = @((New-Row -Site 'https://intranet/sites/a'), (New-Row -Site 'HTTPS://INTRANET/sites/A' -Name 'Other'))

        (Get-Section -Html (Get-Report -Row $row)) | Should -Match '<strong>1</strong> site collection\(s\)'
    }

    It 'shows the site collection, the web, the list, the workflow, whether it is counted and the running instances' {
        $row = @((New-Row -Site 'https://intranet/sites/team' -Web 'https://intranet/sites/team/hr' -List 'Documents' -Name 'Approval' -Running 12))

        $cell = @(Get-RowCell -Html (Get-Report -Row $row))

        $cell | Should -HaveCount 1
        $cell[0] | Should -HaveCount 6
        $cell[0][0] | Should -BeExactly 'https://intranet/sites/team'
        $cell[0][1] | Should -BeExactly 'https://intranet/sites/team/hr'
        $cell[0][2] | Should -BeExactly 'Documents'
        $cell[0][3] | Should -BeExactly 'Approval'
        $cell[0][4] | Should -BeExactly 'Yes'
        $cell[0][5] | Should -BeExactly '12'
    }

    It 'says web, and not a list, for an association of a web, and says that a previous version is not counted' {
        $row = @(
            (New-Row -Scope 'Web' -List '' -Name 'Publication' -Running 2)
            (New-Row -Name 'Old' -Counted $false -Running 1)
        )

        $cell = @(Get-RowCell -Html (Get-Report -Row $row))

        $cell[0][2] | Should -BeExactly '<span class="muted">web</span>'
        $cell[0][4] | Should -BeExactly 'Yes'
        $cell[1][2] | Should -BeExactly 'Documents'
        $cell[1][4] | Should -BeExactly '<span class="muted">No (previous version)</span>'
    }

    It 'lists the counted associations first, the ones with the most running instances first, then by site, web, list and name' {
        $row = @(
            (New-Row -Name 'Previous busy' -Counted $false -Running 50)
            (New-Row -Name 'Zeta' -Running 5)
            (New-Row -Name 'Alpha' -Running 5)
            (New-Row -Name 'Busy' -Running 20)
            (New-Row -Name 'Idle' -Running 0)
        )

        $cell = @(Get-RowCell -Html (Get-Report -Row $row))

        @($cell | ForEach-Object { $_[3] }) | Should -BeExactly @('Busy', 'Alpha', 'Zeta', 'Idle', 'Previous busy')
    }

    It 'lists the associations that tie on the counted flag and on the running instances by site collection, web, list and name' {
        # Each pair is in the order that only one key gives: the other keys would put it the other way round.
        $row = @(
            (New-Row -Site 'https://intranet/sites/b' -Web 'https://intranet/web/aa' -List 'L' -Name 'N')
            (New-Row -Site 'https://intranet/sites/a' -Web 'https://intranet/web/zz' -List 'L' -Name 'N')
            (New-Row -Site 'https://intranet/sites/c' -Web 'https://intranet/web/w2' -List 'Alpha' -Name 'N')
            (New-Row -Site 'https://intranet/sites/c' -Web 'https://intranet/web/w1' -List 'Zeta' -Name 'N')
            (New-Row -Site 'https://intranet/sites/d' -Web 'https://intranet/web/d' -List 'Tasks' -Name 'A')
            (New-Row -Site 'https://intranet/sites/d' -Web 'https://intranet/web/d' -List 'Documents' -Name 'B')
            (New-Row -Site 'https://intranet/sites/e' -Web 'https://intranet/web/e' -List 'L' -Name 'Flow2')
            (New-Row -Site 'https://intranet/sites/e' -Web 'https://intranet/web/e' -List 'L' -Name 'Flow1')
        )

        $cell = @(Get-RowCell -Html (Get-Report -Row $row))

        @($cell | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_[0], $_[1], $_[2], $_[3] }) | Should -BeExactly @(
            'https://intranet/sites/a|https://intranet/web/zz|L|N'
            'https://intranet/sites/b|https://intranet/web/aa|L|N'
            'https://intranet/sites/c|https://intranet/web/w1|Zeta|N'
            'https://intranet/sites/c|https://intranet/web/w2|Alpha|N'
            'https://intranet/sites/d|https://intranet/web/d|Documents|B'
            'https://intranet/sites/d|https://intranet/web/d|Tasks|A'
            'https://intranet/sites/e|https://intranet/web/e|L|Flow1'
            'https://intranet/sites/e|https://intranet/web/e|L|Flow2'
        )
    }

    It 'explains what the associations are, and that the rows of the previous versions stop at 1000' {
        $section = Get-Section -Html (Get-Report -Row @((New-Row)))

        $section | Should -Match 'The SharePoint 2010 workflow associations of the webs, lists and libraries that the Workflow 2010 signals count\.'
        $section | Should -Match 'a previous version is not counted, but its running instances are in the running total'
        $section | Should -Match 'The SharePoint 2010 workflow engine is retired in SharePoint Online'
        $section | Should -Match 'The counted associations with the most running instances come first\.'
        $section | Should -Match 'The workflow association CSV and JSON files give every association, by site collection \(the rows of the previous versions stop at 1000 for each\)\.'
    }

    It 'encodes the text of the rows, which is written in SharePoint' {
        $row = @(
            (New-Row -Site 'https://intranet/sites/<b>x</b>' -Web '"web"' -List '<script>alert(1)</script>' -Name '<img src=x onerror=alert(1)>' -Running 1)
        )

        $section = Get-Section -Html (Get-Report -Row $row)

        $section | Should -Not -Match '<script>'
        $section | Should -Not -Match '<img '
        $section | Should -Not -Match '<b>x'
        $section | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $section | Should -Match '&lt;img src=x onerror=alert\(1\)&gt;'
        $section | Should -Match '&lt;b&gt;x&lt;/b&gt;'
        $section | Should -Match '&quot;web&quot;'
    }

    It 'shows at most MaxDetailRow associations and says how many are not shown' {
        $row = 1..3 | ForEach-Object { New-Row -Name ('Workflow {0}' -f $_) -Running (10 - $_) }

        $section = Get-Section -Html (Get-Report -Row $row -Extra @{ MaxDetailRow = 2 })

        @(Get-RowHtml -Section $section) | Should -HaveCount 2
        $section | Should -Match '<p class="muted">Showing the first 2 of 3 rows\. The workflow association CSV and JSON files hold all the rows\.</p>'
    }

    It 'shows no note about rows that are not shown when every row is shown' {
        (Get-Section -Html (Get-Report -Row @((New-Row)))) | Should -Not -Match 'Showing the first'
    }

    It 'puts the section in the entry page of a split report, and not in the table pages' {
        $site = 1..3 | ForEach-Object { [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/s$_"; Title = "s$_"; WebApp = 'Intranet'; AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = '' } }

        $pages = @(ConvertTo-SPSInventoryHtml -InputObject $site -WorkflowAssociations @((New-Row)) -FileName 'report.html' -SplitThreshold 1 -RowsPerPage 50)

        $pages.Count | Should -BeGreaterThan 1
        ($pages | Where-Object { $_.Kind -eq 'Entry' }).Html | Should -Match 'id="workflow-associations"'
        foreach ($page in @($pages | Where-Object { $_.Kind -eq 'Sites' })) {
            $page.Html | Should -Not -Match 'id="workflow-associations"'
        }
    }

    It 'renders the rows that the collector gives' {
        $association = [PSCustomObject]@{ Name = 'Approval'; RunningInstances = 3 }
        $rows = & (Get-Module -Name SPSSiteInventory.Common) {
            param ($Association)
            $table = [PSCustomObject]@{ Current = [System.Collections.Generic.List[object]]::new(); Previous = [System.Collections.Generic.List[object]]::new() }
            $null = Add-SPSWorkflowAssociationRow -Table $table -Association $Association -ActiveAssociation @($Association) -SiteUrl 'https://intranet/sites/team' -WebUrl 'https://intranet/sites/team' -Scope List -ListTitle 'Documents' -ListUrl '/sites/team/Shared Documents'
            @($table.Current)
        } $association

        $cell = @(Get-RowCell -Html (Get-Report -Row @($rows)))

        $cell | Should -HaveCount 1
        $cell[0][2] | Should -BeExactly 'Documents'
        $cell[0][3] | Should -BeExactly 'Approval'
        $cell[0][4] | Should -BeExactly 'Yes'
        $cell[0][5] | Should -BeExactly '3'
    }
}
