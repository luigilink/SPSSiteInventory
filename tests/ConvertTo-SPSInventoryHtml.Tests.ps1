# Behavior tests for ConvertTo-SPSInventoryHtml (pure HTML rendering, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:Sample = @(
        [PSCustomObject]@{
            Url = 'https://intranet/sites/team'; Title = 'Team & Co'; WebApp = 'Intranet'
            ContentDb = 'WSS_Content'; Template = 'STS#3'; SizeGB = 1.5; SubWebCount = 2
            TemplateCompatibility = 'Compatible'; IsUnsupportedSiteTemplate = $false
            TemplateCompatibilityReason = "Template 'STS#3' matches a compatibility prefix."
            TemplateLanguageLcid = 1033; TemplateLanguageTag = 'en-US'; TemplateLanguageName = 'English (United States)'
            TemplateLanguageReviewRequired = $false; TemplateLanguageReason = ''
            Workflow2010RunningInstanceCount = 0; Workflow2013RunningInstanceCount = 0
            AppInstanceCount = 0; AppWebCount = 0; AppInstanceExamples = ''
            PublishingInfrastructureEnabled = $false; PublishingWebCount = 0; PublishingPageCount = 0
            PublishingPageLayoutCount = 0; PublishingPageLayoutExamples = ''
            CustomizedPageCount = 0; CustomizedPageExamples = ''
            WebAppUrl = 'https://intranet'; BrowserFileHandling = 'Strict'
            WebAppPolicyCount = 2; WebAppPolicyExamples = 'CONTOSO\farm: Full Control; CONTOSO\crawl: Full Read'
            CustomPermissionLevelCount = 0; CustomPermissionLevelExamples = ''
            EmailEnabledListCount = 0; EmailEnabledListExamples = ''
            HtmlFileCount = 0; HtmlFileExamples = ''
            ManagedMetadataListCount = 0; ManagedMetadataColumnCount = 0; ManagedMetadataTermSetCount = 0; ManagedMetadataExamples = ''
            ExternalListCount = 0; ExternalListExamples = ''
            SharePointAlertCount = 0
            IsLargeSite = $false; LargeListCount = 0; LargeListExamples = ''
            LargeListViewCount = 0; LargeListViewExamples = ''
            CheckedOutFileCount = 0; CheckedOutFileExamples = ''
            FileVersionCount = 0; FileVersionExamples = ''
            SiteLockState = 'Unlock'; IsLockedSite = $false; IrmEnabledListCount = 0
            LastModified = [datetime]'2025-01-15'; Category = 1; CategoryName = 'Simple'
            Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
        },
        [PSCustomObject]@{
            Url = 'https://intranet/sites/legacy'; Title = 'Legacy <workflows>'; WebApp = 'Intranet'
            ContentDb = 'WSS_Content'; Template = 'STS#0'; SizeGB = 12.25; SubWebCount = 8
            TemplateCompatibility = 'Review'; IsUnsupportedSiteTemplate = $false
            TemplateCompatibilityReason = "Template 'STS#0' requires manual validation."
            TemplateLanguageLcid = 999999; TemplateLanguageTag = ''; TemplateLanguageName = ''
            TemplateLanguageReviewRequired = $true; TemplateLanguageReason = 'Template language LCID is not recognized.'
            Workflow2010RunningInstanceCount = 4; Workflow2013RunningInstanceCount = 2
            AppInstanceCount = 3; AppWebCount = 1; AppInstanceExamples = 'Contoso App (https://intranet/sites/legacy)'
            PublishingInfrastructureEnabled = $true; PublishingWebCount = 2; PublishingPageCount = 40
            PublishingPageLayoutCount = 3; PublishingPageLayoutExamples = 'ArticleLeft.aspx (30)'
            CustomizedPageCount = 2; CustomizedPageExamples = '/sites/legacy/default.aspx'
            WebAppUrl = 'https://legacy'; BrowserFileHandling = 'Permissive'
            WebAppPolicyCount = 3; WebAppPolicyExamples = 'CONTOSO\farm: Full Control; R&D <ops>: Full Read'
            CustomPermissionLevelCount = 2; CustomPermissionLevelExamples = 'Project Manager (https://intranet/sites/legacy)'
            EmailEnabledListCount = 1; EmailEnabledListExamples = 'Invoices (/sites/legacy/Invoices)'
            HtmlFileCount = 4; HtmlFileExamples = '/sites/legacy/Docs/a.htm'
            ManagedMetadataListCount = 2; ManagedMetadataColumnCount = 3; ManagedMetadataTermSetCount = 2
            ManagedMetadataExamples = 'Contracts (Department, Region); Projects <Q&A> (Department)'
            ExternalListCount = 2; ExternalListExamples = 'Customers (Contoso.Crm.Customer); Orders <SAP> (Contoso.Sap.Order)'
            SharePointAlertCount = 1234
            IsLargeSite = $true; LargeListCount = 2; LargeListExamples = 'Documents (7000); Records (5100)'
            LargeListViewCount = 1; LargeListViewExamples = 'Documents/All Documents (7000)'
            CheckedOutFileCount = 3; CheckedOutFileExamples = 'Documents (3)'
            FileVersionCount = 2; FileVersionExamples = '/sites/legacy/docs/spec.docx (80)'
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

    It 'shows permission and policy signals in summary cards and table columns' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with custom permission levels</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with e-mail enabled lists</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with HTML files</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites in web applications with permissive browser file handling</div>'
        foreach ($label in @('Custom permission levels', 'Custom permission level examples', 'E-mail enabled lists', 'E-mail enabled list examples', 'HTML files', 'HTML file examples', 'Browser file handling', 'Web application policies', 'Web application policy examples')) {
            $html | Should -Match ('>{0} <span class="arrow">' -f $label)
        }
        $html | Should -Match 'Project Manager \(https://intranet/sites/legacy\)'
    }

    It 'shows managed metadata signals in the summary card and table columns' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with managed metadata columns</div>'
        foreach ($label in @('Managed metadata lists', 'Managed metadata columns', 'Term sets in use', 'Managed metadata examples')) {
            $html | Should -Match ('>{0} <span class="arrow">' -f $label)
        }
        $html | Should -Match 'Projects &lt;Q&amp;A&gt; \(Department\)'
        $html | Should -Not -Match 'Projects <Q&A>'
    }

    It 'shows external list signals in the summary card and table columns' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with external lists</div>'
        foreach ($label in @('External lists', 'External list examples')) {
            $html | Should -Match ('>{0} <span class="arrow">' -f $label)
        }
        $html | Should -Match 'Orders &lt;SAP&gt; \(Contoso.Sap.Order\)'
        $html | Should -Not -Match 'Orders <SAP>'
    }

    It 'shows the SharePoint alert count in the summary card and table column, without the alert rows' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '>SharePoint alerts <span class="arrow">'
        $html | Should -Match '<td class="num">1234</td>'
    }

    It 'counts the sites that have SharePoint alerts, not the sites with other signals' {
        $records = @(
            [PSCustomObject]@{ Url = 'https://intranet/sites/a'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; SharePointAlertCount = 3; ExternalListCount = 0 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/b'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; SharePointAlertCount = 0; ExternalListCount = 2 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/c'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; SharePointAlertCount = 1; ExternalListCount = 0 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/d'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins' }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $records

        $html | Should -Match '<div class="num">2</div><div class="lbl">Sites with SharePoint alerts</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with external lists</div>'
    }

    It 'renders a web application policies section grouped by web application' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<h2 id="web-app-policies">Web application policies</h2>'
        $html | Should -Match '<a href="#web-app-policies">Web application policies</a>'
        $html | Should -Match '<td>https://legacy</td><td><span class="pill warn">Permissive</span></td><td class="num">3</td>'
        $html | Should -Match '<td>https://intranet</td><td>Strict</td><td class="num">2</td>'
        $html | Should -Match 'R&amp;D &lt;ops&gt;: Full Read'
        $html | Should -Not -Match 'R&D <ops>'
    }

    It 'omits the web application policies section when no policy data was collected' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @([PSCustomObject]@{ Url = 'https://intranet/sites/a'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins' })

        $html | Should -Not -Match 'id="web-app-policies"'
        $html | Should -Not -Match 'href="#web-app-policies"'
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

    It 'shows app signals in summary cards and table columns' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'Sites with app instances'
        $html | Should -Match 'Sites with app webs'
        $html | Should -Match '>App instances <span class="arrow">'
        $html | Should -Match '>App webs <span class="arrow">'
        $html | Should -Match '>App instance examples <span class="arrow">'
    }

    It 'shows publishing and customized-page signals in summary cards and table columns' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with publishing features</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with publishing pages</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with customized pages</div>'
        foreach ($label in @('Publishing infrastructure', 'Publishing webs', 'Publishing pages', 'Page layouts in use', 'Page layout examples', 'Customized pages', 'Customized page examples')) {
            $html | Should -Match ('>{0} <span class="arrow">' -f $label)
        }
        $html | Should -Match 'ArticleLeft\.aspx \(30\)'
        $html | Should -Match '/sites/legacy/default\.aspx'
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
        $html | Should -Match 'href="#wave-plan"'
        $html | Should -Match 'href="#inventory-table"'
        $html | Should -Match 'Risk indicators'
        $html | Should -Match 'Sites with locked state'
        $html | Should -Match 'Sites with IRM-enabled lists'
        $html | Should -Match 'Sites with unsupported templates'
        $html | Should -Match 'Sites with template compatibility review'
        $html | Should -Match 'Sites with template-language review'
        $html | Should -Match 'Sites with Workflow 2010'
        $html | Should -Match 'Sites with running Workflow 2010'
        $html | Should -Match 'Sites with running Workflow 2013'
        $html | Should -Match 'Sites above large-size threshold'
        $html | Should -Match 'Sites with large lists'
        $html | Should -Match 'Sites with checked-out files'
        $html | Should -Match 'Sites with high file-version counts'
        $html | Should -Not -Match 'href="#farm-solutions"'
        $html | Should -Not -Match 'href="#authentication"'
        $html | Should -Not -Match 'href="#content-types"'
        $html | Should -Not -Match 'href="#managed-metadata"'
        $html | Should -Not -Match 'href="#external-lists"'
        $html | Should -Not -Match 'href="#bcs-applications"'
    }

    It 'renders large-content columns in the main table' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'Large site'
        $html | Should -Match 'Large lists'
        $html | Should -Match 'Large-list views'
        $html | Should -Match 'Checked-out files'
        $html | Should -Match 'High-version files'
        $html | Should -Match 'Running WF 2010'
        $html | Should -Match 'Running WF 2013'
        $html | Should -Match 'Template compatibility'
        $html | Should -Match 'Unsupported template'
        $html | Should -Match 'Template language LCID'
        $html | Should -Match 'Template language review'
        $html | Should -Match 'Documents \(7000\); Records \(5100\)'
        $html | Should -Match 'Documents/All Documents \(7000\)'
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
        $html | Should -Not -Match 'href="#wave-plan"'
    }

    It 'renders encoded managed metadata detail, guidance and coverage warnings' {
        $sites = @(
            [PSCustomObject]@{
                Url = 'https://intranet/sites/team'; Category = 1
                ManagedMetadataListCount = 1; CustomizationInventoryComplete = $false
            },
            [PSCustomObject]@{
                InventoryScope = 'WebApplication'; Url = 'https://other'; WebAppUrl = 'https://other'
                AssessmentStatus = 'Failed'
            }
        )
        $lists = @([PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team/sub'
            ListTitle = 'Records <Admin>'; ListUrl = '/sites/team/records?a=1&b=2'
            ListTemplate = 'DocumentLibrary'; ListType = 'DocumentLibrary'
            ListItemCount = 1250; ItemLastModifiedDate = '2026-03-04 10:20:30'
            ManagedMetadataColumnCount = 2; ManagedMetadataColumns = 'Department; R&D'
            TermSetIds = '11111111-1111-1111-1111-111111111111; 22222222-2222-2222-2222-222222222222'
        })

        $html = ConvertTo-SPSInventoryHtml -InputObject $sites -ManagedMetadataLists $lists

        $html | Should -Match '<h2 id="managed-metadata">Managed metadata columns by list</h2>'
        $html | Should -Match '<a href="#managed-metadata">Managed metadata</a>'
        $html | Should -Match '<strong>1</strong> list\(s\) with managed metadata columns'
        $html | Should -Match 'Plan the term store migration together with these lists'
        $html | Should -Match 'Coverage warning:</strong> 1 web application'
        $html | Should -Match 'Partial collection:</strong> 1 site collection'
        $html | Should -Match '(?s)<th>Site</th>.*<th>Web</th>.*<th>List</th>.*<th>List URL</th>.*<th>Template</th>.*<th>Type</th>.*<th>Items</th>.*<th>Last modified</th>.*<th>Columns</th>.*<th>Managed metadata columns</th>.*<th>Term set IDs</th>'
        $html | Should -Match 'Records &lt;Admin&gt;'
        $html | Should -Match '/sites/team/records\?a=1&amp;b=2'
        $html | Should -Match 'Department; R&amp;D'
        $html | Should -Match '<td>1250</td>'
        $html | Should -Match '11111111-1111-1111-1111-111111111111; 22222222-2222-2222-2222-222222222222'
        $html | Should -Not -Match 'Records <Admin>'
    }

    It 'renders an explicit empty managed metadata section when requested' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @() -ManagedMetadataLists @()

        $html | Should -Match '<strong>0</strong> list\(s\) with managed metadata columns'
        $html | Should -Not -Match 'Coverage warning'
        $html | Should -Not -Match 'Partial collection'
    }

    It 'omits the managed metadata section when no managed metadata rows are passed' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Not -Match 'id="managed-metadata"'
        $html | Should -Not -Match 'href="#managed-metadata"'
    }

    It 'renders encoded external list detail, guidance and coverage warnings' {
        $sites = @(
            [PSCustomObject]@{
                Url = 'https://intranet/sites/team'; Category = 1
                ExternalListCount = 1; CustomizationInventoryComplete = $false
            },
            [PSCustomObject]@{
                InventoryScope = 'WebApplication'; Url = 'https://other'; WebAppUrl = 'https://other'
                AssessmentStatus = 'Failed'
            }
        )
        $lists = @([PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team/sub'
            ListTitle = 'Customers <CRM>'; ListUrl = '/sites/team/Lists/Customers?a=1&b=2'
            LobSystemInstance = 'Crm & Billing'; EntityNamespace = 'Contoso.Crm'; Entity = 'Customer'
        })

        $html = ConvertTo-SPSInventoryHtml -InputObject $sites -ExternalLists $lists

        $html | Should -Match '<h2 id="external-lists">External lists</h2>'
        $html | Should -Match '<a href="#external-lists">External lists</a>'
        $html | Should -Match '<strong>1</strong> external list\(s\)'
        $html | Should -Match 'Microsoft retired BCS in SharePoint Online on 30 September 2024'
        $html | Should -Match 'cannot be recreated there and there is no direct migration'
        $html | Should -Match 'for example with Power Apps and its connectors'
        $html | Should -Not -Match 'hybrid'
        $html | Should -Match 'Coverage warning:</strong> 1 web application'
        $html | Should -Match 'Partial collection:</strong> 1 site collection'
        $html | Should -Match '(?s)<th>Site</th>.*<th>Web</th>.*<th>List</th>.*<th>List URL</th>.*<th>LOB system instance</th>.*<th>Entity namespace</th>.*<th>Entity</th>'
        $html | Should -Match 'Customers &lt;CRM&gt;'
        $html | Should -Match '/sites/team/Lists/Customers\?a=1&amp;b=2'
        $html | Should -Match 'Crm &amp; Billing'
        $html | Should -Not -Match 'Customers <CRM>'
    }

    It 'renders an explicit empty external list section when requested' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @() -ExternalLists @()

        $html | Should -Match '<strong>0</strong> external list\(s\)'
        $html | Should -Not -Match 'Coverage warning'
        $html | Should -Not -Match 'Partial collection'
    }

    It 'renders encoded BCS applications with guidance' {
        $applications = @([PSCustomObject]@{
            WebApplicationUrls = 'https://intranet; https://extranet'; BdcServiceApplicationId = '11111111-1111-1111-1111-111111111111'
            LobSystemName = 'Crm & <Billing>'
            LobSystemType = 'Wcf'; LobSystemInstances = 'CrmProd; CrmDev'; EntityCount = 2
            LobEntities = 'Contoso.Crm.Account; Contoso.Crm.Customer'
        })

        $html = ConvertTo-SPSInventoryHtml -InputObject @() -BcsApplications $applications

        $html | Should -Match '<h2 id="bcs-applications">Business Connectivity Services applications</h2>'
        $html | Should -Match '<a href="#bcs-applications">BCS applications</a>'
        $html | Should -Match '<strong>1</strong> BCS LOB system\(s\)'
        $html | Should -Match 'BCS is retired in SharePoint Online \(30 September 2024\), so BCS applications cannot be migrated there'
        $html | Should -Match 'for example Power Apps and its connectors'
        $html | Should -Not -Match 'hybrid'
        $html | Should -Match 'credentials and Secure Store targets are not read'
        $html | Should -Match '(?s)<th>Web application</th>.*<th>BDC service application</th>.*<th>LOB system</th>.*<th>Type</th>.*<th>Instances</th>.*<th>Entities</th>.*<th>Entity names</th>'
        $html | Should -Match '11111111-1111-1111-1111-111111111111'
        $html | Should -Match 'Crm &amp; &lt;Billing&gt;'
        $html | Should -Match 'https://intranet; https://extranet'
        $html | Should -Match '<td>2</td>'
        $html | Should -Not -Match 'Crm & <Billing>'
        $html | Should -Not -Match 'Partial collection'
    }

    It 'says that BCS applications may be missing when the BCS inventory is partial' {
        $html = ConvertTo-SPSInventoryHtml -InputObject @() -BcsApplications @() -BcsInventoryComplete $false

        $html | Should -Match '<strong>0</strong> BCS LOB system\(s\)'
        $html | Should -Match 'Partial collection:</strong> some web applications or LOB systems could not be read'
    }

    It 'omits the external list and BCS sections when no rows are passed' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Not -Match 'id="external-lists"'
        $html | Should -Not -Match 'id="bcs-applications"'
    }

    It 'renders the alerts grouped by type, most severe first, with remediation and a reference link' {
        $learn = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-checked-out-files'
        $alerts = @(
            1..3 | ForEach-Object { [PSCustomObject]@{ AlertType = 'CheckedOutFiles'; Severity = 'Medium'; Url = "https://intranet/sites/$_"; Value = 1; Message = 'site specific'; Remediation = 'Ask the users to <check in> their files & retry.'; Reference = $learn } }
            1..2 | ForEach-Object { [PSCustomObject]@{ AlertType = 'InfoPath'; Severity = 'High'; Url = "https://intranet/sites/hr$_"; Value = 1; Message = 'site specific'; Remediation = 'Rebuild the forms.'; Reference = '' } }
            [PSCustomObject]@{ AlertType = 'FileVersions'; Severity = 'Medium'; Url = 'https://intranet/sites/x'; Value = 1; Message = 'site specific'; Remediation = 'Decide on the versions.'; Reference = '' }
            1..2 | ForEach-Object { [PSCustomObject]@{ AlertType = 'AlertSubscriptions'; Severity = 'Low'; Url = "https://intranet/sites/al$_"; Value = 3; Message = 'site specific'; Remediation = 'Tell the users.'; Reference = '' } }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject @() -Alert $alerts

        $html | Should -Match '<h2 id="alerts">Alerts and remediation</h2>'
        $html | Should -Match '<a href="#alerts">Alerts</a>'
        $html | Should -Match '<strong>8</strong> alert\(s\) of <strong>4</strong> type\(s\): <strong>2</strong> high, <strong>4</strong> medium and <strong>2</strong> low'
        $html | Should -Match '(?s)<table class="alerts">.*<th>Severity</th><th>Alert</th><th class="num">Affected</th><th>What it means</th><th>What to do</th><th>Reference</th>'
        $html | Should -Match '(?s)<td>InfoPath</td>.*<td>CheckedOutFiles</td>.*<td>FileVersions</td>.*<td>AlertSubscriptions</td>'
        $html | Should -Match '<span class="pill no">Low</span></td><td>AlertSubscriptions</td><td class="num">2</td>'
        $html | Should -Match 'Users have SharePoint alerts \(Alert Me subscriptions\) on this site; migration tools do not migrate them\.'
        $html | Should -Match '<span class="pill yes">High</span></td><td>InfoPath</td><td class="num">2</td>'
        $html | Should -Match '<span class="pill warn">Medium</span></td><td>CheckedOutFiles</td><td class="num">3</td>'
        $html | Should -Match 'Checked-out files were detected and should be checked in before migration\.'
        $html | Should -Not -Match 'site specific'
        $html | Should -Match 'Ask the users to &lt;check in&gt; their files &amp; retry\.'
        $html | Should -Not -Match 'Ask the users to <check in>'
        $html | Should -Match ('<a href="{0}">Microsoft Learn</a>' -f [regex]::Escape($learn))
        ([regex]::Matches($html, 'Microsoft Learn</a>')).Count | Should -Be 1
    }

    It 'falls back to the message of the alert for a type that is not in the catalog' {
        $alerts = @([PSCustomObject]@{ AlertType = 'Custom <type>'; Severity = 'Low'; Url = 'u'; Value = 1; Message = 'Custom & message'; Remediation = 'Custom remediation.'; Reference = 'not a link' })

        $html = ConvertTo-SPSInventoryHtml -InputObject @() -Alert $alerts

        $html | Should -Match '<span class="pill no">Low</span>'
        $html | Should -Match 'Custom &lt;type&gt;'
        $html | Should -Match 'Custom &amp; message'
        $html | Should -Not -Match 'Microsoft Learn</a>'
    }

    It 'renders an explicit empty alerts section when requested and none when no alerts are passed' {
        $empty = ConvertTo-SPSInventoryHtml -InputObject @() -Alert @()
        $omitted = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $empty | Should -Match '<strong>0</strong> alert\(s\) of <strong>0</strong> type\(s\)'
        $empty | Should -Not -Match '<table class="alerts">'
        $omitted | Should -Not -Match 'id="alerts"'
        $omitted | Should -Not -Match 'href="#alerts"'
    }
}
