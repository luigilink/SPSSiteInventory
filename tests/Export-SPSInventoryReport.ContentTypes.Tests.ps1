BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
}

Describe 'Export-SPSInventoryReport content types' {
    BeforeAll {
        # Windows PowerShell 5.1 does not unroll a JSON array in a pipeline, so count with foreach.
        function Get-AlertCount {
            param ($Alerts, [string]$Type, [string]$Url = '')
            $count = 0
            foreach ($alert in $Alerts) {
                if ($alert.AlertType -eq $Type -and (-not $Url -or $alert.Url -eq $Url)) { $count++ }
            }
            return $count
        }

        function Get-RowCount {
            param ($Rows)
            $count = 0
            foreach ($row in $Rows) { $count++ }
            return $count
        }
    }

    It 'writes aligned site CSV, JSON, HTML and content-type CSV/JSON' {
        $sites = @([PSCustomObject]@{
            Url = 'https://intranet/sites/team'; WebApp = 'Intranet'
            InventoryScope = 'SiteCollection'
            HasFbaZone = $true; ContentTypeCount = 1
            Template = 'APP#0'
            IsUnsupportedSiteTemplate = $true
            TemplateCompatibility = 'Unsupported'
            TemplateCompatibilityReason = 'App web templates are not migration targets in SharePoint Online.'
            TemplateLanguageLcid = 1036
            TemplateLanguageTag = 'fr-FR'
            TemplateLanguageReviewRequired = $true
            TemplateLanguageReason = "Template language LCID '1036' is outside SupportedLanguageLcid."
            ListContentTypeBindingCount = 1; ContentTypeInventoryComplete = $true
            Workflow2010Count = 1; Workflow2013Count = 0; InfoPathFormCount = 0
            Workflow2010RunningInstanceCount = 2; Workflow2013RunningInstanceCount = 1
            AppInstanceCount = 3; AppWebCount = 1; AppInstanceExamples = 'Contoso App (/sites/team); Legacy Provider App (/sites/team)'
            PublishingInfrastructureEnabled = $true; PublishingWebCount = 2; PublishingPageCount = 40
            PublishingPageLayoutCount = 3; PublishingPageLayoutExamples = 'ArticleLeft.aspx (30); WelcomeSplash.aspx (10)'
            CustomizedPageCount = 2; CustomizedPageExamples = '/sites/team/default.aspx; /sites/team/sub/default.aspx'
            WebAppUrl = 'https://intranet'; BrowserFileHandling = 'Permissive'
            WebAppPolicyCount = 3; WebAppPolicyExamples = 'CONTOSO\farm: Full Control'
            CustomPermissionLevelCount = 2; CustomPermissionLevelExamples = 'Project Manager (https://intranet/sites/team)'
            EmailEnabledListCount = 1; EmailEnabledListExamples = 'Invoices (/sites/team/Invoices)'
            HtmlFileCount = 4; HtmlFileExamples = '/sites/team/Docs/a.htm'
            IrmEnabledListCount = 2; SiteLockState = 'ReadOnly'; IsLockedSite = $true
            IsLargeSite = $true
            LargeListCount = 1; LargeListExamples = 'Documents (7000)'
            LargeListViewCount = 1; LargeListViewExamples = 'Documents/All Items (7000)'
            CheckedOutFileCount = 3; CheckedOutFileExamples = 'Documents (3)'
            FileVersionCount = 2; FileVersionExamples = '/sites/team/Documents/a.docx (80)'
            UsesFullTrustCode = $true
            AssessmentStatus = 'Complete'; AssessmentWarnings = ''
            Category = 4; CategoryName = 'Blocking'; Wave = 4; Score = 0
            Reasons = 'blocking: HasFbaZone'
        })
        $types = @([PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team'
            Scope = 'List'; ListTitle = 'Legal, & Compliance'; ListUrl = '/sites/team/legal?a=1&b=2'
            ContentTypeId = '0x010100AA'; Name = 'Agreement'; Group = 'Contoso'
            ParentContentTypeId = '0x0101'; FieldCount = 2; FieldTypes = 'Text; DateTime'
            DocumentTemplateUrl = ''; Hidden = $true; ReadOnly = $true; Sealed = $false
        })

        $output = Export-SPSInventoryReport -InputObject $sites -ContentTypes $types -OutputFolder $TestDrive -BaseName 'Test'

        @(Import-Csv $output.CsvPath) | Should -HaveCount 1
        @(Get-Content $output.JsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 1
        (Import-Csv $output.CsvPath)[0].HasFbaZone | Should -Be 'True'
        Test-Path $output.SitesJsonPath | Should -BeTrue
        Test-Path $output.AuthJsonPath | Should -BeTrue
        Test-Path $output.WorkflowsJsonPath | Should -BeTrue
        Test-Path $output.AppsJsonPath | Should -BeTrue
        Test-Path $output.PublishingJsonPath | Should -BeTrue
        Test-Path $output.PermissionsJsonPath | Should -BeTrue
        Test-Path $output.IrmLocksJsonPath | Should -BeTrue
        Test-Path $output.LargeContentJsonPath | Should -BeTrue
        Test-Path $output.AlertsJsonPath | Should -BeTrue
        Test-Path $output.ManifestJsonPath | Should -BeTrue
        @(Get-Content $output.WorkflowsJsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 1
        (Get-Content $output.WorkflowsJsonPath -Raw | ConvertFrom-Json)[0].Workflow2010RunningInstanceCount | Should -Be 2
        (Get-Content $output.WorkflowsJsonPath -Raw | ConvertFrom-Json)[0].Workflow2013RunningInstanceCount | Should -Be 1
        (Get-Content $output.WorkflowsJsonPath -Raw | ConvertFrom-Json)[0].TemplateCompatibility | Should -Be 'Unsupported'
        (Get-Content $output.WorkflowsJsonPath -Raw | ConvertFrom-Json)[0].TemplateLanguageReviewRequired | Should -BeTrue
        @(Get-Content $output.AppsJsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 1
        (Get-Content $output.AppsJsonPath -Raw | ConvertFrom-Json)[0].AppInstanceCount | Should -Be 3
        (Get-Content $output.AppsJsonPath -Raw | ConvertFrom-Json)[0].AppWebCount | Should -Be 1
        @(Get-Content $output.PublishingJsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 1
        $publishing = (Get-Content $output.PublishingJsonPath -Raw | ConvertFrom-Json)[0]
        $publishing.PublishingInfrastructureEnabled | Should -BeTrue
        $publishing.PublishingWebCount | Should -Be 2
        $publishing.PublishingPageCount | Should -Be 40
        $publishing.PublishingPageLayoutCount | Should -Be 3
        $publishing.PublishingPageLayoutExamples | Should -Be 'ArticleLeft.aspx (30); WelcomeSplash.aspx (10)'
        $publishing.CustomizedPageCount | Should -Be 2
        $publishing.CustomizedPageExamples | Should -Be '/sites/team/default.aspx; /sites/team/sub/default.aspx'
        @(Get-Content $output.IrmLocksJsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 1
        @(Get-Content $output.LargeContentJsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 1
        @(Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json) | Should -Not -BeNullOrEmpty
        @((Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json) | Where-Object { $_.AlertType -eq 'UnsupportedSiteTemplate' }).Count | Should -Be 1
        @((Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json) | Where-Object { $_.AlertType -eq 'TemplateLanguageReview' }).Count | Should -Be 1
        @((Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json) | Where-Object { $_.AlertType -eq 'PublishingSite' -and $_.Value -eq 2 }).Count | Should -Be 1
        @((Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json) | Where-Object { $_.AlertType -eq 'PublishingPages' -and $_.Value -eq 40 }).Count | Should -Be 1
        @((Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json) | Where-Object { $_.AlertType -eq 'CustomizedPages' -and $_.Value -eq 2 }).Count | Should -Be 1
        @(Import-Csv $output.ContentTypesCsvPath) | Should -HaveCount 1
        (Import-Csv $output.ContentTypesCsvPath)[0].ListTitle | Should -Be 'Legal, & Compliance'
        (Import-Csv $output.ContentTypesCsvPath)[0].ListUrl | Should -Be '/sites/team/legal?a=1&b=2'
        @(Get-Content $output.ContentTypesJsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 1
        $manifest = Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Files.SitesJson | Should -Be $output.SitesJsonPath
        $manifest.Files.AppsJson | Should -Be $output.AppsJsonPath
        $manifest.Files.PublishingJson | Should -Be $output.PublishingJsonPath
        $manifest.Files.PermissionsJson | Should -Be $output.PermissionsJsonPath
        $permissions = (Get-Content $output.PermissionsJsonPath -Raw | ConvertFrom-Json)[0]
        $permissions.WebAppUrl | Should -Be 'https://intranet'
        $permissions.BrowserFileHandling | Should -Be 'Permissive'
        $permissions.WebAppPolicyCount | Should -Be 3
        $permissions.WebAppPolicyExamples | Should -Be 'CONTOSO\farm: Full Control'
        $permissions.CustomPermissionLevelCount | Should -Be 2
        $permissions.CustomPermissionLevelExamples | Should -Be 'Project Manager (https://intranet/sites/team)'
        $permissions.EmailEnabledListCount | Should -Be 1
        $permissions.EmailEnabledListExamples | Should -Be 'Invoices (/sites/team/Invoices)'
        $permissions.HtmlFileCount | Should -Be 4
        $permissions.HtmlFileExamples | Should -Be '/sites/team/Docs/a.htm'
        $firstRunAlerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json
        Get-AlertCount -Alerts $firstRunAlerts -Type 'CustomPermissionLevels' -Url 'https://intranet/sites/team' | Should -Be 1
        Get-AlertCount -Alerts $firstRunAlerts -Type 'EmailEnabledLists' -Url 'https://intranet/sites/team' | Should -Be 1
        Get-AlertCount -Alerts $firstRunAlerts -Type 'HtmlFiles' -Url 'https://intranet/sites/team' | Should -Be 1
        Get-AlertCount -Alerts $firstRunAlerts -Type 'WebApplicationPolicies' -Url 'https://intranet' | Should -Be 1
        Get-AlertCount -Alerts $firstRunAlerts -Type 'PermissiveBrowserFileHandling' -Url 'https://intranet' | Should -Be 1
        $manifest.Files.LargeContentJson | Should -Be $output.LargeContentJsonPath
        $manifest.Files.ContentTypesJson | Should -Be $output.ContentTypesJsonPath
        $manifest.Summary.AlertCount | Should -BeGreaterThan 0
        (Get-Content $output.HtmlPath -Raw) | Should -Match 'Legal, &amp; Compliance'
        (Get-Content $output.HtmlPath -Raw) | Should -Match '/sites/team/legal\?a=1&amp;b=2'
        (Get-Content $output.HtmlPath -Raw) | Should -Match '(?s)<th>Hidden</th>.*<th>Read only</th>.*<th>Sealed</th>'
    }

    It 'writes a valid empty content-type report instead of dropping the files' {
        $output = Export-SPSInventoryReport -InputObject @() -ContentTypes @() -OutputFolder $TestDrive -BaseName 'Empty'

        (Get-Content $output.ContentTypesCsvPath -TotalCount 1) | Should -Match 'ContentTypeId'
        @(Import-Csv $output.ContentTypesCsvPath) | Should -HaveCount 0
        (Get-Content $output.ContentTypesJsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 0
        Test-Path $output.ManifestJsonPath | Should -BeTrue
        (Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json).Files.ContentTypesJson | Should -Be $output.ContentTypesJsonPath
        (Get-Content $output.HtmlPath -Raw) | Should -Match 'Content types and list bindings'
    }

    It 'does not create content-type files when callers omit the optional parameter' {
        $sites = @([PSCustomObject]@{ Url = 'https://intranet/sites/team'; Category = 1 })

        $output = Export-SPSInventoryReport -InputObject $sites -OutputFolder $TestDrive -BaseName 'Legacy'

        $output.ContentTypesCsvPath | Should -BeNullOrEmpty
        @(Get-ChildItem $TestDrive 'Legacy-contenttypes-*') | Should -HaveCount 0
        Test-Path $output.ManifestJsonPath | Should -BeTrue
        (Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json).Files.ContentTypesJson | Should -BeNullOrEmpty
        (Get-Content $output.HtmlPath -Raw) | Should -Not -Match 'Content types and list bindings'
    }

    It 'writes scope-aware alerts for web-app enumeration failures and failed FBA sites' {
        $records = @(
            [PSCustomObject]@{
                InventoryScope = 'WebApplication'
                Url = 'https://intranet'
                WebAppUrl = 'https://intranet'
                SiteInventoryWarnings = 'Site collection list could not be accessed: Access denied'
                AssessmentStatus = 'Failed'
                AssessmentWarnings = 'Site collection enumeration failed for web application'
                HasFbaZone = $true
            },
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'
                Url = 'https://intranet/sites/failed-fba'
                WebApp = 'Intranet'
                HasFbaZone = $true
                AssessmentStatus = 'Failed'
                AssessmentWarnings = 'Assessment failed: Access denied'
                Category = $null
                Workflow2010RunningInstanceCount = 3
                Workflow2013RunningInstanceCount = 4
                Template = 'CUSTOM#42'
                IsUnsupportedSiteTemplate = $false
                TemplateCompatibility = 'Review'
                TemplateCompatibilityReason = 'Template is not mapped; review compatibility.'
                TemplateLanguageLcid = 999999
                TemplateLanguageReviewRequired = $true
                TemplateLanguageReason = "Template language LCID '999999' is not recognized."
                AppInstanceCount = 2
                AppWebCount = 1
                PublishingInfrastructureEnabled = $true
                PublishingWebCount = 0
                PublishingPageCount = 5
                CustomizedPageCount = 3
                IsLargeSite = $true
                LargeListCount = 1
                LargeListViewCount = 1
                CheckedOutFileCount = 2
                FileVersionCount = 1
            }
        )

        $output = Export-SPSInventoryReport -InputObject $records -OutputFolder $TestDrive -BaseName 'Alerts'
        $alerts = @(Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json)

        @($alerts | Where-Object { $_.AlertType -eq 'WebApplicationEnumerationFailed' -and $_.Url -eq 'https://intranet' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'AssessmentFailed' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'FbaConfigured' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'Workflow2010Running' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'Workflow2013Running' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'TemplateCompatibilityReview' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'TemplateLanguageReview' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'AppInstances' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'AppWebs' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'PublishingSite' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'PublishingPages' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'CustomizedPages' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'LargeSite' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'LargeLists' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'LargeListViews' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'CheckedOutFiles' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'FileVersions' -and $_.Url -eq 'https://intranet/sites/failed-fba' }).Count | Should -Be 1
    }

    It 'does not write publishing alerts when the publishing signals are empty or absent' {
        $records = @(
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/plain'; WebApp = 'Intranet'
                AssessmentStatus = 'Complete'; Category = 1
                PublishingInfrastructureEnabled = $false; PublishingWebCount = 0; PublishingPageCount = 0
                CustomizedPageCount = 0
            },
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/legacy-row'; WebApp = 'Intranet'
                AssessmentStatus = 'Complete'; Category = 1
            }
        )

        $output = Export-SPSInventoryReport -InputObject $records -OutputFolder $TestDrive -BaseName 'NoPublishing'
        # Assign without @() because Windows PowerShell 5.1 does not unroll a JSON array in a pipeline.
        $alerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json
        $rows = Get-Content $output.PublishingJsonPath -Raw | ConvertFrom-Json

        ($alerts | Measure-Object).Count | Should -Be 0
        @($rows).Count | Should -Be 2
    }

    It 'writes web application alerts once per web application, not once per site' {
        $sites = @(
            foreach ($name in @('a', 'b', 'c')) {
                [PSCustomObject]@{
                    InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$name"; WebApp = 'Intranet'; WebAppUrl = 'https://intranet'
                    AssessmentStatus = 'Complete'; Category = 1
                    BrowserFileHandling = 'Permissive'; WebAppPolicyCount = 3; WebAppPolicyExamples = 'CONTOSO\farm: Full Control'
                }
            }
            [PSCustomObject]@{
                InventoryScope = 'WebApplication'; Url = 'https://other'; WebApp = 'Other'; WebAppUrl = 'https://other'
                AssessmentStatus = 'Failed'; Category = $null
                BrowserFileHandling = 'Strict'; WebAppPolicyCount = 1; WebAppPolicyExamples = 'CONTOSO\farm: Full Control'
            }
        )

        $output = Export-SPSInventoryReport -InputObject $sites -OutputFolder $TestDrive -BaseName 'PerWebApp'
        $alerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json

        Get-AlertCount -Alerts $alerts -Type 'WebApplicationPolicies' -Url 'https://intranet' | Should -Be 1
        Get-AlertCount -Alerts $alerts -Type 'WebApplicationPolicies' -Url 'https://other' | Should -Be 1
        Get-AlertCount -Alerts $alerts -Type 'PermissiveBrowserFileHandling' -Url 'https://intranet' | Should -Be 1
        Get-AlertCount -Alerts $alerts -Type 'PermissiveBrowserFileHandling' -Url 'https://other' | Should -Be 0
    }

    It 'keeps the policy values of a web application failure row in the permissions dataset' {
        $records = @(
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/a'; WebApp = 'Intranet'; WebAppUrl = 'https://intranet'
                AssessmentStatus = 'Complete'; Category = 1
                BrowserFileHandling = 'Permissive'; WebAppPolicyCount = 3; WebAppPolicyExamples = 'CONTOSO\farm: Full Control'
            },
            [PSCustomObject]@{
                InventoryScope = 'WebApplication'; Url = 'https://other'; WebApp = 'Other'; WebAppUrl = 'https://other'
                AssessmentStatus = 'Failed'; Category = $null
                BrowserFileHandling = 'Strict'; WebAppPolicyCount = 1; WebAppPolicyExamples = 'CONTOSO\crawl: Full Read'
            }
        )

        $output = Export-SPSInventoryReport -InputObject $records -OutputFolder $TestDrive -BaseName 'FailureRow'
        $rows = Get-Content $output.PermissionsJsonPath -Raw | ConvertFrom-Json
        $failureRow = $null
        $rowCount = 0
        foreach ($row in $rows) {
            $rowCount++
            if ($row.InventoryScope -eq 'WebApplication') { $failureRow = $row }
        }

        $rowCount | Should -Be 2
        $failureRow.WebAppUrl | Should -Be 'https://other'
        $failureRow.BrowserFileHandling | Should -Be 'Strict'
        $failureRow.WebAppPolicyCount | Should -Be 1
        $failureRow.WebAppPolicyExamples | Should -Be 'CONTOSO\crawl: Full Read'
    }

    It 'does not write permission or policy alerts when the signals are empty, Strict or absent' {
        $records = @(
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/plain'; WebApp = 'Intranet'; WebAppUrl = 'https://intranet'
                AssessmentStatus = 'Complete'; Category = 1
                BrowserFileHandling = 'Strict'; WebAppPolicyCount = 0
                CustomPermissionLevelCount = 0; EmailEnabledListCount = 0; HtmlFileCount = 0
            },
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/legacy-row'; WebApp = 'Intranet'
                AssessmentStatus = 'Complete'; Category = 1
            }
        )

        $output = Export-SPSInventoryReport -InputObject $records -OutputFolder $TestDrive -BaseName 'NoPermissions'
        $alerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json
        $rows = Get-Content $output.PermissionsJsonPath -Raw | ConvertFrom-Json

        foreach ($type in @('CustomPermissionLevels', 'EmailEnabledLists', 'HtmlFiles', 'WebApplicationPolicies', 'PermissiveBrowserFileHandling')) {
            Get-AlertCount -Alerts $alerts -Type $type | Should -Be 0
        }
        @($rows).Count | Should -Be 2
    }

    It 'writes the per-list managed metadata CSV and JSON, manifest entries and one alert per site' {
        $sites = @([PSCustomObject]@{
            InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/team'; WebApp = 'Intranet'
            AssessmentStatus = 'Complete'; Category = 2
            ManagedMetadataListCount = 2; ManagedMetadataColumnCount = 3; ManagedMetadataTermSetCount = 2
            ManagedMetadataExamples = 'Legal, & Compliance (Department, Region); Projects (Department)'
        })
        $lists = @(
            [PSCustomObject]@{
                SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team'
                ListTitle = 'Legal, & Compliance'; ListUrl = '/sites/team/legal?a=1&b=2'
                ListTemplate = 'DocumentLibrary'; ListType = 'DocumentLibrary'
                ListItemCount = 12; ItemLastModifiedDate = '2026-03-04 10:20:30'
                ManagedMetadataColumnCount = 2; ManagedMetadataColumns = 'Department; Region'
                TermSetIds = '11111111-1111-1111-1111-111111111111; 22222222-2222-2222-2222-222222222222'
            }
            [PSCustomObject]@{
                SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team/sub'
                ListTitle = 'Projects'; ListUrl = '/sites/team/sub/Projects'
                ListTemplate = 'GenericList'; ListType = 'GenericList'
                ListItemCount = 340; ItemLastModifiedDate = ''
                ManagedMetadataColumnCount = 1; ManagedMetadataColumns = 'Department'
                TermSetIds = '11111111-1111-1111-1111-111111111111'
            }
        )

        $output = Export-SPSInventoryReport -InputObject $sites -ManagedMetadataLists $lists -OutputFolder $TestDrive -BaseName 'MetaData'

        $csvRows = @(Import-Csv $output.ManagedMetadataCsvPath)
        $csvRows | Should -HaveCount 2
        $csvRows[0].ListTitle | Should -Be 'Legal, & Compliance'
        $csvRows[0].ListUrl | Should -Be '/sites/team/legal?a=1&b=2'
        $csvRows[0].ListItemCount | Should -Be '12'
        $csvRows[0].ManagedMetadataColumns | Should -Be 'Department; Region'
        $csvRows[0].TermSetIds | Should -Be '11111111-1111-1111-1111-111111111111; 22222222-2222-2222-2222-222222222222'
        $csvRows[1].WebUrl | Should -Be 'https://intranet/sites/team/sub'
        (Get-Content $output.ManagedMetadataCsvPath -TotalCount 1) | Should -Be '"SiteUrl","WebUrl","ListTitle","ListUrl","ListTemplate","ListType","ListItemCount","ItemLastModifiedDate","ManagedMetadataColumnCount","ManagedMetadataColumns","TermSetIds"'
        $jsonRows = Get-Content $output.ManagedMetadataJsonPath -Raw | ConvertFrom-Json
        Get-RowCount -Rows $jsonRows | Should -Be 2
        $jsonRows[0].ManagedMetadataColumnCount | Should -Be 2
        $jsonRows[0].ListItemCount | Should -Be 12
        $manifest = Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Files.ManagedMetadataCsv | Should -Be $output.ManagedMetadataCsvPath
        $manifest.Files.ManagedMetadataJson | Should -Be $output.ManagedMetadataJsonPath
        $alerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json
        Get-AlertCount -Alerts $alerts -Type 'ManagedMetadataColumns' -Url 'https://intranet/sites/team' | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'ManagedMetadataColumns' })[0].Value | Should -Be 2
        @($alerts | Where-Object { $_.AlertType -eq 'ManagedMetadataColumns' })[0].Severity | Should -Be 'Medium'
        $html = Get-Content $output.HtmlPath -Raw
        $html | Should -Match 'Managed metadata columns by list'
        $html | Should -Match 'Legal, &amp; Compliance'
        (Get-Content $output.SitesJsonPath -Raw | ConvertFrom-Json)[0].ManagedMetadataTermSetCount | Should -Be 2
    }

    It 'writes a valid empty managed metadata report instead of dropping the files' {
        $output = Export-SPSInventoryReport -InputObject @() -ManagedMetadataLists @() -OutputFolder $TestDrive -BaseName 'EmptyMetadata'

        (Get-Content $output.ManagedMetadataCsvPath -TotalCount 1) | Should -Match 'ManagedMetadataColumns'
        @(Import-Csv $output.ManagedMetadataCsvPath) | Should -HaveCount 0
        Get-RowCount -Rows (Get-Content $output.ManagedMetadataJsonPath -Raw | ConvertFrom-Json) | Should -Be 0
        (Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json).Files.ManagedMetadataJson | Should -Be $output.ManagedMetadataJsonPath
        (Get-Content $output.HtmlPath -Raw) | Should -Match 'Managed metadata columns by list'
    }

    It 'does not create managed metadata files when callers omit the optional parameter' {
        $sites = @([PSCustomObject]@{ Url = 'https://intranet/sites/team'; Category = 1 })

        $output = Export-SPSInventoryReport -InputObject $sites -OutputFolder $TestDrive -BaseName 'NoMetadataFiles'

        $output.ManagedMetadataCsvPath | Should -BeNullOrEmpty
        $output.ManagedMetadataJsonPath | Should -BeNullOrEmpty
        @(Get-ChildItem $TestDrive 'NoMetadataFiles-managedmetadata-*') | Should -HaveCount 0
        (Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json).Files.ManagedMetadataJson | Should -BeNullOrEmpty
        (Get-Content $output.HtmlPath -Raw) | Should -Not -Match 'Managed metadata columns by list'
    }

    It 'does not write a managed metadata alert for empty counts, absent signals or web application failure rows' {
        $records = @(
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/plain'; WebApp = 'Intranet'
                AssessmentStatus = 'Complete'; Category = 1; ManagedMetadataListCount = 0
            },
            [PSCustomObject]@{
                InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/legacy-row'; WebApp = 'Intranet'
                AssessmentStatus = 'Complete'; Category = 1
            },
            [PSCustomObject]@{
                InventoryScope = 'WebApplication'; Url = 'https://other'; WebAppUrl = 'https://other'
                AssessmentStatus = 'Failed'; Category = $null; ManagedMetadataListCount = 4
            }
        )

        $output = Export-SPSInventoryReport -InputObject $records -OutputFolder $TestDrive -BaseName 'NoMetadataAlert'
        $alerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json

        Get-AlertCount -Alerts $alerts -Type 'ManagedMetadataColumns' | Should -Be 0
    }
}
