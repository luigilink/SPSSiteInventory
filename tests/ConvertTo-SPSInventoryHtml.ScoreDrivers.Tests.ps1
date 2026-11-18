# The HTML report has a Score drivers section: which signals make the score, by category and by signal. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-Site {
        param ([string]$Name, [string]$Reasons = '', [double]$Score = 0, [int]$Category = 3, [string]$CategoryName = 'Complex', [string]$Status = 'Complete')
        [PSCustomObject]@{
            InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$Name"; Title = $Name; WebApp = 'Intranet'
            AssessmentStatus = $Status; Category = $Category; CategoryName = $CategoryName; Score = $Score
            Wave = $Category; WaveName = "Wave $Category"; SizeGB = 0.5; Template = 'STS#0'; Reasons = $Reasons
        }
    }

    function Get-Html {
        param ([object[]]$Record, [string]$Mode = 'SharePointOnline')
        ConvertTo-SPSInventoryHtml -InputObject $Record -EnvName 'PROD' -GeneratedOn ([datetime]'2026-01-02T03:04:00') -TargetMode $Mode
    }

    function Get-Section {
        param ([string]$Html)
        $start = $Html.IndexOf('<h2 id="score-drivers">')
        if ($start -lt 0) { return '' }
        $end = $Html.IndexOf('<h2 id="inventory-table">', $start)
        $Html.Substring($start, $end - $start)
    }

    # A farm where one signal weighs most: the receivers are 105 of the 128.5 points that the signals add (82%).
    $script:Sites = @(
        (New-Site -Name 'simple' -Category 1 -CategoryName 'Simple' -Score 0.5 -Reasons 'CustomPermissionLevelCount=5 (+0.5)')
        (New-Site -Name 'complex-a' -Score 100 -Reasons 'EventReceivers=60 (+90); Workflow2010Count=2 (+6); ScriptWebPartCount=2 (+3); CustomMasterPage=1 (+1)')
        (New-Site -Name 'complex-b' -Score 20 -Reasons 'EventReceivers=10 (+15); Workflow2010Count=1 (+3); ScriptWebPartCount=1 (+2)')
        (New-Site -Name 'blocked' -Category 4 -CategoryName 'Blocking' -Score 8 -Reasons 'HasFbaZone=1 (+8); blocking: HasFbaZone; blocking: InfoPathFormCount')
    )
}

