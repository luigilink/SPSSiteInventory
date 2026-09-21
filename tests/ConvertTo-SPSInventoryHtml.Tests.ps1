# Behavior tests for ConvertTo-SPSInventoryHtml (pure HTML rendering, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:Sample = @(
        [PSCustomObject]@{
            Url = 'https://intranet/sites/team'; Title = 'Team & Co'; WebApp = 'Intranet'
            ContentDb = 'WSS_Content'; Template = 'STS#3'; SizeGB = 1.5; SubWebCount = 2
            LastModified = [datetime]'2025-01-15'; Category = 1; CategoryName = 'Simple'
            Score = 0; Reasons = ''
        },
        [PSCustomObject]@{
            Url = 'https://intranet/sites/legacy'; Title = 'Legacy <workflows>'; WebApp = 'Intranet'
            ContentDb = 'WSS_Content'; Template = 'STS#0'; SizeGB = 12.25; SubWebCount = 8
            LastModified = [datetime]'2024-06-01'; Category = 4; CategoryName = 'Blocking'
            Score = 9.5; Reasons = 'blocking: UsesCustomFarmFeature'
        }
    )
}

Describe 'ConvertTo-SPSInventoryHtml' {
    It 'returns a single self-contained HTML document' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -EnvName 'PROD' -GeneratedOn ([datetime]'2026-09-21T10:00:00')

        $html | Should -BeOfType [string]
        $html | Should -Match '<!DOCTYPE html>'
        $html | Should -Match '</html>'
        # Self-contained: no external stylesheet or script reference.
        $html | Should -Not -Match '<link[^>]+href'
        $html | Should -Not -Match 'src="http'
    }

    It 'applies the house style (Aptos font and blue headings)' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match "font-family: 'Aptos'"
        $html | Should -Match 'rgb\(31, 56, 100\)'
    }

    It 'renders a summary box with per-category counts and the total' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'class="summary"'
        # Two sites total.
        $html | Should -Match '<strong>2</strong> site collection'
        # Total content size (1.5 + 12.25 = 13.75 GB).
        $html | Should -Match '13\.75 GB'
        # Category labels present in the summary cards.
        $html | Should -Match '1\. Simple'
        $html | Should -Match '4\. Blocking'
    }

    It 'HTML-encodes field values so markup cannot break' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'Team &amp; Co'
        $html | Should -Match 'Legacy &lt;workflows&gt;'
        $html | Should -Not -Match 'Legacy <workflows>'
    }

    It 'tags each row with its category for filtering' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'data-category="1"'
        $html | Should -Match 'data-category="4"'
        $html | Should -Match 'class="badge b4"'
    }

    It 'shows the environment name in the header when provided' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -EnvName 'CONTOSO-PROD'

        $html | Should -Match 'CONTOSO-PROD'
    }

    It 'handles an empty inventory without error' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @()

        $html | Should -Match '<!DOCTYPE html>'
        $html | Should -Match '<strong>0</strong> site collection'
    }
}
