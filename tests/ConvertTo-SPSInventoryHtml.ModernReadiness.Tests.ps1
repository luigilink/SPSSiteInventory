# The HTML report of the SharePointOnPrem mode has a Modern experience readiness section: what keeps each site
# collection in the classic experience. The default mode does not have it. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function New-Site {
        param ([string]$Name, [int]$Category = 1, [string]$CategoryName = 'Modern-ready', [double]$Score = 0, [string]$Status = 'Complete', [hashtable]$Signals = @{}, [string]$Title = '')
        $record = [ordered]@{
            InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$Name"; Title = $(if ($Title) { $Title } else { $Name }); WebApp = 'Intranet'
            AssessmentStatus = $Status; Category = $Category; CategoryName = $CategoryName; Score = $Score
            Wave = $Category; WaveName = "Wave $Category"; SizeGB = 0.5; Template = 'STS#0'; Reasons = ''
        }
        foreach ($key in $Signals.Keys) { $record[$key] = $Signals[$key] }
        [PSCustomObject]$record
    }

    function Get-Html {
        param ([object[]]$Record, [string]$Mode = 'SharePointOnPrem', [hashtable]$Extra = @{})
        ConvertTo-SPSInventoryHtml -InputObject $Record -EnvName 'PROD' -GeneratedOn ([datetime]'2026-01-02T03:04:00') -TargetMode $Mode @Extra
    }

    function Get-Section {
        param ([string]$Html)
        $start = $Html.IndexOf('<h2 id="modern-readiness">')
        if ($start -lt 0) { return '' }
        $end = $Html.IndexOf('<h2 id="wave-plan">', $start)
        $Html.Substring($start, $end - $start)
    }

    $script:Sites = @(
        (New-Site -Name 'blocked' -Category 3 -CategoryName 'Rebuild (SPFx)' -Score 8 -Signals @{ CustomMasterPage = $true; XsltListViewCount = 3; ScriptWebPartCount = 1 })
        (New-Site -Name 'light' -Category 2 -CategoryName 'Light remediation' -Score 2 -Signals @{ AlternateCssUrlCount = 2 })
        (New-Site -Name 'ready' -Category 1)
    )
}

