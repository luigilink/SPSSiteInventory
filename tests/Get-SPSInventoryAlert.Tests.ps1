# Behavior tests for Get-SPSInventoryAlert (pure, no farm needed).
BeforeDiscovery {
    # One row per alert a site collection record can raise: the signals that raise it, and what it reports.
    $script:SiteCases = @(
        @{ Type = 'AssessmentFailed'; Severity = 'High'; Signals = @{ AssessmentStatus = 'Failed'; AssessmentWarnings = 'Access denied' }; Value = 'Access denied' }
        @{ Type = 'AssessmentPartial'; Severity = 'Medium'; Signals = @{ AssessmentStatus = 'Partial'; AssessmentWarnings = 'Lists could not be read' }; Value = 'Lists could not be read' }
        @{ Type = 'Workflow2010'; Severity = 'High'; Signals = @{ Workflow2010Count = 2 }; Value = 2 }
        @{ Type = 'Workflow2010Running'; Severity = 'High'; Signals = @{ Workflow2010RunningInstanceCount = 3 }; Value = 3 }
        @{ Type = 'Workflow2013'; Severity = 'High'; Signals = @{ Workflow2013Count = 2 }; Value = 2 }
        @{ Type = 'Workflow2013Running'; Severity = 'High'; Signals = @{ Workflow2013RunningInstanceCount = 4 }; Value = 4 }
        @{ Type = 'AppInstances'; Severity = 'Medium'; Signals = @{ AppInstanceCount = 5 }; Value = 5 }
        @{ Type = 'AppWebs'; Severity = 'Medium'; Signals = @{ AppWebCount = 6 }; Value = 6 }
        @{ Type = 'PublishingSite'; Severity = 'Medium'; Signals = @{ PublishingInfrastructureEnabled = $true; PublishingWebCount = 0 }; Value = 0 }
        @{ Type = 'PublishingSite'; Severity = 'Medium'; Signals = @{ PublishingInfrastructureEnabled = $false; PublishingWebCount = 2 }; Value = 2 }
        @{ Type = 'PublishingPages'; Severity = 'Medium'; Signals = @{ PublishingPageCount = 40 }; Value = 40 }
        @{ Type = 'CustomizedPages'; Severity = 'Medium'; Signals = @{ CustomizedPageCount = 7 }; Value = 7 }
        @{ Type = 'AlternateCssUrl'; Severity = 'Medium'; Signals = @{ AlternateCssUrlCount = 2 }; Value = 2 }
        @{ Type = 'XsltListViews'; Severity = 'Medium'; Signals = @{ XsltListViewCount = 3 }; Value = 3 }
        @{ Type = 'ScriptWebParts'; Severity = 'Medium'; Signals = @{ ScriptWebPartCount = 4 }; Value = 4 }
        @{ Type = 'ModernExperienceOptOut'; Severity = 'Low'; Signals = @{ ClassicExperienceOptOutCount = 1 }; Value = 1 }
        @{ Type = 'ClassicExperienceLists'; Severity = 'Low'; Signals = @{ ClassicExperienceListCount = 5 }; Value = 5 }
        @{ Type = 'CustomPermissionLevels'; Severity = 'Medium'; Signals = @{ CustomPermissionLevelCount = 2 }; Value = 2 }
        @{ Type = 'EmailEnabledLists'; Severity = 'Medium'; Signals = @{ EmailEnabledListCount = 1 }; Value = 1 }
        @{ Type = 'HtmlFiles'; Severity = 'Medium'; Signals = @{ HtmlFileCount = 8 }; Value = 8 }
        @{ Type = 'ManagedMetadataColumns'; Severity = 'Medium'; Signals = @{ ManagedMetadataListCount = 3 }; Value = 3 }
        @{ Type = 'ExternalLists'; Severity = 'High'; Signals = @{ ExternalListCount = 2 }; Value = 2 }
        @{ Type = 'AlertSubscriptions'; Severity = 'Medium'; Signals = @{ SharePointAlertCount = 14 }; Value = 14 }
        @{ Type = 'UnsupportedSiteTemplate'; Severity = 'High'; Signals = @{ IsUnsupportedSiteTemplate = $true; Template = 'APP#0' }; Value = 'APP#0' }
        @{ Type = 'TemplateCompatibilityReview'; Severity = 'Medium'; Signals = @{ TemplateCompatibility = 'Review'; Template = 'CUSTOM#1' }; Value = 'CUSTOM#1' }
        @{ Type = 'TemplateLanguageReview'; Severity = 'Medium'; Signals = @{ TemplateLanguageReviewRequired = $true; TemplateLanguageLcid = 1036 }; Value = 1036 }
        @{ Type = 'InfoPath'; Severity = 'High'; Signals = @{ InfoPathFormCount = 1 }; Value = 1 }
        @{ Type = 'FullTrustCode'; Severity = 'High'; Signals = @{ UsesFullTrustCode = $true }; Value = $true }
        @{ Type = 'FbaConfigured'; Severity = 'High'; Signals = @{ HasFbaZone = $true }; Value = $true }
        @{ Type = 'NoAccessSite'; Severity = 'High'; Signals = @{ IsLockedSite = $true; HasNoAccessLock = $true; SiteLockState = 'NoAccess' }; Value = 'NoAccess' }
        @{ Type = 'LockedSite'; Severity = 'Medium'; Signals = @{ IsLockedSite = $true; HasNoAccessLock = $false; SiteLockState = 'ReadOnly' }; Value = 'ReadOnly' }
        @{ Type = 'IrmEnabledLists'; Severity = 'High'; Signals = @{ IrmEnabledListCount = 2 }; Value = 2 }
        @{ Type = 'LargeSite'; Severity = 'Medium'; Signals = @{ IsLargeSite = $true; SizeGB = 150 }; Value = 150 }
        @{ Type = 'LargeLists'; Severity = 'Medium'; Signals = @{ LargeListCount = 1 }; Value = 1 }
        @{ Type = 'LargeListViews'; Severity = 'Medium'; Signals = @{ LargeListViewCount = 2 }; Value = 2 }
        @{ Type = 'CheckedOutFiles'; Severity = 'Medium'; Signals = @{ CheckedOutFileCount = 9 }; Value = 9 }
        @{ Type = 'FileVersions'; Severity = 'Medium'; Signals = @{ FileVersionCount = 3 }; Value = 3 }
        @{ Type = 'LargeExcelFiles'; Severity = 'Low'; Signals = @{ LargeExcelFileCount = 2 }; Value = 2 }
        @{ Type = 'Subsites'; Severity = 'Low'; Signals = @{ SubsiteCount = 4 }; Value = 4 }
    )
}

BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Get-SPSInventoryAlert is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Catalog = & $script:Module { Get-SPSAlertCatalog }
    $script:OnPremCatalog = & $script:Module { Get-SPSAlertCatalog -TargetMode 'SharePointOnPrem' }

    function Get-Alert {
        param ([object[]]$Record, [hashtable]$Parameters = @{})
        @(& $script:Module { param ($Rows, $Splat) Get-SPSInventoryAlert -InputObject $Rows @Splat } $Record $Parameters)
    }

    function New-Site {
        param ([hashtable]$Signals = @{}, [string]$Url = 'https://intranet/sites/a', [string]$WebApp = 'https://intranet')
        $record = [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = $Url; WebAppUrl = $WebApp; AssessmentStatus = 'Complete' }
        foreach ($name in $Signals.Keys) {
            $record | Add-Member -MemberType NoteProperty -Name $name -Value $Signals[$name] -Force
        }
        return $record
    }
}

Describe 'Get-SPSInventoryAlert' {
    It 'raises <Type> from its signal, with the catalog severity and remediation' -ForEach $script:SiteCases {
        $alerts = Get-Alert -Record @((New-Site -Signals $Signals))

        $alerts | Should -HaveCount 1
        $alerts[0].AlertType | Should -Be $Type
        $alerts[0].Severity | Should -Be $Severity
        $alerts[0].Severity | Should -Be $script:Catalog[$Type].Severity
        $alerts[0].Url | Should -Be 'https://intranet/sites/a'
        $alerts[0].Value | Should -Be $Value
        $alerts[0].Remediation | Should -Be $script:Catalog[$Type].Remediation
        $alerts[0].Reference | Should -Be $script:Catalog[$Type].Reference
    }

    It 'raises <Type> with the catalog of the SharePointOnPrem mode when the mode is given' -ForEach $script:SiteCases {
        $alerts = Get-Alert -Record @((New-Site -Signals $Signals)) -Parameters @{ TargetMode = 'SharePointOnPrem' }

        $alerts | Should -HaveCount 1
        $alerts[0].AlertType | Should -Be $Type
        $alerts[0].Severity | Should -Be $script:OnPremCatalog[$Type].Severity
        $alerts[0].Remediation | Should -Be $script:OnPremCatalog[$Type].Remediation
        $alerts[0].Reference | Should -Be $script:OnPremCatalog[$Type].Reference
        $alerts[0].Value | Should -Be $Value
    }

    It 'frames the reason of each template alert as migration-only in the on-premises mode, and leaves it as it is in the default mode' {
        $record = New-Site -Signals @{
            IsUnsupportedSiteTemplate = $true; Template = 'APP#0'; TemplateCompatibilityReason = 'App webs are not migration targets.'
        }
        $review = New-Site -Signals @{ TemplateCompatibility = 'Review'; Template = 'CUSTOM#1'; TemplateCompatibilityReason = 'Template is not mapped.' }
        $language = New-Site -Signals @{ TemplateLanguageReviewRequired = $true; TemplateLanguageLcid = 999999; TemplateLanguageReason = 'LCID is not recognized.' }
        $parameters = @{ TargetMode = 'SharePointOnPrem' }

        (Get-Alert -Record @($record) -Parameters $parameters)[0].Message | Should -Be 'Migration to SharePoint Online only. App webs are not migration targets.'
        (Get-Alert -Record @($review) -Parameters $parameters)[0].Message | Should -Be 'Migration to SharePoint Online only. Template is not mapped.'
        (Get-Alert -Record @($language) -Parameters $parameters)[0].Message | Should -Be 'Migration to SharePoint Online only. LCID is not recognized.'
        (Get-Alert -Record @($record))[0].Message | Should -Be 'App webs are not migration targets.'
    }

    It 'raises the same alerts in the default mode with or without the mode, and the same types in both modes' {
        $record = New-Site -Signals @{ ExternalListCount = 2; InfoPathFormCount = 1; ScriptWebPartCount = 3; UsesFullTrustCode = $true }

        $default = Get-Alert -Record @($record)
        $explicit = Get-Alert -Record @($record) -Parameters @{ TargetMode = 'SharePointOnline' }
        $onPrem = Get-Alert -Record @($record) -Parameters @{ TargetMode = 'SharePointOnPrem' }

        ($explicit | ConvertTo-Json -Depth 4) | Should -Be ($default | ConvertTo-Json -Depth 4)
        (@($onPrem.AlertType) -join ',') | Should -Be (@($default.AlertType) -join ',')
        ($default | Where-Object AlertType -eq 'ExternalLists').Severity | Should -Be 'High'
        ($onPrem | Where-Object AlertType -eq 'ExternalLists').Severity | Should -Be 'Low'
        ($onPrem | Where-Object AlertType -eq 'FullTrustCode').Severity | Should -Be 'Medium'
        ($onPrem | Where-Object AlertType -eq 'InfoPath').Severity | Should -Be 'High'
    }

    It 'rejects a target mode that is not one of the two, also when there is nothing to alert on' {
        { Get-Alert -Record @() -Parameters @{ TargetMode = 'Online' } } | Should -Throw "*TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'*"
        { Get-Alert -Record @((New-Site)) -Parameters @{ TargetMode = '' } } | Should -Throw "*TargetMode must be*"
    }

    It 'raises no alert of the modern experience for a failed row, whose signals are empty' {
        $row = New-Site -Signals @{
            AssessmentStatus = 'Failed'; AssessmentWarnings = 'Access denied'
            AlternateCssUrlCount = $null; XsltListViewCount = $null; ScriptWebPartCount = $null; ClassicExperienceOptOutCount = $null; ClassicExperienceListCount = $null
        }

        @((Get-Alert -Record @($row)).AlertType) | Should -Be @('AssessmentFailed')
    }

    It 'raises the LargeExcelFiles alert for a single workbook, and none for 0' {
        @((Get-Alert -Record @((New-Site -Signals @{ LargeExcelFileCount = 1 }))).AlertType) | Should -Be @('LargeExcelFiles')
        Get-Alert -Record @((New-Site -Signals @{ LargeExcelFileCount = 0 })) | Should -HaveCount 0
        Get-Alert -Record @((New-Site -Signals @{ LargeExcelFileCount = $null })) | Should -HaveCount 0
    }

    It 'raises the alert of each signal of the modern experience for a single item, and for none when the count is 0' -ForEach @(
        @{ Field = 'AlternateCssUrlCount'; Type = 'AlternateCssUrl' }
        @{ Field = 'XsltListViewCount'; Type = 'XsltListViews' }
        @{ Field = 'ScriptWebPartCount'; Type = 'ScriptWebParts' }
        @{ Field = 'ClassicExperienceOptOutCount'; Type = 'ModernExperienceOptOut' }
        @{ Field = 'ClassicExperienceListCount'; Type = 'ClassicExperienceLists' }
    ) {
        $one = Get-Alert -Record @((New-Site -Signals @{ $Field = 1 }))
        $none = Get-Alert -Record @((New-Site -Signals @{ $Field = 0 }))

        @($one.AlertType) | Should -Be @($Type)
        $one[0].Value | Should -Be 1
        $none | Should -HaveCount 0
    }

    It 'raises nothing for a site collection without any signal' {
        Get-Alert -Record @((New-Site)) | Should -HaveCount 0
    }

    It 'raises the Subsites alert for a single subsite, and not for a site collection that has only its root web' {
        $one = Get-Alert -Record @((New-Site -Signals @{ SubsiteCount = 1; MaxSubsiteDepth = 1 }))
        $none = Get-Alert -Record @((New-Site -Signals @{ SubsiteCount = 0; MaxSubsiteDepth = 0 }))
        $failed = Get-Alert -Record @((New-Site -Signals @{ SubsiteCount = $null; MaxSubsiteDepth = $null }))

        $one | Should -HaveCount 1
        $one[0].AlertType | Should -Be 'Subsites'
        $one[0].Value | Should -Be 1
        $none | Should -HaveCount 0
        $failed | Should -HaveCount 0
    }

    It 'raises nothing for an empty inventory' {
        Get-Alert -Record @() | Should -HaveCount 0
    }

    It 'uses the reason of the record for the template alerts and falls back to the catalog message' {
        $withReason = Get-Alert -Record @((New-Site -Signals @{ IsUnsupportedSiteTemplate = $true; Template = 'APP#0'; TemplateCompatibilityReason = 'App webs are not migration targets.' }))
        $withoutReason = Get-Alert -Record @((New-Site -Signals @{ IsUnsupportedSiteTemplate = $true; Template = 'APP#0' }))
        $review = Get-Alert -Record @((New-Site -Signals @{ TemplateCompatibility = 'Review'; Template = 'CUSTOM#1'; TemplateCompatibilityReason = 'Template is not mapped.' }))
        $language = Get-Alert -Record @((New-Site -Signals @{ TemplateLanguageReviewRequired = $true; TemplateLanguageLcid = 999999; TemplateLanguageReason = 'LCID is not recognized.' }))

        $withReason[0].Message | Should -Be 'App webs are not migration targets.'
        $withoutReason[0].Message | Should -Be $script:Catalog['UnsupportedSiteTemplate'].Message
        $review[0].Message | Should -Be 'Template is not mapped.'
        $language[0].Message | Should -Be 'LCID is not recognized.'
        $language[0].Remediation | Should -Be $script:Catalog['TemplateLanguageReview'].Remediation
    }

    It 'does not review the compatibility of a template that is already unsupported' {
        $alerts = Get-Alert -Record @((New-Site -Signals @{ IsUnsupportedSiteTemplate = $true; TemplateCompatibility = 'Review'; Template = 'APP#0' }))

        @($alerts.AlertType) | Should -Be @('UnsupportedSiteTemplate')
    }

    It 'raises the enumeration failure of a web application and no site alert for its row' {
        $row = [PSCustomObject]@{
            IsLockedSite = $true; HasNoAccessLock = $true; SiteLockState = 'NoAccess'
            InventoryScope = 'WebApplication'; Url = 'https://other'; WebAppUrl = 'https://other'; AssessmentStatus = 'Failed'
            SiteInventoryWarnings = 'Access denied'; Workflow2010Count = 5; Workflow2013Count = 3; InfoPathFormCount = 2; SharePointAlertCount = 4
        }

        $alerts = Get-Alert -Record @($row)

        @($alerts.AlertType) | Should -Be @('WebApplicationEnumerationFailed', 'AssessmentFailed')
        $alerts[0].Url | Should -Be 'https://other'
        $alerts[0].Value | Should -Be 'Access denied'
        $alerts[0].Severity | Should -Be 'High'
    }

    It 'raises one lock alert that follows the lock state, never both' -ForEach @(
        @{ State = 'NoAccess'; NoAccess = $true; Expected = 'NoAccessSite' }
        @{ State = 'NoAdditions'; NoAccess = $false; Expected = 'LockedSite' }
        @{ State = 'ReadOnly'; NoAccess = $false; Expected = 'LockedSite' }
    ) {
        $alerts = Get-Alert -Record @((New-Site -Signals @{ IsLockedSite = $true; HasNoAccessLock = $NoAccess; SiteLockState = $State }))

        @($alerts.AlertType) | Should -Be @($Expected)
        $alerts[0].Value | Should -Be $State
    }

    It 'raises no lock alert for an unlocked site or for a lock state that is unknown' {
        $unlocked = Get-Alert -Record @((New-Site -Signals @{ IsLockedSite = $false; HasNoAccessLock = $false; SiteLockState = 'Unlock' }))
        $unknown = Get-Alert -Record @((New-Site -Signals @{ IsLockedSite = $false; HasNoAccessLock = $false; SiteLockState = 'Unknown' }))

        $unlocked | Should -HaveCount 0
        $unknown | Should -HaveCount 0
    }

    It 'raises the policy and browser file handling alerts once per web application' {
        $first = New-Site -Url 'https://intranet/sites/a' -Signals @{ WebAppPolicyCount = 3; BrowserFileHandling = 'Permissive' }
        $second = New-Site -Url 'https://intranet/sites/b' -Signals @{ WebAppPolicyCount = 3; BrowserFileHandling = 'Permissive' }
        $other = New-Site -Url 'https://extranet/sites/c' -WebApp 'https://extranet' -Signals @{ WebAppPolicyCount = 0; BrowserFileHandling = 'Strict' }

        $alerts = Get-Alert -Record @($first, $second, $other)

        @($alerts | Where-Object { $_.AlertType -eq 'WebApplicationPolicies' }) | Should -HaveCount 1
        @($alerts | Where-Object { $_.AlertType -eq 'PermissiveBrowserFileHandling' }) | Should -HaveCount 1
        ($alerts | Where-Object { $_.AlertType -eq 'WebApplicationPolicies' }).Url | Should -Be 'https://intranet'
        ($alerts | Where-Object { $_.AlertType -eq 'WebApplicationPolicies' }).Value | Should -Be 3
        ($alerts | Where-Object { $_.AlertType -eq 'PermissiveBrowserFileHandling' }).Value | Should -Be 'Permissive'
    }

    It 'raises one BCS alert per LOB system with its first web application, and none without LOB systems' {
        $applications = @(
            [PSCustomObject]@{ WebApplicationUrls = 'https://intranet; https://extranet'; LobSystemName = 'CrmSystem' }
            [PSCustomObject]@{ WebApplicationUrls = 'https://intranet'; LobSystemName = 'SapSystem' }
        )

        $alerts = Get-Alert -Record @() -Parameters @{ BcsApplication = $applications }

        $alerts | Should -HaveCount 2
        $alerts[0].AlertType | Should -Be 'BcsApplication'
        $alerts[0].Url | Should -Be 'https://intranet'
        $alerts[0].Value | Should -Be 'CrmSystem'
        $alerts[1].Value | Should -Be 'SapSystem'
        Get-Alert -Record @() -Parameters @{ BcsApplication = @() } | Should -HaveCount 0
    }

    It 'raises the partial BCS inventory alert only when BCS rows were supplied and the inventory is not complete' {
        (Get-Alert -Record @() -Parameters @{ BcsApplication = @(); BcsInventoryComplete = $false }).AlertType | Should -Be 'BcsInventoryPartial'
        Get-Alert -Record @() -Parameters @{ BcsApplication = @(); BcsInventoryComplete = $true } | Should -HaveCount 0
        Get-Alert -Record @() -Parameters @{ BcsInventoryComplete = $false } | Should -HaveCount 0
    }

    It 'raises one Secure Store alert per target application with its first web application, and none without target applications' {
        $applications = @(
            [PSCustomObject]@{ WebApplicationUrls = 'https://intranet; https://extranet'; Name = 'SapTarget' }
            [PSCustomObject]@{ WebApplicationUrls = 'https://intranet'; Name = 'CrmTarget' }
        )

        $alerts = Get-Alert -Record @() -Parameters @{ SecureStoreApplication = $applications }

        $alerts | Should -HaveCount 2
        $alerts[0].AlertType | Should -Be 'SecureStoreApplication'
        $alerts[0].Severity | Should -Be 'Low'
        $alerts[0].Url | Should -Be 'https://intranet'
        $alerts[0].Value | Should -Be 'SapTarget'
        $alerts[1].Value | Should -Be 'CrmTarget'
        Get-Alert -Record @() -Parameters @{ SecureStoreApplication = @() } | Should -HaveCount 0
    }

    It 'raises the partial Secure Store inventory alert only when rows were supplied and the inventory is not complete' {
        $alert = Get-Alert -Record @() -Parameters @{ SecureStoreApplication = @(); SecureStoreInventoryComplete = $false }

        $alert.AlertType | Should -Be 'SecureStoreInventoryPartial'
        $alert.Severity | Should -Be 'Medium'
        Get-Alert -Record @() -Parameters @{ SecureStoreApplication = @(); SecureStoreInventoryComplete = $true } | Should -HaveCount 0
        Get-Alert -Record @() -Parameters @{ SecureStoreInventoryComplete = $false } | Should -HaveCount 0
    }

    It 'words the Secure Store alert as a migration-only one in the on-premises mode' {
        $applications = @([PSCustomObject]@{ WebApplicationUrls = 'https://intranet'; Name = 'SapTarget' })

        $alert = Get-Alert -Record @() -Parameters @{ SecureStoreApplication = $applications; TargetMode = 'SharePointOnPrem' }

        $alert.Severity | Should -Be 'Low'
        $alert.Message | Should -Match '^Migration to SharePoint Online only\. '
    }

    It 'keeps the order of the alerts: site collections first, then web applications, then BCS, then Secure Store' {
        $site = New-Site -Signals @{ InfoPathFormCount = 1; WebAppPolicyCount = 1 }
        $applications = @([PSCustomObject]@{ WebApplicationUrls = 'https://intranet'; LobSystemName = 'CrmSystem' })
        $targets = @([PSCustomObject]@{ WebApplicationUrls = 'https://intranet'; Name = 'SapTarget' })

        $alerts = Get-Alert -Record @($site) -Parameters @{ BcsApplication = $applications; BcsInventoryComplete = $false; SecureStoreApplication = $targets; SecureStoreInventoryComplete = $false }

        @($alerts.AlertType) | Should -Be @('InfoPath', 'WebApplicationPolicies', 'BcsApplication', 'BcsInventoryPartial', 'SecureStoreApplication', 'SecureStoreInventoryPartial')
    }

    It 'raises exactly the alert types of the catalog and nothing that is not cataloged' -ForEach @(@{ Cases = $script:SiteCases }) {
        $records = @($Cases | ForEach-Object { New-Site -Signals $_.Signals })
        $records += [PSCustomObject]@{ InventoryScope = 'WebApplication'; Url = 'https://other'; WebAppUrl = 'https://other'; AssessmentStatus = 'Failed'; SiteInventoryWarnings = 'Access denied' }
        $records += New-Site -Url 'https://intranet/sites/policy' -WebApp 'https://policy' -Signals @{ WebAppPolicyCount = 2; BrowserFileHandling = 'Permissive' }
        $applications = @([PSCustomObject]@{ WebApplicationUrls = 'https://intranet'; LobSystemName = 'CrmSystem' })
        $targets = @([PSCustomObject]@{ WebApplicationUrls = 'https://intranet'; Name = 'SapTarget' })

        $alerts = Get-Alert -Record $records -Parameters @{ BcsApplication = $applications; BcsInventoryComplete = $false; SecureStoreApplication = $targets; SecureStoreInventoryComplete = $false }
        $raised = @($alerts.AlertType | Sort-Object -Unique)
        $cataloged = @($script:Catalog.Keys | Sort-Object)

        ($raised -join ',') | Should -Be ($cataloged -join ',')
    }
}
