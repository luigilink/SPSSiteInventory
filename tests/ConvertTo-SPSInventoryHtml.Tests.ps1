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
            Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
        },
        [PSCustomObject]@{
            Url = 'https://intranet/sites/legacy'; Title = 'Legacy <workflows>'; WebApp = 'Intranet'
            ContentDb = 'WSS_Content'; Template = 'STS#0'; SizeGB = 12.25; SubWebCount = 8
            LastModified = [datetime]'2024-06-01'; Category = 4; CategoryName = 'Blocking'
            Wave = 4; WaveName = 'Projects / blockers'; Score = 9.5; Reasons = 'blocking: UsesCustomFarmFeature'
        }
    )

    $script:SolutionMap = @(
        [PSCustomObject]@{
            SolutionName = 'contoso.portal.wsp'; Deployed = $true; DeploymentState = 'GlobalDeployed'
            IsCustom = $true; ContainsGlobalAssembly = $true; ContainsCasPolicy = $false
            ContainsWebApplicationResource = $true; IsFullTrustCode = $true
            FeatureCount = 3; FeatureScopes = @('Site', 'Web'); FeatureIds = @('f1', 'f2', 'f3')
        },
        [PSCustomObject]@{
            SolutionName = 'microsoft.sharepoint.search.wsp'; Deployed = $true; DeploymentState = 'GlobalDeployed'
            IsCustom = $false; ContainsGlobalAssembly = $false; ContainsCasPolicy = $false
            ContainsWebApplicationResource = $false; IsFullTrustCode = $false
            FeatureCount = 6; FeatureScopes = @('Farm'); FeatureIds = @()
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

    It 'renders the migration wave plan with per-wave counts and sizes' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'Migration wave plan'
        # Wave summary table header.
        $html | Should -Match '<th>Wave</th><th>Name</th><th class="num">Sites</th><th class="num">Content \(GB\)</th>'
        # Wave 1 row: Quick wins, 1 site, 1.5 GB.
        $html | Should -Match 'Quick wins</td><td class="num">1</td><td class="num">1\.5</td>'
        # Wave 4 row: Projects / blockers, 1 site, 12.25 GB.
        $html | Should -Match 'Projects / blockers</td><td class="num">1</td><td class="num">12\.25</td>'
        # The site table exposes a Wave column.
        $html | Should -Match 'Wave <span class="arrow">'
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

    It 'omits the Farm solutions section when no SolutionMap is given' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Not -Match 'Farm solutions \(WSP\)'
    }

    It 'renders the Farm solutions section with a WSP summary and table' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -SolutionMap $script:SolutionMap

        $html | Should -Match 'Farm solutions \(WSP\)'
        # Summary: 2 solutions, 1 custom, 1 full-trust.
        $html | Should -Match '<strong>2</strong> farm solution\(s\) &middot; <strong>1</strong> custom &middot; <strong>1</strong> full-trust code'
        # The custom full-trust WSP is listed with Yes pills.
        $html | Should -Match 'contoso\.portal\.wsp'
        $html | Should -Match 'class="pill yes">Yes<'
        # The Microsoft WSP is not custom / not full-trust.
        $html | Should -Match 'microsoft\.sharepoint\.search\.wsp'
        $html | Should -Match 'class="pill no">No<'
        # Feature scopes surfaced.
        $html | Should -Match 'Site; Web'
    }

    It 'HTML-encodes solution values in the WSP section' {
        $map = @(
            [PSCustomObject]@{
                SolutionName = 'a&b <x>.wsp'; Deployed = $true; DeploymentState = 'GlobalDeployed'
                IsCustom = $true; ContainsGlobalAssembly = $true; ContainsCasPolicy = $false
                ContainsWebApplicationResource = $false; IsFullTrustCode = $true
                FeatureCount = 1; FeatureScopes = @('Site'); FeatureIds = @('f1')
            }
        )
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -SolutionMap $map

        $html | Should -Match 'a&amp;b &lt;x&gt;\.wsp'
    }
}
