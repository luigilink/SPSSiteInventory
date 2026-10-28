# Behavior tests for the pages of ConvertTo-SPSInventoryHtml: the report as one file, and as several for a
# farm with many site collections (pure HTML rendering, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-SiteRecord {
        param ([string]$Name, [int]$Category, [string]$CategoryName, [double]$Score = 0, [hashtable]$Extra = @{})
        $record = [ordered]@{
            InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$Name"; Title = $Name; WebApp = 'Intranet'
            AssessmentStatus = 'Complete'; Category = $Category; CategoryName = $CategoryName; Score = $Score
            Wave = $Category; WaveName = "Wave $Category"; SizeGB = 0.5; Template = 'STS#0'; Reasons = ''
        }
        foreach ($key in $Extra.Keys) { $record[$key] = $Extra[$key] }
        [PSCustomObject]$record
    }

    # 2 rows that are not assessed, 3 Blocking, 60 Moderate and 120 Simple site collections. With 50 rows a page, that
    # makes 1 + 1 + 2 + 3 table pages. Sorted by score, then URL, the Moderate m55 is on its second page, and the two
    # Simple site collections with large lists are on the first and the third.
    $records = [System.Collections.Generic.List[object]]::new()
    $records.Add([PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/failed'; AssessmentStatus = 'Failed'; Category = $null; CategoryName = 'Not assessed'; Wave = 0; WaveName = 'Not assessed'; Score = $null; Reasons = 'Assessment failed' })
    $records.Add([PSCustomObject]@{ InventoryScope = 'WebApplication'; Url = 'https://other'; AssessmentStatus = 'Failed'; Category = $null; CategoryName = 'Not assessed'; Wave = 0; WaveName = 'Not assessed'; AssessmentWarnings = 'The site collections could not be listed' })
    foreach ($index in 0..2) { $records.Add((New-SiteRecord -Name ('b{0}' -f $index) -Category 4 -CategoryName 'Blocking' -Score 9 -Extra @{ UsesFullTrustCode = ($index -eq 1) })) }
    foreach ($index in 0..59) { $records.Add((New-SiteRecord -Name ('m{0:00}' -f $index) -Category 2 -CategoryName 'Moderate' -Score 2 -Extra @{ CustomMasterPage = ($index -eq 55) })) }
    foreach ($index in 0..119) { $records.Add((New-SiteRecord -Name ('s{0:000}' -f $index) -Category 1 -CategoryName 'Simple' -Score 0 -Extra @{ LargeListCount = $(if ($index -in @(10, 100)) { 1 } else { 0 }) })) }
    $script:Records = $records.ToArray()

    $script:Alerts = @(
        [PSCustomObject]@{ AlertType = 'LargeLists'; Severity = 'Medium'; Url = 'https://intranet/sites/s010'; Value = 1; Message = 'm'; Remediation = 'Clean up.'; Reference = 'https://learn.microsoft.com/en-us/x' }
    )
    $script:Common = @{ EnvName = 'PROD'; GeneratedOn = [datetime]'2026-10-28T10:08:00'; Alert = $script:Alerts }

    function Get-SplitPage {
        param ([string]$FileName = 'report.html', [int]$RowsPerPage = 50, [int]$SplitThreshold = 100)
        @(ConvertTo-SPSInventoryHtml -InputObject $script:Records @script:Common -FileName $FileName -SplitThreshold $SplitThreshold -RowsPerPage $RowsPerPage)
    }

    function Get-Link {
        param ([string]$Html)
        @([regex]::Matches($Html, '(?:href|src)="([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
    }

    function Get-Row {
        param ([string]$Html)
        @([regex]::Matches($Html, '(?s)<tbody class="site".*?</tbody>') | ForEach-Object { $_.Value })
    }

    function Get-PageData {
        param ([string]$Html)
        $json = [regex]::Match($Html, '(?s)<script type="application/json" id="inv-split">(.*?)</script>').Groups[1].Value
        ConvertFrom-Json -InputObject $json
    }
}

Describe 'ConvertTo-SPSInventoryHtml pages' {
    It 'returns the report as one string by default, with no page object' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Records @script:Common

        $html | Should -BeOfType [string]
        $html | Should -Match '<table id="inv">'
        $html | Should -Not -Match 'id="inv-split"'
    }

    It 'returns one page, the same as the single report, for a farm with no more site collections than the threshold, or with a threshold of 0' {
        $single = ConvertTo-SPSInventoryHtml -InputObject $script:Records @script:Common

        foreach ($threshold in @(185, 1000, 0)) {
            $pages = @(ConvertTo-SPSInventoryHtml -InputObject $script:Records @script:Common -FileName 'folder/report.html' -SplitThreshold $threshold)

            $pages | Should -HaveCount 1 -Because "threshold $threshold"
            $pages[0].Name | Should -Be 'report.html'
            $pages[0].Kind | Should -Be 'Entry'
            $pages[0].Html | Should -BeExactly $single -Because "threshold $threshold"
        }
    }

    It 'splits a farm with more site collections than the threshold, in an entry page and table pages named after it, worst category first' {
        $pages = Get-SplitPage

        @($pages | ForEach-Object { $_.Name }) | Should -Be @(
            'report.html'
            'report-sites-not-assessed-1.html'
            'report-sites-blocking-1.html'
            'report-sites-moderate-1.html'
            'report-sites-moderate-2.html'
            'report-sites-simple-1.html'
            'report-sites-simple-2.html'
            'report-sites-simple-3.html'
        )
        @($pages | ForEach-Object { $_.Kind }) | Should -Be @('Entry', 'Sites', 'Sites', 'Sites', 'Sites', 'Sites', 'Sites', 'Sites')
    }

    It 'splits above the threshold only: the 184 site collections of the sample, not the web application row, are counted' {
        (Get-SplitPage -SplitThreshold 183) | Should -Not -HaveCount 1
        (Get-SplitPage -SplitThreshold 184) | Should -HaveCount 1
    }

    It 'keeps what is not the table in the entry page, and no table, row or script' {
        $entry = (Get-SplitPage)[0].Html

        foreach ($id in @('summary', 'risk-indicators', 'alerts', 'wave-plan', 'inventory-table')) {
            $entry | Should -Match ('id="{0}"' -f $id) -Because $id
        }
        $entry | Should -Match '<strong>184</strong> site collection\(s\)'
        $entry | Should -Not -Match '<table id="inv">'
        $entry | Should -Not -Match 'class="site"'
        $entry | Should -Not -Match '<script'
        $entry | Should -Match 'the table is split in <strong>7</strong> pages'
    }

    It 'puts every site collection on one table page, in the order of the single report: nothing is lost' {
        $single = ConvertTo-SPSInventoryHtml -InputObject $script:Records @script:Common
        $pages = Get-SplitPage

        $singleRows = @(Get-Row -Html $single)
        $splitRows = @($pages | Where-Object { $_.Kind -eq 'Sites' } | ForEach-Object { Get-Row -Html $_.Html })

        $singleRows | Should -HaveCount 185
        $splitRows | Should -HaveCount 185
        for ($index = 0; $index -lt $singleRows.Count; $index++) {
            $splitRows[$index] | Should -BeExactly $singleRows[$index] -Because "row $index"
        }
    }

    It 'holds at most RowsPerPage site collections on a page, and a category on consecutive pages' {
        $counts = @{}
        foreach ($page in (Get-SplitPage | Where-Object { $_.Kind -eq 'Sites' })) {
            $counts[$page.Name] = @(Get-Row -Html $page.Html).Count
        }

        $counts['report-sites-not-assessed-1.html'] | Should -Be 2
        $counts['report-sites-blocking-1.html'] | Should -Be 3
        $counts['report-sites-moderate-1.html'] | Should -Be 50
        $counts['report-sites-moderate-2.html'] | Should -Be 10
        $counts['report-sites-simple-1.html'] | Should -Be 50
        $counts['report-sites-simple-2.html'] | Should -Be 50
        $counts['report-sites-simple-3.html'] | Should -Be 20
        # A table page holds the rows of one category only.
        $page = (Get-SplitPage | Where-Object { $_.Name -eq 'report-sites-moderate-2.html' }).Html
        @([regex]::Matches($page, 'data-category="(\d)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique) | Should -Be @('2')
    }

    It 'makes a risk indicator a link to the first table page that has a site collection that raises it, with the filter in the address' {
        $entry = (Get-SplitPage)[0].Html

        $entry | Should -Match 'class="risk sev-medium" data-ind="large-lists" href="report-sites-simple-1\.html#ind=large-lists"'
        $entry | Should -Match 'data-ind="custom-master-page" href="report-sites-moderate-2\.html#ind=custom-master-page"'
        $entry | Should -Match 'data-ind="full-trust" href="report-sites-blocking-1\.html#ind=full-trust"'
        $entry | Should -Not -Match '@@IND-PAGE'
        $entry | Should -Not -Match '<button type="button" class="risk'
        $entry | Should -Match 'Click an indicator to open the first page of the inventory table'
    }

    It 'lists the pages of each category in the entry page' {
        $entry = (Get-SplitPage)[0].Html

        $entry | Should -Match '<tr><td>1\. Simple</td><td class="num">120</td><td><a href="report-sites-simple-1\.html">1</a> <a href="report-sites-simple-2\.html">2</a> <a href="report-sites-simple-3\.html">3</a></td></tr>'
        $entry | Should -Match '<tr><td>Not assessed</td><td class="num">2</td><td><a href="report-sites-not-assessed-1\.html">1</a></td></tr>'
    }

    It 'gives every page the same header, the way back to the entry page and the other categories, and no filter by category' {
        foreach ($page in (Get-SplitPage | Where-Object { $_.Kind -eq 'Sites' })) {
            $page.Html | Should -Match '<h1>SharePoint Site Inventory</h1>' -Because $page.Name
            $page.Html | Should -Match 'Environment <strong>PROD</strong>' -Because $page.Name
            $page.Html | Should -Match '<a href="report\.html">Summary</a>' -Because $page.Name
            $page.Html | Should -Match '<a href="report\.html#risk-indicators">Risk indicators</a>' -Because $page.Name
            $page.Html | Should -Match 'href="report-sites-blocking-1\.html" data-href="report-sites-blocking-1\.html" data-keep( class="current")?>4\. Blocking \(3\)</a>' -Because $page.Name
            $page.Html | Should -Match 'data-keep( class="current")?>1\. Simple \(120\)</a>' -Because $page.Name
            $page.Html | Should -Not -Match 'data-filter=' -Because $page.Name
            $page.Html | Should -Match '<input type="search" id="inv-search" placeholder="Search this page"' -Because $page.Name
        }
        $simple2 = (Get-SplitPage | Where-Object { $_.Name -eq 'report-sites-simple-2.html' }).Html
        $simple2 | Should -Match 'data-keep class="current">1\. Simple \(120\)</a>'
        $simple2 | Should -Match '<title>SharePoint Site Inventory - Site collections - 1\. Simple, page 2 of 3 - PROD</title>'
        $simple2 | Should -Match 'site collections 51 to 100 of 120'
    }

    It 'links the pages of a category with a pager that has the previous and the next page' {
        $simple2 = (Get-SplitPage | Where-Object { $_.Name -eq 'report-sites-simple-2.html' }).Html
        $simple1 = (Get-SplitPage | Where-Object { $_.Name -eq 'report-sites-simple-1.html' }).Html
        $blocking = (Get-SplitPage | Where-Object { $_.Name -eq 'report-sites-blocking-1.html' }).Html

        $simple2 | Should -Match '&larr; Previous'
        $simple2 | Should -Match 'Next &rarr;'
        $simple2 | Should -Match '<strong>2</strong>'
        $simple1 | Should -Not -Match '&larr; Previous'
        $simple1 | Should -Match 'Next &rarr;'
        # A category with one page has no pager.
        $blocking | Should -Not -Match 'class="pager"'
    }

    It 'uses relative links to the files of the report only, so that the folder can be moved' {
        $pages = Get-SplitPage
        $names = @($pages | ForEach-Object { $_.Name })

        foreach ($page in $pages) {
            foreach ($link in (Get-Link -Html $page.Html)) {
                $file = ($link -split '#')[0]
                $ok = $link.StartsWith('#') -or ($names -contains $file) -or $link.StartsWith('https://learn.microsoft.com/')
                $ok | Should -BeTrue -Because "$($page.Name) links to '$link'"
            }
            $page.Html | Should -Not -Match '<link ' -Because $page.Name
            $page.Html | Should -Not -Match '<script src' -Because $page.Name
        }
    }

    It 'gives a table page the data to follow the indicator of its address, and the pages that hold each indicator' {
        $pages = Get-SplitPage
        $simple3 = ($pages | Where-Object { $_.Name -eq 'report-sites-simple-3.html' }).Html

        $data = Get-PageData -Html $simple3
        $data.entry | Should -Be 'report.html'
        $names = @($pages | Where-Object { $_.Kind -eq 'Sites' } | ForEach-Object { $_.Name })
        @($data.pages) | Should -Be $names
        $data.current | Should -Be 6
        $names[$data.current] | Should -Be 'report-sites-simple-3.html'
        @($data.indicatorPages.'large-lists') | Should -Be @(4, 6)
        @($data.indicatorPages.'custom-master-page') | Should -Be @(3)
        $data.labels.'large-lists' | Should -Be 'Sites with large lists'
        # Every indicator has a label and its pages are valid indexes.
        foreach ($property in $data.indicatorPages.PSObject.Properties) {
            $data.labels.PSObject.Properties.Name | Should -Contain $property.Name
            foreach ($index in @($property.Value)) { $index | Should -BeLessThan $names.Count }
        }
        $simple3 | Should -Match "hashchange"
        $simple3 | Should -Match "history\.replaceState"
    }

    It 'applies the same sort, search and detail script on a table page, and has none in the entry page' {
        $simple1 = (Get-SplitPage | Where-Object { $_.Name -eq 'report-sites-simple-1.html' }).Html

        $simple1 | Should -Match "document\.getElementById\('inv'\)"
        $simple1 | Should -Match 'class="toggle"'
        $simple1 | Should -Match '<span class="count" id="inv-count">50 of 50 shown</span>'
        (Get-SplitPage)[0].Html | Should -Not -Match 'applyFilters'
    }

    It 'names the pages after the file name without its extension and its folder, and encodes the name in the links' {
        $pages = Get-SplitPage -FileName 'some folder/My Report #1.html'

        $pages[0].Name | Should -Be 'My Report #1.html'
        $pages[1].Name | Should -Be 'My Report #1-sites-not-assessed-1.html'
        $pages[0].Html | Should -Match 'href="My%20Report%20%231-sites-simple-1\.html#ind=large-lists"'
        $pages[1].Html | Should -Match '<a href="My%20Report%20%231\.html">Summary</a>'
        (Get-PageData -Html $pages[1].Html).entry | Should -Be 'My%20Report%20%231.html'
    }

    It 'rejects a page size or a threshold out of range, and a split without a file name' {
        { ConvertTo-SPSInventoryHtml -InputObject $script:Records -FileName 'r.html' -RowsPerPage 49 } | Should -Throw
        { ConvertTo-SPSInventoryHtml -InputObject $script:Records -FileName 'r.html' -RowsPerPage 5001 } | Should -Throw
        { ConvertTo-SPSInventoryHtml -InputObject $script:Records -FileName 'r.html' -SplitThreshold -1 } | Should -Throw
        { ConvertTo-SPSInventoryHtml -InputObject $script:Records -SplitThreshold 10 } | Should -Throw
    }

    It 'renders an empty inventory as one entry page' {
        $pages = @(ConvertTo-SPSInventoryHtml -InputObject @() -FileName 'report.html' -SplitThreshold 1)

        $pages | Should -HaveCount 1
        $pages[0].Html | Should -Match 'There is no site collection in this inventory'
    }
}
