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
            SiteLockState = 'Unlock'; IsLockedSite = $false; HasNoAccessLock = $false; IrmEnabledListCount = 0
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
            SiteLockState = 'NoAccess'; IsLockedSite = $true; HasNoAccessLock = $true; IrmEnabledListCount = 3
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
        $html | Should -Match '<th data-type="text">Status <span class="arrow">'
        $html | Should -Match '<span class="pill warn">Partial</span>'
        $html | Should -Match '<span class="pill yes">Failed</span>'
        $html | Should -Match '<dt>Site inventory incomplete</dt>'
        $html | Should -Match '<dt>Customization inventory incomplete</dt>'
        $html | Should -Match '<dt>Content type inventory incomplete</dt>'
        $html | Should -Match 'Assessment warnings</strong> Root web metadata could not be fully read'
        $html | Should -Match 'Assessment warnings</strong> Assessment failed: Access denied'
        $html | Should -Match 'Not assessed'
        $html | Should -Match 'data-category="0"'
    }

    It 'shows permission and policy signals in summary cards and in the details of a site' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with custom permission levels</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with e-mail enabled lists</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with HTML files</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites in web applications with permissive browser file handling</div>'
        $html | Should -Match '<dt>Custom permission levels</dt><dd><span class="sig-value">2</span> <span class="sig-detail">Project Manager \(https://intranet/sites/legacy\)</span></dd>'
        $html | Should -Match '<dt>E-mail enabled lists</dt><dd><span class="sig-value">1</span> <span class="sig-detail">Invoices \(/sites/legacy/Invoices\)</span></dd>'
        $html | Should -Match '<dt>HTML files</dt><dd><span class="sig-value">4</span> <span class="sig-detail">/sites/legacy/Docs/a\.htm</span></dd>'
        $html | Should -Match '<dt>Browser file handling</dt><dd><span class="sig-value">Permissive</span></dd>'
        # The policies belong to the web application: their section shows them once, not each site.
        $html | Should -Not -Match '<dt>Web application policies</dt>'
    }

    It 'shows managed metadata signals in the summary card and in the details of a site' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with managed metadata columns</div>'
        $html | Should -Match '<dt>Managed metadata</dt><dd><span class="sig-value">2 list\(s\), 3 column\(s\), 2 term set\(s\)</span>'
        $html | Should -Match 'Projects &lt;Q&amp;A&gt; \(Department\)'
        $html | Should -Not -Match 'Projects <Q&A>'
    }

    It 'shows external list signals in the summary card and in the details of a site' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with external lists</div>'
        $html | Should -Match '<dt>External lists</dt><dd><span class="sig-value">2</span>'
        $html | Should -Match 'Orders &lt;SAP&gt; \(Contoso.Sap.Order\)'
        $html | Should -Not -Match 'Orders <SAP>'
    }

    It 'shows the SharePoint alert count in the summary card and in the details of a site, without the alert rows' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with SharePoint alerts</div>'
        $html | Should -Match '<dt>SharePoint alerts</dt><dd><span class="sig-value">1234</span></dd>'
    }

    It 'shows the classic customization signals in summary cards and in the details, and counts only the sites that have them' {
        # The four cards count 1, 2, 3 and 4 sites, so that a card that reads the wrong field is noticed.
        $records = @(
            [PSCustomObject]@{ Url = 'https://intranet/sites/a'; Category = 2; CategoryName = 'Moderate'; Wave = 2; WaveName = 'Light remediation'; UsesCustomFarmFeature = $true; SandboxSolutions = 1; CustomMasterPage = $true; EventReceivers = 3; UniquePermissionsCount = 9 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/b'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; UsesCustomFarmFeature = $false; SandboxSolutions = 1; CustomMasterPage = $true; EventReceivers = 1; UniquePermissionsCount = 4 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/c'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; UsesCustomFarmFeature = $false; SandboxSolutions = 1; CustomMasterPage = $false; EventReceivers = 1; UniquePermissionsCount = 4 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/d'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; UsesCustomFarmFeature = $false; SandboxSolutions = 0; CustomMasterPage = $false; EventReceivers = 1; UniquePermissionsCount = 4 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/e'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins' }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $records

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with custom farm features</div>'
        $html | Should -Match '<div class="num">2</div><div class="lbl">Sites with a custom master page</div>'
        $html | Should -Match '<div class="num">3</div><div class="lbl">Sites with sandbox solutions</div>'
        $html | Should -Match '<div class="num">4</div><div class="lbl">Sites with custom event receivers</div>'
        # The details list a signal only for the sites that raise it.
        ([regex]::Matches($html, '<dt>Custom farm feature</dt>')).Count | Should -Be 1
        ([regex]::Matches($html, '<dt>Sandbox solutions</dt>')).Count | Should -Be 3
        ([regex]::Matches($html, '<dt>Custom master page</dt>')).Count | Should -Be 2
        ([regex]::Matches($html, '<dt>Custom event receivers</dt>')).Count | Should -Be 4
        $html | Should -Match '<dt>Unique permission assignments</dt><dd><span class="sig-value">9</span></dd>'
        # A site with no signal says so instead of showing an empty row.
        ([regex]::Matches($html, 'No signal raised')).Count | Should -Be 1
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

    It 'shows the subsite structure in a summary card and in the details, and counts only the sites that have subsites' {
        $records = @(
            [PSCustomObject]@{ Url = 'https://intranet/sites/a'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; SubWebCount = 4; SubsiteCount = 3; MaxSubsiteDepth = 2; SubsiteExamples = 'payroll/<2026> (level 2); payroll (level 1)' }
            [PSCustomObject]@{ Url = 'https://intranet/sites/b'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; SubWebCount = 1; SubsiteCount = 0; MaxSubsiteDepth = 0; SubsiteExamples = '' }
            [PSCustomObject]@{ Url = 'https://intranet/sites/c'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins' }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $records

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with subsites</div>'
        $html | Should -Match '<dt>Subsites</dt><dd><span class="sig-value">3 \(depth 2\)</span> <span class="sig-detail">payroll/&lt;2026&gt; \(level 2\); payroll \(level 1\)</span></dd>'
        ([regex]::Matches($html, '<dt>Subsites</dt>')).Count | Should -Be 1
        # The number of webs, which includes the root web, is in the context line of the site.
        $html | Should -Match 'Webs <strong>4</strong>'
        $html | Should -Not -Match 'payroll/<2026>'
    }

    It 'shows the NoAccess lock in a summary card and in the details of a site' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites locked with NoAccess</div>'
        $html | Should -Match '<dt>Site lock</dt><dd><span class="sig-value">NoAccess</span></dd>'
    }

    It 'counts the NoAccess locks apart from the other locks' {
        $records = @(
            [PSCustomObject]@{ Url = 'https://intranet/sites/a'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; IsLockedSite = $true; HasNoAccessLock = $false; SiteLockState = 'ReadOnly' }
            [PSCustomObject]@{ Url = 'https://intranet/sites/b'; Category = 4; CategoryName = 'Blocking'; Wave = 4; WaveName = 'Projects / blockers'; IsLockedSite = $true; HasNoAccessLock = $true; SiteLockState = 'NoAccess' }
            [PSCustomObject]@{ Url = 'https://intranet/sites/c'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; IsLockedSite = $true; HasNoAccessLock = $false; SiteLockState = 'NoAdditions' }
            [PSCustomObject]@{ Url = 'https://intranet/sites/d'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; IsLockedSite = $false; HasNoAccessLock = $false; SiteLockState = 'Unlock' }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $records

        $html | Should -Match '<div class="num">3</div><div class="lbl">Sites with locked state</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites locked with NoAccess</div>'
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

    It 'shows app signals in summary cards and in the details of a site' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'Sites with app instances'
        $html | Should -Match 'Sites with app webs'
        $html | Should -Match '<dt>App instances</dt><dd><span class="sig-value">3</span> <span class="sig-detail">Contoso App \(https://intranet/sites/legacy\)</span></dd>'
        $html | Should -Match '<dt>App webs</dt><dd><span class="sig-value">1</span></dd>'
    }

    It 'shows publishing and customized-page signals in summary cards and in the details of a site' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with publishing features</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with publishing pages</div>'
        $html | Should -Match '<div class="num">1</div><div class="lbl">Sites with customized pages</div>'
        foreach ($label in @('Publishing infrastructure', 'Publishing webs', 'Publishing pages', 'Page layouts in use', 'Customized pages')) {
            $html | Should -Match ('<dt>{0}</dt>' -f $label)
        }
        $html | Should -Match 'ArticleLeft\.aspx \(30\)'
        $html | Should -Match '/sites/legacy/default\.aspx'
    }

    It 'shows the total of small site collections, not 0 GB' {
        $records = foreach ($suffix in 1..20) {
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/small$suffix"
                AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'
                SizeGB = 0.0029; Wave = 1; WaveName = 'Quick wins'
            }
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject @($records)

        $html | Should -Match '<strong>0\.06 GB</strong> total content'
        $html | Should -Match '<td class="num">20</td><td class="num">0\.06</td>'
    }

    It 'says that the content is under 0.01 GB when it is not zero but very small' {
        $record = [PSCustomObject]@{
            InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/tiny'
            AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'
            SizeGB = 0.0004; Wave = 1; WaveName = 'Quick wins'
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject @($record)

        $html | Should -Match '<strong>&lt; 0\.01 GB</strong> total content'
    }

    It 'shows 0 GB when the size of every site collection is unknown or zero' {
        $records = @(
            [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/a'; AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; SizeGB = 0; Wave = 1; WaveName = 'Quick wins' },
            [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/b'; AssessmentStatus = 'Partial'; Category = 1; CategoryName = 'Simple'; SizeGB = $null; Wave = 1; WaveName = 'Quick wins' }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $records

        $html | Should -Match '<strong>0 GB</strong> total content'
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
        # The failure is a row of the inventory table, tagged as a web application, with its warning.
        $html | Should -Match '<span class="pill no">Web application</span></div><div class="site-url">https://intranet</div>'
        $html | Should -Match 'Assessment warnings</strong> Site collection list could not be accessed: Access denied'
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

    It 'puts a category on each site collection and keeps the details in the same body' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<tbody class="site" data-category="1">'
        $html | Should -Match '<tbody class="site" data-category="4">'
        ([regex]::Matches($html, '<tbody class="site"')).Count | Should -Be 2
        ([regex]::Matches($html, '<tr class="main">')).Count | Should -Be 2
        ([regex]::Matches($html, '<tr class="detail">')).Count | Should -Be 2
        ([regex]::Matches($html, 'class="toggle"')).Count | Should -Be 2
    }

    It 'shows nine columns and a column for the toggle in the inventory table' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $header = [regex]::Match($html, '(?s)<table id="inv">\s*<thead>(.*?)</thead>').Groups[1].Value
        ([regex]::Matches($header, '<th')).Count | Should -Be 10
        $labels = @([regex]::Matches($header, '(?s)<th[^>]*>\s*([^<]*?)\s*(?:<span|</th>)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ })
        $labels | Should -Be @('Site', 'Category', 'Score', 'Wave', 'Size (GB)', 'Template', 'Last modified', 'Status', 'Reasons')
    }

    It 'shows the title and the URL of a site collection together, and the URL alone when there is no title' {
        $records = @(
            [PSCustomObject]@{ Url = 'https://intranet/sites/with-title'; Title = 'With <title>'; Category = 1; CategoryName = 'Simple' }
            [PSCustomObject]@{ Url = 'https://intranet/sites/no-title'; Category = 1; CategoryName = 'Simple' }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $records

        $html | Should -Match '<div class="site-title">With &lt;title&gt;</div><div class="site-url">https://intranet/sites/with-title</div>'
        $html | Should -Match '<div class="site-title">https://intranet/sites/no-title</div></td>'
        $html | Should -Not -Match 'With <title>'
    }

    It 'lists the site collections worst first, then by score' {
        $records = @(
            [PSCustomObject]@{ Url = 'https://intranet/sites/a-simple'; Category = 1; CategoryName = 'Simple'; Score = 0.5 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/b-moderate-low'; Category = 2; CategoryName = 'Moderate'; Score = 1.5 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/c-blocking'; Category = 4; CategoryName = 'Blocking'; Score = 3 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/d-moderate-high'; Category = 2; CategoryName = 'Moderate'; Score = 5.25 }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $records

        $order = @([regex]::Matches($html, '<div class="site-url">https://intranet/sites/([a-z-]+)</div>|<div class="site-title">https://intranet/sites/([a-z-]+)</div>') | ForEach-Object { $_.Groups[1].Value + $_.Groups[2].Value })
        $order | Should -Be @('c-blocking', 'd-moderate-high', 'b-moderate-low', 'a-simple')
    }

    It 'sorts by score with the same result in every culture' {
        $records = @(
            [PSCustomObject]@{ Url = 'https://intranet/sites/low'; Category = 2; CategoryName = 'Moderate'; Score = 1.5 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/high'; Category = 2; CategoryName = 'Moderate'; Score = 5.25 }
        )
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
            $html = ConvertTo-SPSInventoryHtml -InputObject $records
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }

        $html.IndexOf('sites/high') | Should -BeLessThan $html.IndexOf('sites/low')
        $html | Should -Match '<td class="num">5\.25</td>'
    }

    It 'puts the site collections that were not assessed first and adds a filter for them' {
        $records = @(
            [PSCustomObject]@{ Url = 'https://intranet/sites/ok'; Category = 4; CategoryName = 'Blocking'; Score = 9 }
            [PSCustomObject]@{ Url = 'https://intranet/sites/failed'; Category = $null; CategoryName = 'Not assessed'; AssessmentStatus = 'Failed' }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject $records

        $html.IndexOf('sites/failed') | Should -BeLessThan $html.IndexOf('sites/ok')
        $html | Should -Match '<button data-filter="0">Not assessed</button>'
        $withoutFailure = ConvertTo-SPSInventoryHtml -InputObject $script:Sample
        $withoutFailure | Should -Not -Match 'data-filter="0"'
    }

    It 'offers a search box, the category filters and a count of the site collections shown' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<input type="search" id="inv-search"'
        $html | Should -Match '<button data-filter="all" class="active">All</button>'
        foreach ($key in 1..4) {
            $html | Should -Match ('<button data-filter="{0}">{0}\. ' -f $key)
        }
        $html | Should -Match '<span class="count" id="inv-count">2 of 2 shown</span>'
    }

    It 'shows the context of a site collection in its details' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match 'Web application <strong>Intranet</strong> &middot; Content database <strong>WSS_Content</strong>'
        $html | Should -Match 'Template language <strong>en-US</strong>'
        $html | Should -Match 'Webs <strong>8</strong>'
    }

    It 'shows the blocking reasons first in the compact row and the full reasons, as they are, in the details' {
        $record = [PSCustomObject]@{
            Url = 'https://intranet/sites/team'; Category = 4; CategoryName = 'Blocking'; Score = 5
            Reasons = 'CustomMasterPage=1 (+2); UniquePermissionsCount=7 (+0.07); blocking: UsesFullTrustCode; blocking: HasNoAccessLock'
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject @($record)

        $html | Should -Match '<div class="clamp">blocking: UsesFullTrustCode; blocking: HasNoAccessLock; CustomMasterPage=1 \(\+2\); UniquePermissionsCount=7 \(\+0\.07\)</div>'
        $html | Should -Match '<strong>Reasons</strong> CustomMasterPage=1 \(\+2\); UniquePermissionsCount=7 \(\+0\.07\); blocking: UsesFullTrustCode; blocking: HasNoAccessLock</div>'
    }

    It 'does not show the assessment warnings twice: they end the reasons and have their own box' {
        $warnings = "Site inventory partial: Storage usage could not be read; Webs could not be fully enumerated"
        $record = [PSCustomObject]@{
            Url = 'https://intranet/sites/partial'; Category = 1; CategoryName = 'Simple'; Score = 0.5
            AssessmentStatus = 'Partial'; AssessmentWarnings = $warnings
            Reasons = "TemplateLanguageReviewRequired=1 (+0.5); $warnings"
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject @($record)

        ([regex]::Matches($html, [regex]::Escape($warnings))).Count | Should -Be 1
        $html | Should -Match '<div class="clamp">TemplateLanguageReviewRequired=1 \(\+0\.5\)</div>'
        $html | Should -Match '<strong>Reasons</strong> TemplateLanguageReviewRequired=1 \(\+0\.5\)</div>'
        $html | Should -Match 'Assessment warnings</strong> Site inventory partial'
    }

    It 'shows the warnings in the reasons cell of a row that has no other reason' {
        $record = [PSCustomObject]@{
            InventoryScope = 'WebApplication'; Url = 'https://intranet'; AssessmentStatus = 'Failed'
            AssessmentWarnings = 'Site collection list could not be accessed: Access denied'
            Reasons = 'Site collection list could not be accessed: Access denied'
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject @($record)

        $html | Should -Match '<div class="clamp">Site collection list could not be accessed: Access denied</div>'
        $html | Should -Not -Match '<strong>Reasons</strong>'
        $html | Should -Match 'Assessment warnings</strong> Site collection list could not be accessed: Access denied'
    }

    It 'places the inventory table right after the wave plan, before the detail sections' {
        $withAuthentication = @($script:Sample) + [PSCustomObject]@{
            Url = 'https://intranet/sites/auth'; Category = 1; CategoryName = 'Simple'
            WebAppUrl = 'https://intranet'; AuthenticationZones = 'Default: Windows'
        }
        $html = ConvertTo-SPSInventoryHtml -InputObject $withAuthentication -SolutionMap $script:SolutionMap -ContentTypes @() -ManagedMetadataLists @() -ExternalLists @() -BcsApplications @()

        $wave = $html.IndexOf('id="wave-plan"')
        $inventory = $html.IndexOf('id="inventory-table"')
        $inventory | Should -BeGreaterThan $wave
        foreach ($section in @('farm-solutions', 'authentication', 'web-app-policies', 'content-types', 'managed-metadata', 'external-lists', 'bcs-applications')) {
            $html.IndexOf(('id="{0}"' -f $section)) | Should -BeGreaterThan $inventory
        }
    }

    It 'keeps every field of the former 78-column table in the page, except the few that the CSV and JSON files alone hold' {
        # Every text and numeric field gets a value that can be found in the page.
        $textFields = @(
            'Url', 'Title', 'WebApp', 'ContentDb', 'Template', 'TemplateCompatibilityReason', 'TemplateLanguageTag', 'TemplateLanguageReason',
            'AppInstanceExamples', 'PublishingPageLayoutExamples', 'CustomizedPageExamples', 'CustomPermissionLevelExamples',
            'EmailEnabledListExamples', 'HtmlFileExamples', 'WebAppPolicyExamples', 'ManagedMetadataExamples', 'ExternalListExamples',
            'SubsiteExamples', 'AssessmentStatus', 'AssessmentWarnings', 'AuthenticationModes', 'SiteLockState',
            'LargeListExamples', 'LargeListViewExamples', 'CheckedOutFileExamples', 'FileVersionExamples', 'Reasons'
        )
        $numberFields = @(
            'AppInstanceCount', 'AppWebCount', 'PublishingWebCount', 'PublishingPageCount', 'PublishingPageLayoutCount', 'CustomizedPageCount',
            'CustomPermissionLevelCount', 'EmailEnabledListCount', 'HtmlFileCount', 'WebAppPolicyCount', 'ManagedMetadataListCount',
            'ManagedMetadataColumnCount', 'ManagedMetadataTermSetCount', 'ExternalListCount', 'SharePointAlertCount', 'SubWebCount',
            'SubsiteCount', 'MaxSubsiteDepth', 'IrmEnabledListCount', 'Workflow2010RunningInstanceCount', 'Workflow2013RunningInstanceCount',
            'LargeListCount', 'LargeListViewCount', 'CheckedOutFileCount', 'FileVersionCount', 'ContentTypeCount', 'ListContentTypeBindingCount',
            'SandboxSolutions', 'EventReceivers', 'UniquePermissionsCount'
        )
        $record = [ordered]@{ Category = 4; CategoryName = 'Blocking'; Wave = 4; WaveName = 'Projects / blockers'; WebAppUrl = 'https://intranet' }
        foreach ($field in $textFields) { $record[$field] = "ZZ${field}ZZ" }
        $number = 70000
        foreach ($field in $numberFields) { $record[$field] = ++$number }
        $record['SizeGB'] = 7.25
        $record['Score'] = 8.5
        $record['LastModified'] = [datetime]'2026-01-02'
        # The flags show as a label, whose presence is checked below.
        foreach ($flag in @('IsUnsupportedSiteTemplate', 'TemplateLanguageReviewRequired', 'PublishingInfrastructureEnabled', 'HasFbaZone', 'IsLargeSite', 'IsLockedSite', 'HasNoAccessLock', 'UsesCustomFarmFeature', 'CustomMasterPage', 'UsesFullTrustCode')) {
            $record[$flag] = $true
        }
        foreach ($flag in @('SiteInventoryComplete', 'CustomizationInventoryComplete', 'ContentTypeInventoryComplete')) {
            $record[$flag] = $false
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject @([PSCustomObject]$record)

        # Not checked here, because the CSV and JSON files alone hold them or the page shows them otherwise:
        # InventoryScope (a tag on web application rows), TemplateLanguageLcid (a fallback for a missing
        # language tag), TemplateCompatibility (replaced by the unsupported-template signal) and Wave
        # (a number that is not unique in this record, and a column of the table).
        $missing = @(
            @($textFields) + @($numberFields) | Where-Object {
                $value = if ($record[$_] -is [string]) { [System.Net.WebUtility]::HtmlEncode($record[$_]) } else { [string]$record[$_] }
                $html.IndexOf($value, [System.StringComparison]::Ordinal) -lt 0
            }
        )
        $missing | Should -BeNullOrEmpty
        foreach ($shown in @('7.25', '8.5', '2026-01-02')) {
            $html.IndexOf($shown) | Should -BeGreaterThan -1
        }
        foreach ($label in @('Unsupported template', 'Template language review', 'Publishing infrastructure', 'FBA configured', 'Large site', 'Site lock', 'Custom farm feature', 'Custom master page', 'Full-trust code', 'Site inventory incomplete', 'Customization inventory incomplete', 'Content type inventory incomplete')) {
            $html | Should -Match ('<dt>{0}</dt>' -f $label)
        }
        $html | Should -Match '<th class="num" data-type="num">Wave <span class="arrow">'
    }

    It 'keeps the report small however many content types there are' {
        $types = foreach ($index in 1..600) {
            [PSCustomObject]@{
                SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team'; Scope = 'List'
                ListTitle = "List $index"; ListUrl = "/sites/team/List$index"; Name = "Content type $index"
                ContentTypeId = '0x0100'; ParentContentTypeId = '0x01'; Group = 'Custom'
                FieldCount = 12; FieldTypes = 'Text; Note; Choice'; DocumentTemplateUrl = ''
                Hidden = $false; ReadOnly = $false; Sealed = $false
            }
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -ContentTypes @($types)

        $html | Should -Match '<strong>600</strong> definition/binding row\(s\)'
        $html.Length | Should -BeLessThan 60000
        $html | Should -Not -Match 'Content type 600'
    }

    It 'limits each detail table to MaxDetailRow rows and says where to find the others' {
        $lists = foreach ($index in 1..5) {
            [PSCustomObject]@{
                SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team'; ListTitle = "List $index"; ListUrl = "/sites/team/List$index"
                ListTemplate = 'DocumentLibrary'; ListType = 'DocumentLibrary'; ListItemCount = 1; ItemLastModifiedDate = ''
                ManagedMetadataColumnCount = 1; ManagedMetadataColumns = 'Department'; TermSetIds = ''
                LobSystemInstance = 'Crm'; EntityNamespace = 'Contoso.Crm'; Entity = "Entity $index"
            }
        }
        $applications = foreach ($index in 1..5) {
            [PSCustomObject]@{
                WebApplicationUrls = 'https://intranet'; BdcServiceApplicationId = 'id'; LobSystemName = "Lob $index"
                LobSystemType = 'Wcf'; LobSystemInstances = 'Crm'; EntityCount = 1; LobEntities = 'Contoso.Crm.Account'
            }
        }
        $solutions = foreach ($index in 1..5) {
            [PSCustomObject]@{
                SolutionName = "solution$index.wsp"; Deployed = $true; DeploymentState = 'GlobalDeployed'
                IsCustom = $true; ContainsGlobalAssembly = $true; ContainsCasPolicy = $false
                ContainsWebApplicationResource = $false; IsFullTrustCode = $true
                FeatureCount = 1; FeatureScopes = @('Site'); FeatureIds = @('f1')
            }
        }
        $fullTrustSites = foreach ($index in 1..5) {
            [PSCustomObject]@{ Url = "https://intranet/sites/trust$index"; Category = 4; CategoryName = 'Blocking'; UsesFullTrustCode = $true; Wave = 4; Score = 1 }
        }

        $html = ConvertTo-SPSInventoryHtml -InputObject @($fullTrustSites) -SolutionMap @($solutions) -ManagedMetadataLists @($lists) -ExternalLists @($lists) -BcsApplications @($applications) -MaxDetailRow 2

        ([regex]::Matches($html, '<td>List [0-9]</td>')).Count | Should -Be 4
        ([regex]::Matches($html, '<td>Lob [0-9]</td>')).Count | Should -Be 2
        ([regex]::Matches($html, '<td>solution[0-9]\.wsp</td>')).Count | Should -Be 2
        ([regex]::Matches($html, '<table class="fulltrust">.*?</table>', 'Singleline')[0].Value -split '<tr>').Count - 2 | Should -Be 2
        $html | Should -Match 'Showing the first 2 of 5 rows\. The managed metadata CSV and JSON files hold all the rows\.'
        $html | Should -Match 'Showing the first 2 of 5 rows\. The external lists CSV and JSON files hold all the rows\.'
        $html | Should -Match 'Showing the first 2 of 5 rows\. The BCS CSV and JSON files hold all the rows\.'
        $html | Should -Match 'Showing the first 2 of 5 rows\. The farm solutions CSV and JSON files hold all the rows\.'
        $html | Should -Match 'Showing the first 2 of 5 rows\. The main CSV and JSON files hold all the rows\.'
    }

    It 'shows every row of a detail table that is within the limit, without a note' {
        $applications = @([PSCustomObject]@{
            WebApplicationUrls = 'https://intranet'; BdcServiceApplicationId = 'id'; LobSystemName = 'Lob'
            LobSystemType = 'Wcf'; LobSystemInstances = 'Crm'; EntityCount = 1; LobEntities = 'Contoso.Crm.Account'
        })

        $html = ConvertTo-SPSInventoryHtml -InputObject @() -BcsApplications $applications

        $html | Should -Not -Match 'Showing the first'
    }

    It 'rejects a MaxDetailRow that is not a positive number' {
        { ConvertTo-SPSInventoryHtml -InputObject @() -MaxDetailRow 0 } | Should -Throw
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

    It 'shows the lock state and the IRM-enabled lists in the details of a site' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        $html | Should -Match '<dt>Site lock</dt><dd><span class="sig-value">NoAccess</span></dd>'
        $html | Should -Match '<dt>IRM-enabled lists</dt><dd><span class="sig-value">3</span></dd>'
        # The site that is not locked has no lock line.
        ([regex]::Matches($html, '<dt>Site lock</dt>')).Count | Should -Be 1
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

    It 'shows the large-content, workflow and template signals in the details of a site' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample

        foreach ($label in @('Large site', 'Large lists', 'Large-list views', 'Checked-out files', 'High-version files', 'Workflow 2010', 'Workflow 2013', 'Template compatibility', 'Template language review')) {
            $html | Should -Match ('<dt>{0}</dt>' -f $label)
        }
        $html | Should -Match '<dt>Workflow 2010</dt><dd><span class="sig-value">4 running instance\(s\)</span></dd>'
        $html | Should -Match '<dt>Template compatibility</dt><dd><span class="sig-value">Review</span> <span class="sig-detail">Template &#39;STS#0&#39; requires manual validation\.</span></dd>'
        $html | Should -Match '<dt>Template language review</dt><dd><span class="sig-value">LCID 999999</span>'
        $html | Should -Match 'Documents \(7000\); Records \(5100\)'
        $html | Should -Match 'Documents/All Documents \(7000\)'
    }

    It 'summarizes the content types and leaves the rows to the CSV and JSON files' {
        $site = [PSCustomObject]@{
            Url = 'https://intranet/sites/team'; Category = 1
            ContentTypeCount = 1; ListContentTypeBindingCount = 1
            ContentTypeInventoryComplete = $false
        }
        $types = @(
            [PSCustomObject]@{
                SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team'
                Scope = 'Web'; ListTitle = ''; ListUrl = ''
                Name = 'Contract & Agreement'
                ContentTypeId = '0x01'; ParentContentTypeId = '0x0'; Group = 'Custom'
                FieldCount = 1; FieldTypes = 'Text'; DocumentTemplateUrl = 'a&b.dotx'
                Hidden = $true; ReadOnly = $true; Sealed = $false
            },
            [PSCustomObject]@{
                SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team'
                Scope = 'List'; ListTitle = 'Records <Admin>'; ListUrl = '/sites/team/records?a=1&b=2'
                Name = 'Contract & Agreement'
                ContentTypeId = '0x01'; ParentContentTypeId = '0x0'; Group = 'Custom'
                FieldCount = 1; FieldTypes = 'Text'; DocumentTemplateUrl = 'a&b.dotx'
                Hidden = $false; ReadOnly = $false; Sealed = $false
            }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject @($site) -ContentTypes $types

        $html | Should -Match 'Content types and list bindings'
        $html | Should -Match '<strong>2</strong> definition/binding row\(s\): <strong>1</strong> web definition\(s\) and <strong>1</strong> list binding\(s\), in <strong>1</strong> site collection\(s\)'
        $html | Should -Match 'content types CSV and JSON files hold every one of them'
        $html | Should -Match 'Partial collection'
        $html | Should -Match '<dt>Content type inventory incomplete</dt>'
        $html | Should -Match 'Content types <strong>1</strong> definition\(s\), <strong>1</strong> list binding\(s\)'
        # The rows themselves are not in the page.
        $html | Should -Not -Match 'class="contenttypes"'
        $html | Should -Not -Match 'Records &lt;Admin&gt;'
        $html | Should -Not -Match 'Contract &amp; Agreement'
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
            1..2 | ForEach-Object { [PSCustomObject]@{ AlertType = 'InformationOnly'; Severity = 'Low'; Url = "https://intranet/sites/al$_"; Value = 3; Message = 'Pass this on to the users.'; Remediation = 'Tell the users.'; Reference = '' } }
        )

        $html = ConvertTo-SPSInventoryHtml -InputObject @() -Alert $alerts

        $html | Should -Match '<h2 id="alerts">Alerts and remediation</h2>'
        $html | Should -Match '<a href="#alerts">Alerts</a>'
        $html | Should -Match '<strong>8</strong> alert\(s\) of <strong>4</strong> type\(s\): <strong>2</strong> high, <strong>4</strong> medium and <strong>2</strong> low'
        $html | Should -Match '(?s)<table class="alerts">.*<th>Severity</th><th>Alert</th><th class="num">Affected</th><th>What it means</th><th>What to do</th><th>Reference</th>'
        $html | Should -Match '(?s)<td>InfoPath</td>.*<td>CheckedOutFiles</td>.*<td>FileVersions</td>.*<td>InformationOnly</td>'
        $html | Should -Match '<span class="pill no">Low</span></td><td>InformationOnly</td><td class="num">2</td>'
        $html | Should -Match 'Pass this on to the users\.'
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

    It 'says how many personal sites and site masters were left out, right under the site collection total' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -ExcludedPersonalSiteCount 109 -ExcludedSiteMasterCount 10

        $html | Should -Match '<div class="summary-total"><strong>109</strong> personal site\(s\) and <strong>10</strong> site master\(s\) were left out of this inventory \(Scope in the settings\)</div>'
        $html | Should -Match '(?s)site collection\(s\).*?</div>\s*<div class="summary-total"><strong>109</strong> personal site'
        $html | Should -Match '<strong>\d+</strong> site collection\(s\)'
    }

    It 'reads well when only personal sites were left out' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -ExcludedPersonalSiteCount 3

        $html | Should -Match '<div class="summary-total"><strong>3</strong> personal site\(s\) were left out of this inventory \(Scope in the settings\)</div>'
        $html | Should -Not -Match 'site master'
    }

    It 'reads well when only site masters were left out' {
        $html = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -ExcludedSiteMasterCount 10

        $html | Should -Match '<div class="summary-total"><strong>10</strong> site master\(s\) were left out of this inventory \(Scope in the settings\)</div>'
        $html | Should -Not -Match 'personal site'
    }

    It 'does not mention the Scope when nothing was left out' {
        $default = ConvertTo-SPSInventoryHtml -InputObject $script:Sample
        $zero = ConvertTo-SPSInventoryHtml -InputObject $script:Sample -ExcludedPersonalSiteCount 0 -ExcludedSiteMasterCount 0

        $default | Should -Not -Match 'left out of this inventory'
        $zero | Should -Not -Match 'left out of this inventory'
    }
}
