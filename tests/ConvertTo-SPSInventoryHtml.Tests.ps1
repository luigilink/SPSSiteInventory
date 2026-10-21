# Behavior tests for ConvertTo-SPSInventoryHtml (pure HTML rendering, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:Sample = @(
        [PSCustomObject]@{
            Url = 'https://intranet/sites/team'; Title = 'Team & Co'; WebApp = 'Intranet'
            ContentDb = 'WSS_Content'; Template = 'STS#3'; SizeGB = 1.5; SubWebCount = 2
            SiteLockState = 'Unlock'; IsLockedSite = $false; IrmEnabledListCount = 0
            LastModified = [datetime]'2025-01-15'; Category = 1; CategoryName = 'Simple'
            Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
        },
        [PSCustomObject]@{
            Url = 'https://intranet/sites/legacy'; Title = 'Legacy <workflows>'; WebApp = 'Intranet'
            ContentDb = 'WSS_Content'; Template = 'STS#0'; SizeGB = 12.25; SubWebCount = 8
            SiteLockState = 'NoAccess'; IsLockedSite = $true; IrmEnabledListCount = 3
            LastModified = [datetime]'2024-06-01'; Category = 4; CategoryName = 'Blocking'
            UsesFullTrustCode = $true
            Wave = 4; WaveName = 'Projects / blockers'; Score = 9.5; Reasons = 'blocking: UsesFullTrustCode'
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

    It 'shows partial and failed assessment counts and per-site status' {
        $sites = @(
            [PSCustomObject]@{
                Url = 'https://intranet/sites/partial'; Category = 1; CategoryName = 'Simple'
                AssessmentStatus = 'Partial'; SiteInventoryComplete = $false
                CustomizationInventoryComplete = $true; ContentTypeInventoryComplete = $true
                AssessmentWarnings = 'Root web metadata could not be fully read'
                SizeGB = 1; Wave = 1; WaveName = 'Quick wins'; Score = 0
            },
            [PSCustomObject]@{
                Url = 'https://intranet/sites/failed'; Category = $null; CategoryName = 'Not assessed'
                AssessmentStatus = 'Failed'; SiteInventoryComplete = $true
                CustomizationInventoryComplete = $false; ContentTypeInventoryComplete = $false
                AssessmentWarnings = 'Assessment failed: Access denied'
                SizeGB = 2; Wave = 0; WaveName = 'Not assessed'; Score = $null
            }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $sites

        $html | Should -Match '<strong>1</strong> partial &middot; <strong>1</strong> failed'
        $html | Should -Match 'Assessment status'
        $html | Should -Match 'Customization complete'
        $html | Should -Match 'Assessment warnings'
        $html | Should -Match 'Root web metadata could not be fully read'
        $html | Should -Match 'Assessment failed: Access denied'
        $html | Should -Match 'Not assessed'
        $html | Should -Match 'data-category="0"'
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

    It 'keeps wave-zero groups distinct for unmapped and failed records in either input order' {
        $unassigned = [PSCustomObject]@{
            Url = 'https://intranet/sites/unmapped'; Category = 5; CategoryName = 'Other'
            AssessmentStatus = 'Complete'; SizeGB = 1; Wave = 0; WaveName = 'Unassigned'
        }
        $notAssessed = [PSCustomObject]@{
            Url = 'https://intranet/sites/failed'; Category = $null; CategoryName = 'Not assessed'
            AssessmentStatus = 'Failed'; SizeGB = 2; Wave = 0; WaveName = 'Not assessed'
        }

        $htmlFirst = ConvertTo-SPSInventoryHtml -InputObject @($unassigned, $notAssessed)
        $htmlReverse = ConvertTo-SPSInventoryHtml -InputObject @($notAssessed, $unassigned)
        foreach ($html in @($htmlFirst, $htmlReverse)) {
            ([regex]::Matches($html, '<td class="num">-</td><td>Unassigned</td><td class="num">1</td><td class="num">1</td>')).Count | Should -Be 1
            ([regex]::Matches($html, '<td class="num">-</td><td>Not assessed</td><td class="num">1</td><td class="num">2</td>')).Count | Should -Be 1
        }
    }

    It 'counts web-application enumeration failures separately from site collections' {
        $records = @(
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/team'
                AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'
                SizeGB = 1; Wave = 1; WaveName = 'Quick wins'
            },
            [PSCustomObject]@{
                InventoryScope = 'WebApplication'; Url = 'https://intranet'
                AssessmentStatus = 'Failed'; Category = $null; CategoryName = 'Not assessed'
                AssessmentWarnings = 'Site collection list could not be accessed: Access denied'
                SizeGB = $null; Wave = 0; WaveName = 'Not assessed'
            }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $records -ContentTypes @()

        $html | Should -Match '<strong>1</strong> site collection\(s\)'
        $html | Should -Match '<strong>1</strong> web application enumeration failure'
        $html | Should -Match '1 web application\(s\) had site collection enumeration failures'
        $html | Should -Match 'Inventory scope'
        $html | Should -Match 'WebApplication'
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

    It 'links full-trust solutions to the affected sites' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -SolutionMap $script:SolutionMap

        $html | Should -Match 'Sites bound to full-trust code'
        # The blocking site that uses full-trust code is listed with its URL.
        $html | Should -Match 'https://intranet/sites/legacy'
    }

    It 'omits the affected-sites table when no site uses full-trust code' {
        $simpleOnly = @(
            [PSCustomObject]@{
                Url = 'https://intranet/sites/ok'; Title = 'OK'; Category = 1; CategoryName = 'Simple'
                UsesFullTrustCode = $false; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
            }
        )
        $html = ConvertTo-SPSInventoryHtml -InputObject $simpleOnly -SolutionMap $script:SolutionMap

        $html | Should -Match 'Farm solutions \(WSP\)'
        $html | Should -Not -Match 'Sites bound to full-trust code'
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

    It 'renders authentication by web application and does not infer sign-ins' {
        $site = [PSCustomObject]@{
            Url = 'https://intranet/sites/team'; WebAppUrl = 'https://intranet'
            AuthenticationZones = 'Default: Windows; Extranet: FBA (Members & Co)'
            AuthenticationModes = 'FBA; Windows'
            HasFbaZone = $true
            Category = 4; CategoryName = 'Blocking'; Wave = 4; Score = 0
        }
        $html = ConvertTo-SPSInventoryHtml -InputObject @($site)

        $html | Should -Match 'Web application authentication'
        $html | Should -Match 'not actual user sign-in activity'
        $html | Should -Match 'Members &amp; Co'
        $html | Should -Match 'FBA configured'
        $html | Should -Match '<span class="pill warn">Yes</span>'
    }

    It 'shows authentication metadata from a web-application failure row with zero collections' {
        $failure = [PSCustomObject]@{
            InventoryScope = 'WebApplication'
            WebAppUrl = 'https://intranet'
            AuthenticationZones = 'Default: Windows; Extranet: FBA'
            HasFbaZone = $true
            AuthenticationReviewRequired = $true
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject @($failure)

        $html | Should -Match 'Web application authentication'
        $html | Should -Match 'https://intranet'
        $html | Should -Match 'Default: Windows; Extranet: FBA'
        $html | Should -Match '<td class="num">0</td></tr>'
    }

    It 'shows unknown FBA state without displaying a false No pill' {
        $site = [PSCustomObject]@{
            Url = 'https://intranet/sites/team'; WebAppUrl = 'https://intranet'
            AuthenticationZones = 'Default: Unknown'; HasFbaZone = $null
            AuthenticationReviewRequired = $true; Category = 1
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject @($site)

        $html | Should -Match '<td>Unknown</td><td><span class="pill warn">Yes</span>'
    }

    It 'renders lock-state and IRM columns in the main table' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'Site lock state'
        $html | Should -Match 'Site locked'
        $html | Should -Match 'IRM-enabled lists'
        $html | Should -Match 'NoAccess'
        $html | Should -Match '>3</td>'
    }

    It 'renders navigation shortcuts and risk indicator cards' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'href="#summary"'
        $html | Should -Match 'href="#risk-indicators"'
        $html | Should -Match 'href="#inventory-table"'
        $html | Should -Match 'Risk indicators'
        $html | Should -Match 'Locked sites'
        $html | Should -Match 'IRM-enabled lists'
        $html | Should -Match 'Workflow 2010'
    }

    It 'renders encoded content-type detail and surfaces partial collection' {
        $site = [PSCustomObject]@{
            Url = 'https://intranet/sites/team'; Category = 1
            ContentTypeCount = 1; ListContentTypeBindingCount = 1
            ContentTypeInventoryComplete = $false
        }
        $types = @([PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team'
            Scope = 'List'; ListTitle = 'Records <Admin>'; ListUrl = '/sites/team/records?a=1&b=2'
            Name = 'Contract & Agreement'
            ContentTypeId = '0x01'; ParentContentTypeId = '0x0'; Group = 'Custom'
            FieldCount = 1; FieldTypes = 'Text'; DocumentTemplateUrl = 'a&b.dotx'
            Hidden = $true; ReadOnly = $true; Sealed = $false
        })

        $html = ConvertTo-SPSInventoryHtml -InputObject @($site) -ContentTypes $types

        $html | Should -Match 'Content types and list bindings'
        $html | Should -Match 'Partial collection'
        $html | Should -Match 'Records &lt;Admin&gt;'
        $html | Should -Match 'List URL'
        $html | Should -Match '/sites/team/records\?a=1&amp;b=2'
        $html | Should -Match 'Contract &amp; Agreement'
        $html | Should -Match 'a&amp;b.dotx'
        $html | Should -Match '(?s)<th>Hidden</th>.*<th>Read only</th>.*<th>Sealed</th>'
        $html | Should -Match '(?s)<td>True</td>\s*<td>True</td>\s*<td>False</td>'
        $html | Should -Not -Match 'Records <Admin>'
    }

    It 'renders an explicit empty content-type report when requested' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @() -ContentTypes @()

        $html | Should -Match '0</strong> definition/binding row'
    }
}