Describe 'The Modern experience readiness section of the HTML report' {
    It 'is in the report of the SharePointOnPrem mode, with a link in the navigation, between the alerts and the wave plan' {
        $html = Get-Html -Record $script:Sites -Extra @{ Alert = @() }

        $html | Should -Match '<h2 id="modern-readiness">Modern experience readiness</h2>'
        $html | Should -Match '<a href="#modern-readiness">Modern readiness</a>'
        $html.IndexOf('id="alerts"') | Should -BeLessThan $html.IndexOf('id="modern-readiness"')
        $html.IndexOf('id="modern-readiness"') | Should -BeLessThan $html.IndexOf('id="wave-plan"')
        $html.IndexOf('href="#alerts"') | Should -BeLessThan $html.IndexOf('href="#modern-readiness"')
    }

    It 'is not in the report of the default mode, with or without the mode' {
        $without = ConvertTo-SPSInventoryHtml -InputObject $script:Sites -EnvName 'PROD'
        $with = Get-Html -Record $script:Sites -Mode 'SharePointOnline'

        foreach ($html in @($without, $with)) {
            $html | Should -Not -Match 'modern-readiness'
            $html | Should -Not -Match 'Modern experience readiness'
            $html | Should -Not -Match 'Modern readiness'
        }
    }

    It 'says how many assessed site collections have a blocker, and explains what a blocker is and how it is counted' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Match '<strong>2</strong> of <strong>3</strong> assessed site collection\(s\) have at least one blocker of the modern experience'
        $section | Should -Match 'keeps a page or a list in the classic experience'
        $section | Should -Match 'counted once per kind'
    }

    It 'has a row for each kind of blocker, with the site collections that have it and the items behind it' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Match '<tr><td>Custom master page</td><td class="num">1</td><td class="num">-</td></tr>'
        $section | Should -Match '<tr><td>Alternate CSS URL</td><td class="num">1</td><td class="num">2 web\(s\)</td></tr>'
        $section | Should -Match '<tr><td>Publishing features</td><td class="num">0</td><td class="num">-</td></tr>'
        $section | Should -Match '<tr><td>XSLT list views</td><td class="num">1</td><td class="num">3 view\(s\)</td></tr>'
        $section | Should -Match '<tr><td>Script web parts</td><td class="num">1</td><td class="num">1 web part\(s\)</td></tr>'
        $section | Should -Match '<tr><td>Opted out of modern lists</td><td class="num">0</td><td class="num">-</td></tr>'
        $section | Should -Match '<tr><td>Lists forced to classic</td><td class="num">0</td><td class="num">-</td></tr>'
    }

    It 'lists the site collections that have a blocker, the most kinds first, with the category of the mode, and leaves out the others' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Match 'https://intranet/sites/blocked'
        $section | Should -Match '<td class="num">3</td><td>Custom master page; XSLT list views \(3\); Script web parts \(1\)</td><td><span class="badge b3">Rebuild \(SPFx\)</span></td>'
        $section | Should -Match '<td class="num">1</td><td>Alternate CSS URL \(2 webs\)</td><td><span class="badge b2">Light remediation</span></td>'
        $section | Should -Not -Match 'https://intranet/sites/ready'
        $section.IndexOf('sites/blocked') | Should -BeLessThan $section.IndexOf('sites/light')
    }

    It 'says in which order the site collections are listed, when none is left out' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Match '<p class="muted">The site collections that have a blocker, the most kinds first, then the highest score\.</p>'
        $section | Should -Not -Match 'are listed below, of'
    }

    It 'shows the title with the URL under it, and only the URL when there is no other title' {
        $section = Get-Section -Html (Get-Html -Record @((New-Site -Name 'hr' -Title 'Human resources' -Signals @{ ScriptWebPartCount = 1 }), (New-Site -Name 'plain' -Title 'https://intranet/sites/plain' -Signals @{ ScriptWebPartCount = 1 })))

        $section | Should -Match '<div class="site-title">Human resources</div><div class="site-url">https://intranet/sites/hr</div>'
        $section | Should -Match '<div class="site-title">https://intranet/sites/plain</div></td>'
    }

    It 'encodes what comes from the farm' {
        $record = New-Site -Name 'x' -Title '<script>alert(1)</script> & co' -Signals @{ ScriptWebPartCount = 1 }
        $record.Url = 'https://intranet/sites/x?a=1&b="2"'

        $section = Get-Section -Html (Get-Html -Record @($record))

        $section | Should -Not -Match '<script>alert'
        $section | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt; &amp; co'
        $section | Should -Match 'a=1&amp;b=&quot;2&quot;'
    }

    It 'marks a site collection whose assessment is partial, and says that its counts are lower bounds' {
        $section = Get-Section -Html (Get-Html -Record @((New-Site -Name 'partial' -Status 'Partial' -Signals @{ ScriptWebPartCount = 2 }), (New-Site -Name 'ok' -Signals @{ XsltListViewCount = 1 })))

        $section | Should -Match ([regex]::Escape('Script web parts (2) <span class="pill warn">Partial</span></td>'))
        $section | Should -Match 'lower bounds'
        ([regex]::Matches($section, 'pill warn')).Count | Should -Be 1
    }

    It 'says how many site collections were not counted because their assessment failed' {
        $failed = New-Site -Name 'failed' -Status 'Failed' -Category 0 -CategoryName 'Not assessed'
        $section = Get-Section -Html (Get-Html -Record @($failed, (New-Site -Name 'ok' -Signals @{ XsltListViewCount = 1 })))

        $section | Should -Match '<strong>1</strong> site collection\(s\) whose assessment failed are not counted'
        $section | Should -Match '<strong>1</strong> of <strong>1</strong> assessed'
    }

    It 'says so, with no table, when no assessed site collection has a blocker' {
        $section = Get-Section -Html (Get-Html -Record @((New-Site -Name 'a'), (New-Site -Name 'b')))

        $section | Should -Match 'No assessed site collection has a blocker of the modern experience \(2 assessed\)'
        $section | Should -Not -Match '<table'
    }

    It 'has no section for an empty inventory' {
        (Get-Html -Record @()) | Should -Not -Match 'modern-readiness'
    }

    It 'lists at most 100 site collections and says how many have a blocker' {
        $records = 1..120 | ForEach-Object { New-Site -Name ('s{0:000}' -f $_) -Signals @{ ScriptWebPartCount = 1 } }

        $section = Get-Section -Html (Get-Html -Record $records)

        ([regex]::Matches($section, '<div class="site-url">')).Count | Should -Be 100
        $section | Should -Match 'The <strong>100</strong> site collections with the most kinds of blocker are listed below, of <strong>120</strong>'
        $section | Should -Not -Match 'then the highest score\.</p>'
    }

    It 'is in the entry page of a split report, and the table pages link to it' {
        $records = @(1..30 | ForEach-Object { New-Site -Name ('s{0:00}' -f $_) -Signals @{ ScriptWebPartCount = 1 } })

        $pages = @(ConvertTo-SPSInventoryHtml -InputObject $records -EnvName 'PROD' -TargetMode 'SharePointOnPrem' -FileName 'report.html' -SplitThreshold 10 -RowsPerPage 50)

        $pages.Count | Should -BeGreaterThan 1
        $pages[0].Html | Should -Match '<h2 id="modern-readiness">'
        foreach ($page in $pages | Select-Object -Skip 1) {
            $page.Html | Should -Not -Match '<h2 id="modern-readiness">'
            $page.Html | Should -Match '<a href="report.html#modern-readiness">Modern readiness</a>'
        }
    }

    It 'does not add the section to a split report of the default mode' {
        $records = @(1..30 | ForEach-Object { New-Site -Name ('s{0:00}' -f $_) -Signals @{ ScriptWebPartCount = 1 } })

        $pages = @(ConvertTo-SPSInventoryHtml -InputObject $records -EnvName 'PROD' -FileName 'report.html' -SplitThreshold 10 -RowsPerPage 50)

        foreach ($page in $pages) { $page.Html | Should -Not -Match 'modern-readiness' }
    }
}

