# Behavior tests for the Custom event receivers section of ConvertTo-SPSInventoryHtml (pure HTML rendering, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:Site = [PSCustomObject]@{
        InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/team'; Title = 'Team'; WebApp = 'Intranet'
        AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
    }

    function New-Row {
        param (
            [string]$Site = 'https://intranet/sites/team', [string]$AssemblyName = 'Contoso.Intranet', [string]$Version = '1.0.0.0', [string]$Token = '0123456789abcdef',
            [string]$Class = 'Contoso.Intranet.ItemReceiver', [int]$Receivers = 6, [int]$Lists = 2, [string]$Match = 'NotChecked', [string]$Farm = '', [string]$Package = ''
        )
        [PSCustomObject]@{
            SiteUrl = $Site; Assembly = ('{0}, Version={1}, Culture=neutral, PublicKeyToken={2}' -f $AssemblyName, $Version, $Token); AssemblyName = $AssemblyName
            AssemblyVersion = $Version; PublicKeyToken = $Token; Class = $Class; ReceiverCount = $Receivers; ListCount = $Lists
            EventTypes = 'ItemAdded'; FirstListUrl = '/sites/team/Lists/Tasks'; SolutionMatch = $Match; FarmSolutionName = $Farm; PackageName = $Package
        }
    }

    function Get-Report {
        param ([object[]]$Row, [hashtable]$Extra = @{})
        $parameters = @{ InputObject = @($script:Site); EventReceiverClasses = $Row }
        foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
        ConvertTo-SPSInventoryHtml @parameters
    }

    function Get-Section {
        param ([string]$Html)
        [regex]::Match($Html, '(?s)<h2 id="custom-event-receivers">.*?(?=<h2 |<div class="footer">)').Value
    }

    function Get-RowHtml {
        param ([string]$Section)
        @([regex]::Matches($Section, '(?s)<tr><td>.*?</tr>') | ForEach-Object { $_.Value })
    }

    function Get-Cell {
        param ([string]$Row)
        @([regex]::Matches($Row, '(?s)<td[^>]*>(.*?)</td>') | ForEach-Object { $_.Groups[1].Value })
    }

    # The cells of the first row of the section. A function that returns one row gives a string, so the rows are collected first.
    function Get-FirstRowCell {
        param ([string]$Html)
        $row = @(Get-RowHtml -Section (Get-Section -Html $Html))
        return @(Get-Cell -Row $row[0])
    }
}