Describe 'The Score drivers section of the HTML report' {
    It 'is in the report of both modes, with a link in the navigation, between the wave plan and the inventory table' -ForEach @(
        @{ Mode = 'SharePointOnline' }
        @{ Mode = 'SharePointOnPrem' }
    ) {
        $html = Get-Html -Record $script:Sites -Mode $Mode

        $html | Should -Match '<h2 id="score-drivers">Score drivers</h2>'
        $html | Should -Match '<a href="#score-drivers">Score drivers</a>'
        $html.IndexOf('<h2 id="wave-plan">') | Should -BeLessThan $html.IndexOf('<h2 id="score-drivers">')
        $html.IndexOf('<h2 id="score-drivers">') | Should -BeLessThan $html.IndexOf('<h2 id="inventory-table">')
        $html.IndexOf('href="#wave-plan"') | Should -BeLessThan $html.IndexOf('href="#score-drivers"')
        $html.IndexOf('href="#score-drivers"') | Should -BeLessThan $html.IndexOf('href="#inventory-table"')
    }

    It 'is not in the report when no site collection has a weighted signal, or when none was assessed' {
        $failed = [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/f'; AssessmentStatus = 'Failed'; Category = $null; CategoryName = 'Not assessed'; Score = $null; Reasons = 'Assessment failed: x=1 (+5)' }
        $case = [ordered]@{
            'no reasons'               = @((New-Site -Name 'a' -Category 1 -CategoryName 'Simple'), (New-Site -Name 'b' -Category 1 -CategoryName 'Simple'))
            'only a failed assessment' = @($failed)
        }

        foreach ($name in $case.Keys) {
            $html = Get-Html -Record $case[$name]

            $html | Should -Not -Match 'score-drivers' -Because $name
            $html | Should -Not -Match 'Score drivers' -Because $name
        }
    }

    It 'tells which signal holds most of the score, and in how many site collections it weighs most' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Match '<div class="note warn"><strong>EventReceivers</strong> holds <strong>82%</strong> of the score of the inventory and weighs most in <strong>2</strong> of the <strong>4</strong> site collection\(s\) that have a score\. If this is not what you expect, review its weight, or cap what it can add with <code>Caps</code>, in the Scoring section of the settings\.</div>'
    }

    It 'says nothing of the kind when no signal holds half of the score' {
        $records = @(
            (New-Site -Name 'a' -Score 10 -Reasons 'A=1 (+4); B=1 (+3); C=1 (+3)')
            (New-Site -Name 'b' -Score 10 -Reasons 'A=1 (+4); B=1 (+3); C=1 (+3)')
        )

        $section = Get-Section -Html (Get-Html -Record $records)

        $section | Should -Match '<h2 id="score-drivers">'
        $section | Should -Not -Match 'holds <strong>'
        $section | Should -Not -Match 'class="note warn"'
    }

    It 'gives each category with its site collections, its score, the signals that weigh most and its blocking signals' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Match '<th>Category</th><th class="num">Site collections</th><th class="num">Score</th><th>Signals that weigh most</th><th>Blocked by</th>'
        $section | Should -Match '<tr><td><span class="badge b1">Simple</span></td><td class="num">1</td><td class="num">0\.5</td><td>CustomPermissionLevelCount 100%</td><td>-</td></tr>'
        $section | Should -Match '<tr><td><span class="badge b3">Complex</span></td><td class="num">2</td><td class="num">20 to 100</td><td>EventReceivers 88%, Workflow2010Count 8%, ScriptWebPartCount 4%</td><td>-</td></tr>'
        $section | Should -Match '<tr><td><span class="badge b4">Blocking</span></td><td class="num">1</td><td class="num">8</td><td>HasFbaZone 100%</td><td>HasFbaZone \(1\), InfoPathFormCount \(1\)</td></tr>'
    }

    It 'gives each signal with its site collections, its share of the score and the site collections where it weighs most, the largest first' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Match '<th>Signal</th><th class="num">Site collections</th><th class="num">Share of the score</th><th class="num">Weighs most in</th>'
        $section | Should -Match '<tr><td>EventReceivers</td><td class="num">2</td><td class="num">82%</td><td class="num">2</td></tr>'
        $section | Should -Match '<tr><td>Workflow2010Count</td><td class="num">2</td><td class="num">7%</td><td class="num">0</td></tr>'
        $section.IndexOf('<td>EventReceivers</td>') | Should -BeLessThan $section.IndexOf('<td>Workflow2010Count</td>')
        $section.IndexOf('<td>Workflow2010Count</td>') | Should -BeLessThan $section.IndexOf('<td>ScriptWebPartCount</td>')
    }

    It 'rounds a share to the nearest percent, half away from zero, and a share just under 1% to 1%' {
        # 12.5% and 87.5%: half-even rounding would give 12% for the first. And 1 of 128 is 0.78%.
        $half = Get-Section -Html (Get-Html -Record @((New-Site -Name 'a' -Score 8 -Reasons 'Big=1 (+7); Small=1 (+1)')))
        $near = Get-Section -Html (Get-Html -Record @((New-Site -Name 'a' -Score 128 -Reasons 'Main=1 (+127); Near=1 (+1)')))

        $half | Should -Match '<tr><td>Small</td><td class="num">1</td><td class="num">13%</td><td class="num">0</td></tr>'
        $half | Should -Match '<tr><td>Big</td><td class="num">1</td><td class="num">88%</td><td class="num">1</td></tr>'
        $near | Should -Match '<tr><td>Near</td><td class="num">1</td><td class="num">1%</td><td class="num">0</td></tr>'
    }

    It 'leaves a signal that is under 1% of a category out of its row, and writes a share under 1% as <1%' {
        $records = @(
            (New-Site -Name 'a' -Score 1000.2 -Reasons 'Big=1 (+1000); Tiny=1 (+0.2)')
        )

        $section = Get-Section -Html (Get-Html -Record $records)

        $section | Should -Match '<td>Big 100%</td>'
        $section | Should -Not -Match '<td>Big 100%, Tiny'
        $section | Should -Match '<tr><td>Tiny</td><td class="num">1</td><td class="num">&lt;1%</td><td class="num">0</td></tr>'
    }

    It 'lists at most 10 signals and says how many there are' {
        $reasons = (1..12 | ForEach-Object { 'Signal{0:00}=1 (+{1})' -f $_, (13 - $_) }) -join '; '
        $section = Get-Section -Html (Get-Html -Record @((New-Site -Name 'a' -Score 78 -Reasons $reasons)))

        $section | Should -Match 'The <strong>10</strong> signals that added the most to the score are listed, of <strong>12</strong>\.'
        $section | Should -Match '<td>Signal10</td>'
        $section | Should -Not -Match '<td>Signal11</td>'
        $section | Should -Not -Match '<td>Signal12</td>'
    }

    It 'says that it lists every signal when there are 10 or fewer' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Match 'What each signal added to the score, the one that added the most first\.'
        $section | Should -Not -Match 'signals that added the most to the score are listed'
    }

    It 'encodes the names of the signals, of a category that the report does not know and of the blocking signals' {
        $records = @(
            (New-Site -Name 'a' -Category 9 -Score 5 -CategoryName 'C<b>at' -Reasons 'X<script>alert(1)</script>=1 (+5)')
            (New-Site -Name 'b' -Category 4 -CategoryName 'Blocking' -Score 5 -Reasons 'Y=1 (+5); blocking: B<i>x')
        )

        $section = Get-Section -Html (Get-Html -Record $records)

        $section | Should -Not -Match '<script>alert\(1\)'
        $section | Should -Match 'X&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $section | Should -Match 'C&lt;b&gt;at'
        $section | Should -Match 'B&lt;i&gt;x \(1\)'
        $section | Should -Not -Match 'B<i>x'
    }

    It 'is on the entry page of a split report, with its link, and the pages of the table link to it' {
        $records = @($script:Sites) + @(1..120 | ForEach-Object { New-Site -Name ('s{0:000}' -f $_) -Category 1 -CategoryName 'Simple' -Score 0.5 -Reasons 'CustomPermissionLevelCount=5 (+0.5)' })

        $pages = @(ConvertTo-SPSInventoryHtml -InputObject $records -EnvName 'PROD' -GeneratedOn ([datetime]'2026-01-02T03:04:00') -FileName 'report.html' -SplitThreshold 100 -RowsPerPage 50)

        $pages.Count | Should -BeGreaterThan 1
        $entry = @($pages | Where-Object { $_.Kind -eq 'Entry' })
        $entry | Should -HaveCount 1
        $entry[0].Html | Should -Match '<h2 id="score-drivers">Score drivers</h2>'
        $entry[0].Html | Should -Match '<a href="#score-drivers">Score drivers</a>'
        $tablePages = @($pages | Where-Object { $_.Kind -ne 'Entry' })
        $tablePages.Count | Should -BeGreaterThan 0
        foreach ($page in $tablePages) {
            $page.Html | Should -Match '(?s)report\.html#wave-plan.+?<a href="report\.html#score-drivers">Score drivers</a>.+?report\.html#inventory-table'
            $page.Html | Should -Not -Match '<h2 id="score-drivers">'
        }
    }

    It 'says what weighs most without claiming that it decides the categories' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Match 'holds <strong>82%</strong>'
        $section | Should -Not -Match 'decides'
    }

    It 'applies the 1% cut-off of a category to the share itself, not to the rounded percentage' {
        # 1 of 128 is 0.78%: it is shown as 1% in the signal table, but it is under the cut-off of the category row.
        $section = Get-Section -Html (Get-Html -Record @((New-Site -Name 'a' -Score 128 -Reasons 'Main=1 (+127); Near=1 (+1)')))

        $section | Should -Match '<td>Main 99%</td>'
        $section | Should -Not -Match '<td>Main 99%, Near'
        $section | Should -Match '<tr><td>Near</td><td class="num">1</td><td class="num">1%</td><td class="num">0</td></tr>'
    }

    It 'keeps a signal that is just above 1% of the category' {
        $section = Get-Section -Html (Get-Html -Record @((New-Site -Name 'a' -Score 100 -Reasons 'Main=1 (+99); Edge=1 (+1)')))

        $section | Should -Match '<td>Main 99%, Edge 1%</td>'
    }

    It 'names the category as the target mode does, whatever the name that the record holds' {
        $online = Get-Section -Html (Get-Html -Record $script:Sites -Mode 'SharePointOnline')
        $onPrem = Get-Section -Html (Get-Html -Record $script:Sites -Mode 'SharePointOnPrem')

        $online | Should -Match '<span class="badge b3">Complex</span>'
        $onPrem | Should -Match '<span class="badge b3">Rebuild \(SPFx\)</span>'
        $onPrem | Should -Not -Match '<span class="badge b3">Complex</span>'
    }

    It 'falls back to the name of the record for a category number that the report does not know' {
        $records = @((New-Site -Name 'odd' -Category 9 -CategoryName 'Custom' -Score 5 -Reasons 'Signal=1 (+5)'))

        $section = Get-Section -Html (Get-Html -Record $records)

        $section | Should -Match '<span class="badge b9">Custom</span>'
    }

    It 'says how many site collections have a score without a signal that can be read' {
        $records = @(
            (New-Site -Name 'tiny' -Category 1 -CategoryName 'Simple' -Score 0.01 -Reasons 'PageCount=4 (+0); SizeGB=0.2 (+0)')
            (New-Site -Name 'raising' -Score 5 -Reasons 'Signal=1 (+5)')
        )

        $section = Get-Section -Html (Get-Html -Record $records)

        $section | Should -Match '<p class="muted"><strong>1</strong> site collection\(s\) have a score without a signal that can be read'
        $section | Should -Not -Match '<tr><td>PageCount</td>'
    }

    It 'does not show the note about unreadable scores when every score can be explained' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Not -Match 'without a signal that can be read'
    }

    It 'explains the scores that no signal explains when no contribution can be read at all, with the table of the categories and without the table of the signals' {
        $records = @(
            (New-Site -Name 'a' -Category 1 -CategoryName 'Simple' -Score 0.01 -Reasons 'PublishingPageCount=4 (+0); SizeGB=0.2 (+0)')
            (New-Site -Name 'b' -Category 1 -CategoryName 'Simple' -Score 0.01 -Reasons 'PublishingPageCount=4 (+0)')
        )

        $html = Get-Html -Record $records
        $section = Get-Section -Html $html

        $section | Should -Not -BeNullOrEmpty
        $html | Should -Match '<a href="#score-drivers">Score drivers</a>'
        $section | Should -Match '<p class="muted"><strong>2</strong> site collection\(s\) have a score without a signal that can be read'
        $section | Should -Match '<tr><td><span class="badge b1">Simple</span></td><td class="num">2</td><td class="num">0.01</td><td>-</td><td>-</td></tr>'
        $section | Should -Not -Match '<th>Signal</th>'
        $section | Should -Not -Match 'holds <strong>'
    }

    It 'still has no section when no site collection has a score at all' {
        $html = Get-Html -Record @((New-Site -Name 'a' -Category 1 -CategoryName 'Simple' -Score 0 -Reasons ''))

        $html | Should -Not -Match 'id="score-drivers"'
        $html | Should -Not -Match 'href="#score-drivers"'
    }
}