Describe 'The risk indicators and the alerts of the HTML report, for the modern experience' {
    It 'has a risk indicator for each signal of the modern experience, in both modes, with the severity of its alert' {
        $records = @(
            (New-Site -Name 'a' -Signals @{ AlternateCssUrlCount = 1; XsltListViewCount = 1; ScriptWebPartCount = 1; ClassicExperienceOptOutCount = 1; ClassicExperienceListCount = 1 })
            (New-Site -Name 'b')
        )

        foreach ($mode in 'SharePointOnline', 'SharePointOnPrem') {
            $html = Get-Html -Record $records -Mode $mode
            foreach ($key in 'alternate-css', 'xslt-views', 'script-web-parts', 'modern-opt-out', 'classic-lists') {
                $html | Should -Match ('data-ind="{0}"' -f $key) -Because "$mode, indicator $key"
            }
        }
        $online = Get-Html -Record $records -Mode 'SharePointOnline'
        $onPrem = Get-Html -Record $records -Mode 'SharePointOnPrem'
        $online | Should -Match 'class="risk sev-medium" data-ind="script-web-parts"'
        $online | Should -Match 'class="risk sev-low" data-ind="modern-opt-out"'
        $onPrem | Should -Match 'class="risk sev-medium" data-ind="modern-opt-out"'
        $onPrem | Should -Match 'class="risk sev-low" data-ind="classic-lists"'
    }

    It 'names the indicators that no site collection raises' {
        $html = Get-Html -Record @((New-Site -Name 'a'))

        $html | Should -Match 'No site collection has: .*an alternate CSS URL.*XSLT list views.*script web parts.*an opt-out of modern lists.*lists forced to classic'
    }

    It 'ranks the signals of a migration lower in the on-premises report, as the catalog of the mode does' {
        $records = @((New-Site -Name 'a' -Signals @{ ExternalListCount = 1; UsesCustomFarmFeature = $true; UsesFullTrustCode = $true; InfoPathFormCount = 1 }))

        $online = Get-Html -Record $records -Mode 'SharePointOnline'
        $onPrem = Get-Html -Record $records -Mode 'SharePointOnPrem'

        $online | Should -Match 'class="risk sev-high" data-ind="external-lists"'
        $online | Should -Match 'class="risk sev-high" data-ind="custom-farm-feature"'
        $online | Should -Match 'class="risk sev-high" data-ind="full-trust"'
        $onPrem | Should -Match 'class="risk sev-low" data-ind="external-lists"'
        $onPrem | Should -Match 'class="risk sev-medium" data-ind="custom-farm-feature"'
        $onPrem | Should -Match 'class="risk sev-medium" data-ind="full-trust"'
        $onPrem | Should -Match 'class="risk sev-high" data-ind="infopath"'
    }

    It 'words the alert of each type with the catalog of the mode of the report' {
        $records = @((New-Site -Name 'a' -Signals @{ ExternalListCount = 1 }))
        $online = Get-Html -Record $records -Mode 'SharePointOnline' -Extra @{ Alert = @(& $script:Module { param ($R) Get-SPSInventoryAlert -InputObject $R -TargetMode 'SharePointOnline' } $records) }
        $onPrem = Get-Html -Record $records -Mode 'SharePointOnPrem' -Extra @{ Alert = @(& $script:Module { param ($R) Get-SPSInventoryAlert -InputObject $R -TargetMode 'SharePointOnPrem' } $records) }

        $online | Should -Match '<span class="pill yes">High</span><span class="alert-name">ExternalLists</span>'
        $online | Should -Match 'External lists depend on BCS'
        $online | Should -Not -Match 'Migration to SharePoint Online only'
        $onPrem | Should -Match '<span class="pill no">Low</span><span class="alert-name">ExternalLists</span>'
        $onPrem | Should -Match 'Migration to SharePoint Online only\. External lists depend on BCS'
        $onPrem | Should -Match 'Nothing to do to modernize this farm'
    }
}