Describe 'ConvertTo-SPSInventoryHtml event receivers' {
    It 'adds no section and no link when no row is given' -ForEach @(
        @{ Case = 'the parameter is left out'; Row = $null }
        @{ Case = 'an empty list'; Row = @() }
        @{ Case = 'a list that has only a null'; Row = @($null) }
    ) {
        $html = if ($null -eq $Row) { ConvertTo-SPSInventoryHtml -InputObject @($script:Site) } else { Get-Report -Row $Row }

        $html | Should -Not -Match 'custom-event-receivers' -Because $Case
        $html | Should -Not -Match 'Custom event receivers</h2>'
    }

    It 'adds the section, with a link in the navigation' {
        $html = Get-Report -Row @((New-Row))

        $html | Should -Match '<a href="#custom-event-receivers">Event receivers</a>'
        $html | Should -Match '<h2 id="custom-event-receivers">Custom event receivers</h2>'
        $html | Should -Match '<table class="eventreceivers">'
    }

    It 'puts the section after the solution packages' {
        $package = [PSCustomObject]@{
            PackageName = 'Contoso.Intranet'; Status = 'Inspected'; Detail = ''; IsCustom = $true; IsCustomSource = 'Assembly'; IsFullTrustCode = $false
            AssemblyCount = 1; CustomAssemblyCount = 1; FeatureCount = 1; FeatureReceiverCount = 0; TargetFrameworks = @('.NETFramework,Version=v4.8')
            LegacyFrameworkAssemblyCount = 0; InFarm = $null; FarmSolutionName = ''; FarmMatch = ''; Difference = @()
        }

        $html = Get-Report -Row @((New-Row)) -Extra @{ SolutionPackages = @($package) }

        $html.IndexOf('id="solution-packages"') | Should -BeGreaterThan 0
        $html.IndexOf('id="solution-packages"') | Should -BeLessThan $html.IndexOf('id="custom-event-receivers"')
        $html | Should -Match '<a href="#solution-packages">Solution packages</a>\s*<a href="#custom-event-receivers">Event receivers</a>'
    }

    It 'counts the receivers, the assemblies, the classes and the site collections' {
        $row = @(
            (New-Row -Site 'https://intranet/sites/a' -Class 'Contoso.Intranet.A' -Receivers 10)
            (New-Row -Site 'https://intranet/sites/a' -Class 'Contoso.Intranet.B' -Receivers 5)
            (New-Row -Site 'https://intranet/sites/b' -Class 'Contoso.Intranet.A' -Receivers 1)
            (New-Row -Site 'https://intranet/sites/b' -AssemblyName 'Fabrikam.Docs' -Token '' -Class 'Fabrikam.Docs.Receiver' -Receivers 4)
        )

        $section = Get-Section -Html (Get-Report -Row $row)

        $section | Should -Match '<div class="summary-total"><strong>20</strong> receiver\(s\) &middot; <strong>2</strong> assembly\(ies\) &middot; <strong>3</strong> class\(es\) &middot; <strong>2</strong> site collection\(s\)</div>'
    }

    It 'groups the rows by assembly, and adds up the classes, the receivers and the site collections' {
        $row = @(
            (New-Row -Site 'https://intranet/sites/a' -Class 'Contoso.Intranet.A' -Receivers 10 -Lists 4)
            (New-Row -Site 'https://intranet/sites/a' -Class 'Contoso.Intranet.B' -Receivers 5 -Lists 1)
            (New-Row -Site 'https://intranet/sites/b' -Class 'Contoso.Intranet.A' -Receivers 1 -Lists 1)
        )

        $cell = Get-FirstRowCell -Html (Get-Report -Row $row)

        $cell | Should -HaveCount 6
        $cell[0] | Should -BeExactly 'Contoso.Intranet <span class="muted">0123456789abcdef</span>'
        $cell[3] | Should -BeExactly '2'
        $cell[4] | Should -BeExactly '16'
        $cell[5] | Should -BeExactly '2'
    }

    It 'shows no number of lists for an assembly: its classes are often on the same lists, and the rows cannot count a list once' {
        $row = @(
            (New-Row -Class 'Contoso.Intranet.A' -Receivers 300 -Lists 100)
            (New-Row -Class 'Contoso.Intranet.B' -Receivers 300 -Lists 100)
            (New-Row -Class 'Contoso.Intranet.C' -Receivers 300 -Lists 100)
        )
        $html = Get-Report -Row $row

        (Get-Section -Html $html) | Should -Match '<thead><tr><th>Assembly</th><th>Version</th><th>Solution</th><th class="num">Classes</th><th class="num">Receivers</th><th class="num">Site collections</th></tr></thead>'
        (Get-Section -Html $html) | Should -Not -Match '<th class="num">Lists</th>'
        $cell = Get-FirstRowCell -Html $html
        $cell | Should -HaveCount 6
        $cell[3] | Should -BeExactly '3'
        $cell[4] | Should -BeExactly '900'
        $cell[5] | Should -BeExactly '1'
        $cell | Should -Not -Contain '300'
    }

    It 'counts a class once, in the summary and in the table, when it is registered with two versions of its assembly' {
        $row = @(
            (New-Row -Version '1.0.0.0' -Class 'Contoso.Intranet.ItemReceiver' -Receivers 4)
            (New-Row -Version '2.0.0.0' -Class 'Contoso.Intranet.ItemReceiver' -Receivers 2)
        )
        $html = Get-Report -Row $row

        (Get-Section -Html $html) | Should -Match '<strong>6</strong> receiver\(s\) &middot; <strong>1</strong> assembly\(ies\) &middot; <strong>1</strong> class\(es\)'
        (Get-FirstRowCell -Html $html)[3] | Should -BeExactly '1'
    }

    It 'does not count the same site collection twice, whatever the case of its URL' {
        $row = @((New-Row -Site 'https://intranet/sites/a' -Class 'A'), (New-Row -Site 'HTTPS://INTRANET/sites/A' -Class 'B'))

        (Get-FirstRowCell -Html (Get-Report -Row $row))[5] | Should -Be '1'
    }

    It 'keeps two assemblies of the same name apart when their public key tokens differ' {
        $row = @((New-Row -Token '0123456789abcdef' -Receivers 3), (New-Row -Token 'fedcba9876543210' -Receivers 2))

        @(Get-RowHtml -Section (Get-Section -Html (Get-Report -Row $row))) | Should -HaveCount 2
    }

    It 'lists the assembly with the most receivers first, then by name' {
        $row = @(
            (New-Row -AssemblyName 'Zeta' -Receivers 5)
            (New-Row -AssemblyName 'Alpha' -Receivers 5)
            (New-Row -AssemblyName 'Big' -Receivers 50)
            (New-Row -AssemblyName 'Small' -Receivers 1)
        )

        $rowHtml = Get-RowHtml -Section (Get-Section -Html (Get-Report -Row $row))

        @($rowHtml | ForEach-Object { (Get-Cell -Row $_)[0] -replace ' <span.*$', '' }) | Should -Be @('Big', 'Alpha', 'Zeta', 'Small')
    }

    It 'shows the versions of an assembly, and says that it is not signed when it has no token' {
        $row = @(
            (New-Row -AssemblyName 'Contoso.Intranet' -Version '2.0.0.0' -Class 'A')
            (New-Row -AssemblyName 'Contoso.Intranet' -Version '1.0.0.0' -Class 'B')
            (New-Row -AssemblyName 'Fabrikam.Docs' -Version '3.0.0.0' -Token '' -Receivers 1)
        )

        $rowHtml = Get-RowHtml -Section (Get-Section -Html (Get-Report -Row $row))

        (Get-Cell -Row $rowHtml[0])[1] | Should -Be '1.0.0.0; 2.0.0.0'
        (Get-Cell -Row $rowHtml[1])[0] | Should -Be 'Fabrikam.Docs <span class="muted">not signed</span>'
    }

    It 'shows the solution of the assembly according to what the packages say' -ForEach @(
        @{ Case = 'the farm solution'; Match = 'AssemblyNameAndKey'; Farm = 'contoso.intranet.wsp'; Package = 'Contoso.Intranet.wsp'; Expected = 'contoso.intranet.wsp' }
        @{ Case = 'the package, when it is not in the farm'; Match = 'AssemblyNameAndKey'; Farm = ''; Package = 'Contoso.Intranet.wsp'; Expected = 'Contoso.Intranet.wsp <span class="muted">(package)</span>' }
        @{ Case = 'a match on the name alone'; Match = 'AssemblyName'; Farm = 'contoso.intranet.wsp'; Package = 'Contoso.Intranet.wsp'; Expected = 'contoso.intranet.wsp <span class="muted">(by name)</span>' }
        @{ Case = 'no package that ships it'; Match = 'None'; Farm = ''; Package = ''; Expected = '<span class="pill warn">No inspected package</span>' }
        @{ Case = 'packages that were not inspected'; Match = 'NotChecked'; Farm = ''; Package = ''; Expected = '<span class="muted">-</span>' }
    ) {
        $cell = Get-FirstRowCell -Html (Get-Report -Row @((New-Row -Match $Match -Farm $Farm -Package $Package)))

        $cell[2] | Should -Be $Expected -Because $Case
    }

    It 'tells to inspect the packages when it does not know the solution, and says what the solution is when it does' {
        $unknown = Get-Section -Html (Get-Report -Row @((New-Row -Match 'NotChecked')))
        $known = Get-Section -Html (Get-Report -Row @((New-Row -Match 'AssemblyNameAndKey' -Farm 'a.wsp' -Package 'a.wsp')))

        $unknown | Should -Match 'The solution that ships an assembly is not known: inspect the WSP packages \(-ExportSolutionPackage or -SolutionPackagePath\) to name it\.'
        $known | Should -Not -Match 'is not known'
        $known | Should -Match 'The solution is the farm solution of an inspected package that ships the assembly\.'
    }

    It 'explains what the signal counts' {
        $section = Get-Section -Html (Get-Report -Row @((New-Row)))

        $section | Should -Match 'SharePoint registers one receiver per event type and per list'
        $section | Should -Match 'Only the receivers of lists and libraries are read'
        $section | Should -Match 'an assembly whose name starts with Microsoft\. is not custom'
        $section | Should -Match 'The event receivers CSV and JSON files give each assembly and class with its receivers and lists, by site collection \(up to 200 assemblies and classes for each\)\.'
    }

    It 'encodes the text of the rows, which is registered in SharePoint' {
        $row = @(
            (New-Row -AssemblyName '<script>alert(1)</script>' -Version '<b>1</b>' -Token '"x"' -Match 'AssemblyName' -Farm '<img src=x onerror=alert(1)>' -Package 'p')
            (New-Row -AssemblyName 'Fabrikam.Docs' -Match 'AssemblyNameAndKey' -Farm '' -Package '<u>pkg</u>' -Receivers 1)
        )

        $section = Get-Section -Html (Get-Report -Row $row)

        $section | Should -Not -Match '<script>'
        $section | Should -Not -Match '<img '
        $section | Should -Not -Match '<b>1'
        $section | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $section | Should -Match '&lt;img src=x onerror=alert\(1\)&gt;'
        $section | Should -Match '&lt;b&gt;1&lt;/b&gt;'
        $section | Should -Match '&quot;x&quot;'
        $section | Should -Not -Match '<u>pkg'
        $section | Should -Match '&lt;u&gt;pkg&lt;/u&gt; <span class="muted">\(package\)</span>'
    }

    It 'shows at most MaxDetailRow assemblies and says how many are not shown' {
        $row = 1..3 | ForEach-Object { New-Row -AssemblyName ('Contoso.A{0}' -f $_) }

        $section = Get-Section -Html (Get-Report -Row $row -Extra @{ MaxDetailRow = 2 })

        @(Get-RowHtml -Section $section) | Should -HaveCount 2
        $section | Should -Match '<p class="muted">Showing the first 2 of 3 assemblies\. The event receivers CSV and JSON files list the others, by site collection \(up to 200 assemblies and classes for each\)\.</p>'
    }

    It 'shows no note about assemblies that are not shown when every assembly is shown' {
        (Get-Section -Html (Get-Report -Row @((New-Row)))) | Should -Not -Match 'Showing the first'
    }

    It 'puts the section in the entry page of a split report, and not in the table pages' {
        $site = 1..3 | ForEach-Object { [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/s$_"; Title = "s$_"; WebApp = 'Intranet'; AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = '' } }

        $pages = @(ConvertTo-SPSInventoryHtml -InputObject $site -EventReceiverClasses @((New-Row)) -FileName 'report.html' -SplitThreshold 1 -RowsPerPage 50)

        $pages.Count | Should -BeGreaterThan 1
        ($pages | Where-Object { $_.Kind -eq 'Entry' }).Html | Should -Match 'id="custom-event-receivers"'
        foreach ($page in @($pages | Where-Object { $_.Kind -eq 'Sites' })) {
            $page.Html | Should -Not -Match 'id="custom-event-receivers"'
        }
    }

    It 'renders the rows that the collector gives' {
        $rows = & $script:Module {
            $table = [System.Collections.Generic.Dictionary[System.String, System.Object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $list = [PSCustomObject]@{ ID = [guid]::NewGuid(); Title = 'Tasks'; RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Lists/Tasks' } }
            $receiver = [PSCustomObject]@{ Assembly = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'; Class = 'Contoso.Intranet.ItemReceiver'; Type = 'ItemAdded' }
            $null = Add-SPSEventReceiverClass -Table $table -Receiver $receiver -List $list
            $null = Add-SPSEventReceiverClass -Table $table -Receiver $receiver -List $list
            $index = Get-SPSSolutionAssemblyIndex -SolutionPackages @([PSCustomObject]@{ PackageName = 'Contoso.Intranet.wsp'; FarmSolutionName = 'contoso.intranet.wsp'; Assemblies = @([PSCustomObject]@{ Name = 'Contoso.Intranet'; PublicKeyToken = '0123456789abcdef'; Version = '1.0.0.0'; IsSatellite = $false; IsManaged = $true }) })
            ConvertTo-SPSEventReceiverClassRow -Table $table -SiteUrl 'https://intranet/sites/team' -SolutionAssemblyIndex $index
        }

        $cell = Get-FirstRowCell -Html (Get-Report -Row @($rows))

        $cell[0] | Should -Be 'Contoso.Intranet <span class="muted">0123456789abcdef</span>'
        $cell[1] | Should -Be '1.0.0.0'
        $cell[2] | Should -Be 'contoso.intranet.wsp'
        $cell | Should -HaveCount 6
        $cell[3] | Should -Be '1'
        $cell[4] | Should -Be '2'
        $cell[5] | Should -Be '1'
    }
}
