BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    function global:Get-SPSite {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }

    $script:TestInventory = @(
        [PSCustomObject]@{ Url = 'https://intranet/sites/first'; Title = 'First'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
        [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; Title = 'Denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
        [PSCustomObject]@{ Url = 'https://intranet/sites/last'; Title = 'Last'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
    )
}

Describe 'Invoke-SPSiteAssessment' {
    It 'continues after a site assessment fails and retains an unscored failure record' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                param ($Identity)
                if ($Identity -match '/denied$') {
                    throw 'Access denied'
                }
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                @{
                    Workflow2010Count = 0
                    Workflow2010RunningInstanceCount = 0
                    Workflow2013Count = 0
                    Workflow2013RunningInstanceCount = 0
                    AppInstanceCount = 0
                    AppWebCount = 0
                    AppInstanceExamples = ''
                    PublishingInfrastructureEnabled = $true
                    PublishingWebCount = 2
                    PublishingPageCount = 40
                    PublishingPageLayoutCount = 3
                    PublishingPageLayoutExamples = 'ArticleLeft.aspx (30); WelcomeSplash.aspx (10)'
                    CustomizedPageCount = 1
                    CustomizedPageExamples = '/sites/first/default.aspx'
                    CustomPermissionLevelCount = 2
                    CustomPermissionLevelExamples = 'Project Manager (https://intranet/sites/first)'
                    EmailEnabledListCount = 1
                    EmailEnabledListExamples = 'Invoices (/sites/first/Invoices)'
                    HtmlFileCount = 4
                    HtmlFileExamples = '/sites/first/Docs/a.htm'
                    ManagedMetadataListCount = 2
                    ManagedMetadataColumnCount = 3
                    ManagedMetadataTermSetCount = 2
                    ManagedMetadataExamples = 'Contracts (Department, Region); Projects (Department)'
                    ManagedMetadataLists = @([PSCustomObject]@{ ListTitle = 'Contracts' })
                    ExternalListCount = 2
                    ExternalListExamples = 'Customers (Contoso.Crm.Customer); Orders (Contoso.Sap.Order)'
                    ExternalLists = @([PSCustomObject]@{ ListTitle = 'Customers' }, [PSCustomObject]@{ ListTitle = 'Orders' })
                    SharePointAlertCount = 3
                    SharePointAlerts = @([PSCustomObject]@{ Title = 'Alert A' }, [PSCustomObject]@{ Title = 'Alert B' })
                    SubsiteCount = 3
                    MaxSubsiteDepth = 2
                    SubsiteExamples = 'payroll/2026 (level 2); payroll (level 1)'
                    InfoPathFormCount = 0
                    IrmEnabledListCount = 0
                    IsLargeSite = $false
                    LargeListCount = 0
                    LargeListExamples = ''
                    LargeListViewCount = 0
                    LargeListViewExamples = ''
                    CheckedOutFileCount = 0
                    CheckedOutFileExamples = ''
                    FileVersionCount = 0
                    FileVersionExamples = ''
                    IsLockedSite = $true
                    HasNoAccessLock = $true
                    SiteLockState = 'NoAccess'
                    UsesFullTrustCode = $false
                    UsesCustomFarmFeature = $true
                    SandboxSolutions = 2
                    CustomMasterPage = $true
                    EventReceivers = 3
                    UniquePermissionsCount = 9
                    ContentTypeCount = 0
                    ListContentTypeBindingCount = 0
                    ContentTypeInventoryComplete = $true
                    CustomizationInventoryComplete = $true
                    ContentTypes = @()
                }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @(
                [PSCustomObject]@{ Url = 'https://intranet/sites/first'; Title = 'First'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; Title = 'Denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/last'; Title = 'Last'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring

            $result.Inventory | Should -HaveCount 3
            $result.Inventory[0].AssessmentStatus | Should -Be 'Complete'
            $result.Inventory[0].IrmEnabledListCount | Should -Be 0
            $result.Inventory[0].Workflow2010RunningInstanceCount | Should -Be 0
            $result.Inventory[0].Workflow2013RunningInstanceCount | Should -Be 0
            $result.Inventory[0].AppInstanceCount | Should -Be 0
            $result.Inventory[0].AppWebCount | Should -Be 0
            $result.Inventory[0].AppInstanceExamples | Should -Be ''
            $result.Inventory[0].PublishingInfrastructureEnabled | Should -BeTrue
            $result.Inventory[0].PublishingWebCount | Should -Be 2
            $result.Inventory[0].PublishingPageCount | Should -Be 40
            $result.Inventory[0].PublishingPageLayoutCount | Should -Be 3
            $result.Inventory[0].PublishingPageLayoutExamples | Should -Be 'ArticleLeft.aspx (30); WelcomeSplash.aspx (10)'
            $result.Inventory[0].CustomizedPageCount | Should -Be 1
            $result.Inventory[0].CustomizedPageExamples | Should -Be '/sites/first/default.aspx'
            $result.Inventory[0].CustomPermissionLevelCount | Should -Be 2
            $result.Inventory[0].CustomPermissionLevelExamples | Should -Be 'Project Manager (https://intranet/sites/first)'
            $result.Inventory[0].EmailEnabledListCount | Should -Be 1
            $result.Inventory[0].EmailEnabledListExamples | Should -Be 'Invoices (/sites/first/Invoices)'
            $result.Inventory[0].SubsiteCount | Should -Be 3
            $result.Inventory[0].MaxSubsiteDepth | Should -Be 2
            $result.Inventory[0].SubsiteExamples | Should -Be 'payroll/2026 (level 2); payroll (level 1)'
            $result.Inventory[0].HtmlFileCount | Should -Be 4
            $result.Inventory[0].HtmlFileExamples | Should -Be '/sites/first/Docs/a.htm'
            $result.Inventory[0].ManagedMetadataListCount | Should -Be 2
            $result.Inventory[0].ManagedMetadataColumnCount | Should -Be 3
            $result.Inventory[0].ManagedMetadataTermSetCount | Should -Be 2
            $result.Inventory[0].ManagedMetadataExamples | Should -Be 'Contracts (Department, Region); Projects (Department)'
            $result.Inventory[0].ExternalListCount | Should -Be 2
            $result.Inventory[0].ExternalListExamples | Should -Be 'Customers (Contoso.Crm.Customer); Orders (Contoso.Sap.Order)'
            $result.Inventory[0].SharePointAlertCount | Should -Be 3
            $result.Inventory[0].IsLargeSite | Should -BeFalse
            $result.Inventory[0].IsLockedSite | Should -BeTrue
            $result.Inventory[0].HasNoAccessLock | Should -BeTrue
            $result.Inventory[0].SiteLockState | Should -Be 'NoAccess'
            $result.Inventory[0].UsesCustomFarmFeature | Should -BeTrue
            $result.Inventory[0].SandboxSolutions | Should -Be 2
            $result.Inventory[0].CustomMasterPage | Should -BeTrue
            $result.Inventory[0].EventReceivers | Should -Be 3
            $result.Inventory[0].UniquePermissionsCount | Should -Be 9
            $result.Inventory[1].AssessmentStatus | Should -Be 'Failed'
            $result.Inventory[1].Category | Should -BeNullOrEmpty
            $result.Inventory[1].Score | Should -BeNullOrEmpty
            $result.Inventory[1].IrmEnabledListCount | Should -BeNullOrEmpty
            $result.Inventory[1].Workflow2010RunningInstanceCount | Should -BeNullOrEmpty
            $result.Inventory[1].Workflow2013RunningInstanceCount | Should -BeNullOrEmpty
            $result.Inventory[1].AppInstanceCount | Should -BeNullOrEmpty
            $result.Inventory[1].AppWebCount | Should -BeNullOrEmpty
            $result.Inventory[1].AppInstanceExamples | Should -BeNullOrEmpty
            $result.Inventory[1].PublishingInfrastructureEnabled | Should -BeNullOrEmpty
            $result.Inventory[1].PublishingWebCount | Should -BeNullOrEmpty
            $result.Inventory[1].PublishingPageCount | Should -BeNullOrEmpty
            $result.Inventory[1].PublishingPageLayoutCount | Should -BeNullOrEmpty
            $result.Inventory[1].PublishingPageLayoutExamples | Should -BeNullOrEmpty
            $result.Inventory[1].CustomizedPageCount | Should -BeNullOrEmpty
            $result.Inventory[1].CustomizedPageExamples | Should -BeNullOrEmpty
            $result.Inventory[1].CustomPermissionLevelCount | Should -BeNullOrEmpty
            $result.Inventory[1].CustomPermissionLevelExamples | Should -BeNullOrEmpty
            $result.Inventory[1].EmailEnabledListCount | Should -BeNullOrEmpty
            $result.Inventory[1].EmailEnabledListExamples | Should -BeNullOrEmpty
            $result.Inventory[1].SubsiteCount | Should -BeNullOrEmpty
            $result.Inventory[1].MaxSubsiteDepth | Should -BeNullOrEmpty
            $result.Inventory[1].SubsiteExamples | Should -BeNullOrEmpty
            $result.Inventory[1].HtmlFileCount | Should -BeNullOrEmpty
            $result.Inventory[1].HtmlFileExamples | Should -BeNullOrEmpty
            $result.Inventory[1].ManagedMetadataListCount | Should -BeNullOrEmpty
            $result.Inventory[1].ManagedMetadataColumnCount | Should -BeNullOrEmpty
            $result.Inventory[1].ManagedMetadataTermSetCount | Should -BeNullOrEmpty
            $result.Inventory[1].ManagedMetadataExamples | Should -BeNullOrEmpty
            $result.Inventory[1].ExternalListCount | Should -BeNullOrEmpty
            $result.Inventory[1].ExternalListExamples | Should -BeNullOrEmpty
            $result.Inventory[1].SharePointAlertCount | Should -BeNullOrEmpty
            $result.Inventory[1].IsLargeSite | Should -BeNullOrEmpty
            $result.Inventory[1].IsLockedSite | Should -BeNullOrEmpty
            $result.Inventory[1].HasNoAccessLock | Should -BeNullOrEmpty
            $result.Inventory[1].SiteLockState | Should -BeNullOrEmpty
            $result.Inventory[1].UsesCustomFarmFeature | Should -BeNullOrEmpty
            $result.Inventory[1].SandboxSolutions | Should -BeNullOrEmpty
            $result.Inventory[1].CustomMasterPage | Should -BeNullOrEmpty
            $result.Inventory[1].EventReceivers | Should -BeNullOrEmpty
            $result.Inventory[1].UniquePermissionsCount | Should -BeNullOrEmpty
            $result.Inventory[2].AssessmentStatus | Should -Be 'Complete'
            @($result.ContentTypes).Count | Should -Be 0
            @($result.ManagedMetadataLists).Count | Should -Be 2
            @($result.ExternalLists).Count | Should -Be 4
            @($result.SharePointAlerts).Count | Should -Be 4
            Should -Invoke Get-SPSite -Times 3 -Exactly
            Should -Invoke Get-SPSSiteCustomization -Times 2 -Exactly
            Should -Invoke Write-Progress -Times 4 -Exactly
        }
    }

    It 'marks readable but incomplete site data as partial and preserves its warning' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                @{
                    Workflow2010Count = 0
                    Workflow2010RunningInstanceCount = 0
                    Workflow2013Count = 0
                    Workflow2013RunningInstanceCount = 0
                    AppInstanceCount = 0
                    AppWebCount = 0
                    AppInstanceExamples = ''
                    PublishingInfrastructureEnabled = $false
                    PublishingWebCount = 0
                    PublishingPageCount = 0
                    PublishingPageLayoutCount = 0
                    PublishingPageLayoutExamples = ''
                    CustomizedPageCount = 0
                    CustomizedPageExamples = ''
                    CustomPermissionLevelCount = 0
                    CustomPermissionLevelExamples = ''
                    EmailEnabledListCount = 0
                    EmailEnabledListExamples = ''
                    HtmlFileCount = 0
                    HtmlFileExamples = ''
                    InfoPathFormCount = 0
                    IrmEnabledListCount = 0
                    IsLargeSite = $false
                    LargeListCount = 0
                    LargeListExamples = ''
                    LargeListViewCount = 0
                    LargeListViewExamples = ''
                    CheckedOutFileCount = 0
                    CheckedOutFileExamples = ''
                    FileVersionCount = 0
                    FileVersionExamples = ''
                    IsLockedSite = $false
                    SiteLockState = 'Unlock'
                    UsesFullTrustCode = $false
                    ContentTypeCount = 0
                    ListContentTypeBindingCount = 0
                    ContentTypeInventoryComplete = $false
                    CustomizationInventoryComplete = $false
                    ContentTypes = @()
                }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @(
                [PSCustomObject]@{
                    Url = 'https://intranet/sites/partial'; Title = 'Partial'
                    SiteInventoryComplete = $false; SiteInventoryWarnings = 'Root web metadata unreadable'
                }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring

            $result.Inventory | Should -HaveCount 1
            $result.Inventory[0].AssessmentStatus | Should -Be 'Partial'
            $result.Inventory[0].AssessmentWarnings | Should -Match 'Root web metadata unreadable'
            $result.Inventory[0].AssessmentWarnings | Should -Match 'Customization inventory partial'
            $result.Inventory[0].ContentTypeInventoryComplete | Should -BeFalse
        }
    }

    It 'preserves collector warnings in the exported assessment warning text' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                Write-Warning -Message "Lists could not be fully enumerated on '$($Site.Url)': Access denied"
                @{
                    Workflow2010Count = 0
                    Workflow2010RunningInstanceCount = 0
                    Workflow2013Count = 0
                    Workflow2013RunningInstanceCount = 0
                    AppInstanceCount = 0
                    AppWebCount = 0
                    AppInstanceExamples = ''
                    PublishingInfrastructureEnabled = $false
                    PublishingWebCount = 0
                    PublishingPageCount = 0
                    PublishingPageLayoutCount = 0
                    PublishingPageLayoutExamples = ''
                    CustomizedPageCount = 0
                    CustomizedPageExamples = ''
                    CustomPermissionLevelCount = 0
                    CustomPermissionLevelExamples = ''
                    EmailEnabledListCount = 0
                    EmailEnabledListExamples = ''
                    HtmlFileCount = 0
                    HtmlFileExamples = ''
                    InfoPathFormCount = 0
                    IrmEnabledListCount = 0
                    IsLargeSite = $false
                    LargeListCount = 0
                    LargeListExamples = ''
                    LargeListViewCount = 0
                    LargeListViewExamples = ''
                    CheckedOutFileCount = 0
                    CheckedOutFileExamples = ''
                    FileVersionCount = 0
                    FileVersionExamples = ''
                    IsLockedSite = $false
                    SiteLockState = 'Unlock'
                    UsesFullTrustCode = $false
                    ContentTypeCount = 0
                    ListContentTypeBindingCount = 0
                    ContentTypeInventoryComplete = $false
                    CustomizationInventoryComplete = $false
                    ContentTypes = @()
                }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @(
                [PSCustomObject]@{
                    Url = 'https://intranet/sites/warning'; Title = 'Warning'
                    SiteInventoryComplete = $true; SiteInventoryWarnings = ''
                }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring

            $result.Inventory[0].AssessmentStatus | Should -Be 'Partial'
            $result.Inventory[0].AssessmentWarnings | Should -Match 'Lists could not be fully enumerated'
            $result.Inventory[0].AssessmentWarnings | Should -Match 'Access denied'
        }
    }

    It 'flags large sites from configured size thresholds during assessment' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                @{
                    Workflow2010Count = 0
                    Workflow2010RunningInstanceCount = 0
                    Workflow2013Count = 0
                    Workflow2013RunningInstanceCount = 0
                    AppInstanceCount = 0
                    AppWebCount = 0
                    AppInstanceExamples = ''
                    PublishingInfrastructureEnabled = $false
                    PublishingWebCount = 0
                    PublishingPageCount = 0
                    PublishingPageLayoutCount = 0
                    PublishingPageLayoutExamples = ''
                    CustomizedPageCount = 0
                    CustomizedPageExamples = ''
                    CustomPermissionLevelCount = 0
                    CustomPermissionLevelExamples = ''
                    EmailEnabledListCount = 0
                    EmailEnabledListExamples = ''
                    HtmlFileCount = 0
                    HtmlFileExamples = ''
                    InfoPathFormCount = 0
                    IrmEnabledListCount = 0
                    IsLargeSite = $false
                    LargeListCount = 0
                    LargeListExamples = ''
                    LargeListViewCount = 0
                    LargeListViewExamples = ''
                    CheckedOutFileCount = 0
                    CheckedOutFileExamples = ''
                    FileVersionCount = 0
                    FileVersionExamples = ''
                    IsLockedSite = $false
                    SiteLockState = 'Unlock'
                    UsesFullTrustCode = $false
                    ContentTypeCount = 0
                    ListContentTypeBindingCount = 0
                    ContentTypeInventoryComplete = $true
                    CustomizationInventoryComplete = $true
                    ContentTypes = @()
                }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @(
                [PSCustomObject]@{
                    Url = 'https://intranet/sites/large'; Title = 'Large'
                    SiteInventoryComplete = $true; SiteInventoryWarnings = ''
                    SizeGB = 150
                }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring -LargeContentThresholds @{ LargeSiteSizeGB = 100 }

            $result.Inventory[0].IsLargeSite | Should -BeTrue
        }
    }

    It 'invokes the private assessment helper from outside the module without requiring an export' {
        $module = Get-Module -Name SPSSiteInventory.Common
        $inventory = [System.Object[]]@()
        $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

        $result = & $module {
            param ($Items, $ScoringRules)
            Invoke-SPSiteAssessment -Inventory $Items -Scoring $ScoringRules
        } $inventory $scoring

        @($result.Inventory).Count | Should -Be 0
        @($result.ContentTypes).Count | Should -Be 0
    }

    It 'retains a web-application enumeration failure without attempting a site read' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite { throw 'A web-application failure is not a site URL' }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @(
                [PSCustomObject]@{
                    InventoryScope = 'WebApplication'
                    Url = 'https://intranet'; WebApp = 'Intranet'
                    Title = 'Site collection enumeration failed'
                    SiteInventoryComplete = $false
                    SiteInventoryWarnings = 'Site collection list could not be accessed: Access denied'
                }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring

            $result.Inventory[0].AssessmentStatus | Should -Be 'Failed'
            $result.Inventory[0].AssessmentWarnings | Should -Match 'Access denied'
            $result.Inventory[0].CategoryName | Should -Be 'Not assessed'
            Should -Invoke Get-SPSite -Times 0 -Exactly
        }
    }

    It 'scans HTML files only for permissive web applications and passes the web application fields through' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                param ($Identity)
                if ($Identity -match '/denied$') {
                    throw 'Access denied'
                }
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                @{
                    ContentTypeInventoryComplete = $true
                    CustomizationInventoryComplete = $true
                    ContentTypes = @()
                    CustomPermissionLevelCount = 0
                }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @(
                [PSCustomObject]@{
                    Url = 'https://legacy/sites/a'; Title = 'A'; SiteInventoryComplete = $true; SiteInventoryWarnings = ''
                    BrowserFileHandling = 'Permissive'; WebAppPolicyCount = 3; WebAppPolicyExamples = 'CONTOSO\farm: Full Control'
                }
                [PSCustomObject]@{
                    Url = 'https://modern/sites/b'; Title = 'B'; SiteInventoryComplete = $true; SiteInventoryWarnings = ''
                    BrowserFileHandling = 'Strict'; WebAppPolicyCount = 1; WebAppPolicyExamples = 'CONTOSO\farm: Full Control'
                }
                [PSCustomObject]@{
                    Url = 'https://legacy/sites/denied'; Title = 'Denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = ''
                    BrowserFileHandling = 'Permissive'; WebAppPolicyCount = 3; WebAppPolicyExamples = 'CONTOSO\farm: Full Control'
                }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring -PermissionLevels @{ BuiltInNames = @('Affichage seul') }

            Should -Invoke Get-SPSSiteCustomization -Times 1 -Exactly -ParameterFilter { $Site.Url -eq 'https://legacy/sites/a' -and $ScanHtmlFile }
            Should -Invoke Get-SPSSiteCustomization -Times 1 -Exactly -ParameterFilter { $Site.Url -eq 'https://modern/sites/b' -and -not $ScanHtmlFile }
            Should -Invoke Get-SPSSiteCustomization -Times 2 -Exactly -ParameterFilter { $PermissionLevels.BuiltInNames -contains 'Affichage seul' }
            $result.Inventory[0].BrowserFileHandling | Should -Be 'Permissive'
            $result.Inventory[0].WebAppPolicyCount | Should -Be 3
            $result.Inventory[0].WebAppPolicyExamples | Should -Be 'CONTOSO\farm: Full Control'
            $result.Inventory[1].BrowserFileHandling | Should -Be 'Strict'
            $result.Inventory[2].AssessmentStatus | Should -Be 'Failed'
            $result.Inventory[2].BrowserFileHandling | Should -Be 'Permissive'
            $result.Inventory[2].WebAppPolicyCount | Should -Be 3
        }
    }

    It 'passes the SharePoint alert settings to the collector of every site' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                @{ ContentTypeInventoryComplete = $true; CustomizationInventoryComplete = $true; ContentTypes = @() }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @(
                [PSCustomObject]@{ Url = 'https://intranet/sites/a'; Title = 'A'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/b'; Title = 'B'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            $null = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring -SharePointAlertSettings @{ IncludeUserLogin = $false }

            Should -Invoke Get-SPSSiteCustomization -Times 2 -Exactly -ParameterFilter { $SharePointAlertSettings.IncludeUserLogin -eq $false }
        }
    }

    It 'rejects invalid SharePoint alert settings before it reads any site' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite { throw 'No site should be read.' }
            Mock Get-SPSSiteCustomization { @{} }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @([PSCustomObject]@{ Url = 'https://intranet/sites/a'; Title = 'A'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' })
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            { Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring -SharePointAlertSettings @{ IncludeUserLogin = 'no' } } | Should -Throw -ExpectedMessage '*SharePointAlerts.IncludeUserLogin must be*'

            Should -Invoke Get-SPSite -Times 0 -Exactly
            Should -Invoke Get-SPSSiteCustomization -Times 0 -Exactly
        }
    }
}
