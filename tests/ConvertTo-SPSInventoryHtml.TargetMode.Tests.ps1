# The HTML report and the report pack name the categories, the waves and the pages of a split report after the target
# mode. The default mode keeps its names, so that a report does not change for whoever does not choose the other one.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-Site {
        param ([string]$Name, [int]$Category, [string]$CategoryName, [string]$WaveName = 'Wave')
        [PSCustomObject]@{
            InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$Name"; Title = $Name; WebApp = 'Intranet'
            AssessmentStatus = 'Complete'; Category = $Category; CategoryName = $CategoryName; Score = 0
            Wave = $Category; WaveName = $WaveName; SizeGB = 0.5; Template = 'STS#0'; Reasons = ''
        }
    }

    $script:Names = @{
        SharePointOnline = @('Simple', 'Moderate', 'Complex', 'Blocking')
        SharePointOnPrem = @('Modern-ready', 'Light remediation', 'Rebuild (SPFx)', 'Blocked')
    }
    $script:Slugs = @{
        SharePointOnline = @('simple', 'moderate', 'complex', 'blocking')
        SharePointOnPrem = @('modern-ready', 'light-remediation', 'rebuild-spfx', 'blocked')
    }
    # The last site has InfoPath forms, a signal of High severity in both modes: the group of the high-severity signals is only drawn then.
    function Get-Sites {
        param ([string]$Mode)
        foreach ($category in 1..4) {
            $site = New-Site -Name ('s{0}' -f $category) -Category $category -CategoryName $script:Names[$Mode][$category - 1] -WaveName ('Wave {0}' -f $category)
            $site | Add-Member -NotePropertyName InfoPathFormCount -NotePropertyValue $(if ($category -eq 4) { 1 } else { 0 })
            $site
        }
    }
}

