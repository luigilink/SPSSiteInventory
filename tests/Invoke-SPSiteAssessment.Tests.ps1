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
                    Workflow2013Count = 0
                    InfoPathFormCount = 0
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
                [PSCustomObject]@{ Url = 'https://intranet/sites/first'; Title = 'First'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; Title = 'Denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/last'; Title = 'Last'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring

            $result.Inventory | Should -HaveCount 3
            $result.Inventory[0].AssessmentStatus | Should -Be 'Complete'
            $result.Inventory[1].AssessmentStatus | Should -Be 'Failed'
            $result.Inventory[1].Category | Should -BeNullOrEmpty
            $result.Inventory[1].Score | Should -BeNullOrEmpty
            $result.Inventory[2].AssessmentStatus | Should -Be 'Complete'
            @($result.ContentTypes).Count | Should -Be 0
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
                    Workflow2013Count = 0
                    InfoPathFormCount = 0
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
                    Workflow2013Count = 0
                    InfoPathFormCount = 0
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
}
