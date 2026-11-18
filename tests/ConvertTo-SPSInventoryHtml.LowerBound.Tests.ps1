# The HTML report says which counts are lower bounds because a scan reached its cap, and how many site collections that is. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-SiteRecord {
        param ([string]$Name, $LowerBound = $null, [int]$FileVersionCount = 0, [string]$Scope = 'SiteCollection')
        $record = [PSCustomObject]@{
            InventoryScope = $Scope; Url = "https://intranet/sites/$Name"; Title = $Name; WebApp = 'Intranet'; AssessmentStatus = 'Complete'
            Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''; FileVersionCount = $FileVersionCount
        }
        if ($null -ne $LowerBound) { $record | Add-Member -NotePropertyName LowerBoundSignals -NotePropertyValue $LowerBound }
        $record
    }
}

Describe 'ConvertTo-SPSInventoryHtml and the lower bounds' {
    # Six signals are tied on purpose: they are counted in a hashtable whose order changes from one process to the next,
    # so with two of them a missing tie-break by name gave the right order by chance one run in two.
    It 'says how many site collections reached a cap and for which signals, the most frequent first and then by name' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @(
            (New-SiteRecord -Name 'a' -LowerBound 'SiteNotebookCount; HtmlFileCount; ScriptWebPartCount; AudienceTargetedListCount')
            (New-SiteRecord -Name 'b' -LowerBound 'FileVersionCount; HtmlFileCount; PublishingPageLayoutCount; AudienceTargetedItemCount')
            (New-SiteRecord -Name 'c' -LowerBound '')
            (New-SiteRecord -Name 'd')
        )

        $html | Should -Match '<div class="summary-total"><strong>2</strong> site collection\(s\) reached the cap of a scan, so some counts are lower bounds there \(shown as &quot;at least&quot; in the detail of the site collection\): HtmlFileCount \(2\), AudienceTargetedItemCount \(1\), AudienceTargetedListCount \(1\), FileVersionCount \(1\), PublishingPageLayoutCount \(1\), ScriptWebPartCount \(1\), SiteNotebookCount \(1\)\. A cap alone does not make a site collection partial or change its category and wave; raise the caps of LargeContentThresholds to read more\.</div>'
    }

    It 'says nothing when no site collection reached a cap, and does not count a web application row' -ForEach @(
        @{ Case = 'the column is missing'; Spec = @(@{ Name = 'a' }) }
        @{ Case = 'the column is empty'; Spec = @(@{ Name = 'a'; LowerBound = '' }) }
        @{ Case = 'only separators'; Spec = @(@{ Name = 'a'; LowerBound = ' ; ; ' }) }
        @{ Case = 'a web application row'; Spec = @(@{ Name = 'a' }, @{ Name = 'app'; LowerBound = 'FileVersionCount'; Scope = 'WebApplication' }) }
    ) {
        $record = foreach ($site in $Spec) { New-SiteRecord @site }
        $html = ConvertTo-SPSInventoryHtml -InputObject @($record)

        $html | Should -Not -Match 'reached the cap of a scan' -Because $Case
    }

    It 'encodes the names of the signals' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @((New-SiteRecord -Name 'a' -LowerBound 'X<script>alert(1)</script>'))

        $html | Should -Not -Match '<script>alert\(1\)'
        $html | Should -Match 'X&lt;script&gt;alert\(1\)&lt;/script&gt; \(1\)\.'
    }

    It 'shows the count as "at least" in the detail of the site collection that reached the cap, and as the number in the others' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @(
            (New-SiteRecord -Name 'capped' -LowerBound 'FileVersionCount' -FileVersionCount 5)
            (New-SiteRecord -Name 'exact' -LowerBound '' -FileVersionCount 7)
        )

        $html | Should -Match '<span class="sig-value">at least 5</span>'
        $html | Should -Match '<span class="sig-value">7</span>'
        $html | Should -Not -Match '<span class="sig-value">5</span>'
        $html | Should -Not -Match 'at least 7'
    }
}