Describe 'ConvertTo-SPSInventoryHtml and the target mode' {
    It 'words the report of the default mode as a migration report, with or without the mode' {
        $without = ConvertTo-SPSInventoryHtml -InputObject @(Get-Sites -Mode 'SharePointOnline') -EnvName 'PROD' -GeneratedOn ([datetime]'2026-01-02T03:04:00')
        $with = ConvertTo-SPSInventoryHtml -InputObject @(Get-Sites -Mode 'SharePointOnline') -EnvName 'PROD' -GeneratedOn ([datetime]'2026-01-02T03:04:00') -TargetMode 'SharePointOnline'

        $with | Should -BeExactly $without
        $without | Should -Match 'class="lbl">1\. Simple<'
        $without | Should -Match 'class="lbl">4\. Blocking<'
        $without | Should -Match 'Migration wave plan'
        $without | Should -Match '>Migration waves<'
        $without | Should -Match 'block or break a migration'
        $without | Should -Not -Match 'Target <strong>'
        $without | Should -Not -Match 'odernization'
    }

    It 'names the four categories, the filters and the wave plan after the modernization with SharePointOnPrem' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @(Get-Sites -Mode 'SharePointOnPrem') -EnvName 'PROD' -TargetMode 'SharePointOnPrem'

        foreach ($category in 1..4) {
            $name = $script:Names.SharePointOnPrem[$category - 1]
            $html | Should -Match ([regex]::Escape(('class="lbl">{0}. {1}<' -f $category, $name)))
            $html | Should -Match ([regex]::Escape(('<button data-filter="{0}">{0}. {1}</button>' -f $category, $name)))
        }
        $html | Should -Match 'Modernization wave plan'
        $html | Should -Match '<a href="#wave-plan">Modernization waves</a>'
        $html | Should -Match 'block or break the modern experience'
        $html | Should -Not -Match 'Migration wave plan'
        $html | Should -Not -Match '>Migration waves<'
        $html | Should -Not -Match 'block or break a migration'
    }

    It 'leaves none of the migration category names in the report of the on-premises mode' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @(Get-Sites -Mode 'SharePointOnPrem') -TargetMode 'SharePointOnPrem'

        $html | Should -Not -Match 'class="lbl">[0-9]\. (Simple|Moderate|Complex|Blocking)<'
        $html | Should -Not -Match 'data-filter="[0-9]">[0-9]\. (Simple|Moderate|Complex|Blocking)<'
    }

    It 'says in the header what the report is for, only when it is not the default mode, and encodes it' {
        $onPrem = ConvertTo-SPSInventoryHtml -InputObject @(Get-Sites -Mode 'SharePointOnPrem') -EnvName 'PROD' -TargetMode 'SharePointOnPrem' -GeneratedOn ([datetime]'2026-01-02T03:04:00')
        $online = ConvertTo-SPSInventoryHtml -InputObject @(Get-Sites -Mode 'SharePointOnline') -EnvName 'PROD' -GeneratedOn ([datetime]'2026-01-02T03:04:00')

        $onPrem | Should -Match ([regex]::Escape('<div class="meta">Environment <strong>PROD</strong> &middot; Target <strong>SharePoint on-premises modernization</strong> &middot; Generated on <strong>2026-01-02 03:04</strong></div>'))
        $online | Should -Match ([regex]::Escape('<div class="meta">Environment <strong>PROD</strong> &middot; Generated on <strong>2026-01-02 03:04</strong></div>'))
    }

    It 'names the pages of a split report after the category of the mode, in ASCII, and links them' -ForEach @(
        @{ Mode = 'SharePointOnline' }
        @{ Mode = 'SharePointOnPrem' }
    ) {
        $pages = @(ConvertTo-SPSInventoryHtml -InputObject @(Get-Sites -Mode $Mode) -FileName 'rep.html' -SplitThreshold 2 -RowsPerPage 50 -TargetMode $Mode)

        @($pages | ForEach-Object { $_.Name } | Where-Object { $_ -ne 'rep.html' } | Sort-Object) |
            Should -Be @($script:Slugs[$Mode] | ForEach-Object { 'rep-sites-{0}-1.html' -f $_ } | Sort-Object)
        foreach ($page in $pages) {
            $page.Name | Should -Match '^[a-z0-9.-]+$'
        }
        $entry = $pages | Where-Object { $_.Kind -eq 'Entry' }
        foreach ($slug in $script:Slugs[$Mode]) {
            $entry.Html | Should -Match ([regex]::Escape(('href="rep-sites-{0}-1.html' -f $slug)))
        }
    }

    It 'words the navigation of the table pages like the entry page' {
        $pages = @(ConvertTo-SPSInventoryHtml -InputObject @(Get-Sites -Mode 'SharePointOnPrem') -FileName 'rep.html' -SplitThreshold 2 -RowsPerPage 50 -TargetMode 'SharePointOnPrem')

        foreach ($page in @($pages | Where-Object { $_.Kind -ne 'Entry' })) {
            $page.Html | Should -Match '>Modernization waves<'
            $page.Html | Should -Not -Match '>Migration waves<'
        }
    }

    It 'names the sites that wait in Needs review after the first category of the mode' {
        $partial = New-Site -Name 'p' -Category 1 -CategoryName 'Modern-ready' -WaveName 'Needs review'
        $partial.AssessmentStatus = 'Partial'
        $partial.Wave = 0

        $html = ConvertTo-SPSInventoryHtml -InputObject @($partial) -TargetMode 'SharePointOnPrem'

        $html | Should -Match '<strong>1</strong> Modern-ready site collection\(s\) with a partial assessment wait in the <strong>Needs review</strong> wave'
    }

    It 'refuses a mode that is not one of the two' {
        { ConvertTo-SPSInventoryHtml -InputObject @(Get-Sites -Mode 'SharePointOnline') -TargetMode 'OnPrem' } |
            Should -Throw "TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'."
    }
}