Describe 'The Score drivers section and the caps of the scoring' {
    BeforeAll {
        $script:Capped = @(
            (New-Site -Name 'a' -Score 7 -Reasons 'EventReceivers=121 (+4, capped from 181.5); Workflow2010Count=1 (+3)')
            (New-Site -Name 'b' -Score 4 -Reasons 'EventReceivers=300 (+4, capped from 450)')
            (New-Site -Name 'c' -Score 3 -Reasons 'EventReceivers=2 (+3)')
        )
    }

    It 'has a Capped in column, with the number of site collections for each signal, and explains it, when a cap cut something' {
        $section = Get-Section -Html (Get-Html -Record $script:Capped)

        $section | Should -Match '<th class="num">Weighs most in</th><th class="num">Capped in</th></tr>'
        $section | Should -Match '<tr><td>EventReceivers</td><td class="num">3</td><td class="num">79%</td><td class="num">3</td><td class="num">2</td></tr>'
        $section | Should -Match '<tr><td>Workflow2010Count</td><td class="num">1</td><td class="num">21%</td><td class="num">0</td><td class="num">0</td></tr>'
        $section | Should -Match '<em>Capped in</em> counts the site collections where the cap of the signal \(<code>Caps</code> in the Scoring section of the settings\) cut what it added\.'
    }

    It 'has no such column and no such explanation when no cap cut anything' {
        $section = Get-Section -Html (Get-Html -Record $script:Sites)

        $section | Should -Not -Match 'Capped in'
        $section | Should -Match '<th class="num">Weighs most in</th></tr>'
    }

    It 'advises to lower the cap of the signal that holds most of the score when it is capped, and to cap it when it is not' {
        $capped = Get-Section -Html (Get-Html -Record $script:Capped)
        $uncapped = Get-Section -Html (Get-Html -Record $script:Sites)

        $capped | Should -Match 'If this is not what you expect, lower its cap, or review its weight, in the Scoring section of the settings\.'
        $capped | Should -Not -Match 'cap what it can add'
        $uncapped | Should -Match 'If this is not what you expect, review its weight, or cap what it can add with <code>Caps</code>, in the Scoring section of the settings\.'
        $uncapped | Should -Not -Match 'lower its cap'
    }
}