Describe 'Export-SPSInventoryReport and the target mode' {
    It 'records the default mode in the manifest, without a mode as with SharePointOnline' {
        $folder = Join-Path $TestDrive 'default'

        $output = Export-SPSInventoryReport -InputObject @(Get-Sites -Mode 'SharePointOnline') -OutputFolder $folder -BaseName 'Default'
        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json

        $manifest.Summary.TargetMode | Should -Be 'SharePointOnline'
        (Get-Content -Path $output.HtmlPath -Raw) | Should -Match 'class="lbl">1\. Simple<'
    }

    It 'records the mode in the manifest and words the HTML report with it' {
        $folder = Join-Path $TestDrive 'onprem'

        $output = Export-SPSInventoryReport -InputObject @(Get-Sites -Mode 'SharePointOnPrem') -OutputFolder $folder -BaseName 'OnPrem' -TargetMode 'sharepointonprem'
        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json

        $manifest.Summary.TargetMode | Should -BeExactly 'SharePointOnPrem'
        (Get-Content -Path $output.HtmlPath -Raw) | Should -Match 'class="lbl">3\. Rebuild \(SPFx\)<'
    }

    It 'names the pages of a split report after the mode and lists them in the manifest' {
        $folder = Join-Path $TestDrive 'onprem-split'

        $output = Export-SPSInventoryReport -InputObject @(Get-Sites -Mode 'SharePointOnPrem') -OutputFolder $folder -BaseName 'Many' -HtmlSplitThreshold 2 -HtmlRowsPerPage 50 -TargetMode 'SharePointOnPrem'
        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json

        $base = [System.IO.Path]::GetFileNameWithoutExtension((Split-Path -Path $output.HtmlPath -Leaf))
        @($output.HtmlPagePaths | ForEach-Object { Split-Path -Path $_ -Leaf } | Sort-Object) |
            Should -Be @($script:Slugs.SharePointOnPrem | ForEach-Object { '{0}-sites-{1}-1.html' -f $base, $_ } | Sort-Object)
        @($manifest.Files.InventoryHtmlPages).Count | Should -Be 4
    }

    It 'writes the CSV and the JSON of the inventory with the names that the records carry, whatever the mode' {
        $folder = Join-Path $TestDrive 'records'

        $output = Export-SPSInventoryReport -InputObject @(Get-Sites -Mode 'SharePointOnPrem') -OutputFolder $folder -BaseName 'Records' -TargetMode 'SharePointOnPrem'
        $rows = @(Import-Csv -Path $output.CsvPath)

        @($rows | ForEach-Object { $_.CategoryName }) | Should -Be $script:Names.SharePointOnPrem
        @($rows | ForEach-Object { $_.Category }) | Should -Be @('1', '2', '3', '4')
    }

    It 'writes the alerts of the catalog of the mode, the same types in both, and the readiness section in the report of the on-premises mode only' {
        $records = @(
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/a'; Title = 'A'; WebApp = 'Intranet'; WebAppUrl = 'https://intranet'
                AssessmentStatus = 'Complete'; Category = 3; CategoryName = 'x'; Score = 4; Wave = 3; WaveName = 'w'; SizeGB = 1; Template = 'STS#0'; Reasons = ''
                ExternalListCount = 2; InfoPathFormCount = 1; ScriptWebPartCount = 3
            }
        )

        $online = Export-SPSInventoryReport -InputObject $records -OutputFolder (Join-Path $TestDrive 'alerts-online') -BaseName 'Online'
        $onPrem = Export-SPSInventoryReport -InputObject $records -OutputFolder (Join-Path $TestDrive 'alerts-onprem') -BaseName 'OnPrem' -TargetMode 'SharePointOnPrem'

        # No @() around ConvertFrom-Json: Windows PowerShell 5.1 emits a JSON array as one object, which @() would nest.
        $onlineAlerts = Get-Content -Path $online.AlertsJsonPath -Raw | ConvertFrom-Json
        $onPremAlerts = Get-Content -Path $onPrem.AlertsJsonPath -Raw | ConvertFrom-Json
        (@($onPremAlerts.AlertType) -join ',') | Should -Be (@($onlineAlerts.AlertType) -join ',')
        ($onlineAlerts | Where-Object AlertType -eq 'ExternalLists').Severity | Should -Be 'High'
        ($onPremAlerts | Where-Object AlertType -eq 'ExternalLists').Severity | Should -Be 'Low'
        ($onPremAlerts | Where-Object AlertType -eq 'ExternalLists').Message | Should -Match '^Migration to SharePoint Online only\. '
        ($onPremAlerts | Where-Object AlertType -eq 'InfoPath').Severity | Should -Be 'High'
        (Get-Content -Path $online.HtmlPath -Raw) | Should -Not -Match 'modern-readiness'
        (Get-Content -Path $onPrem.HtmlPath -Raw) | Should -Match '<h2 id="modern-readiness">Modern experience readiness</h2>'
        $importedAlerts = @(Import-Csv -Path $onPrem.AlertsCsvPath)
        ($importedAlerts | Where-Object AlertType -eq 'ExternalLists').Severity | Should -Be 'Low'
    }

    It 'refuses a mode that is not one of the two before it writes a file' {
        $folder = Join-Path $TestDrive 'refused'

        { Export-SPSInventoryReport -InputObject @(Get-Sites -Mode 'SharePointOnline') -OutputFolder $folder -BaseName 'Refused' -TargetMode 'OnPrem' } |
            Should -Throw "TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'."

        Test-Path -Path $folder | Should -BeFalse
    }
}
