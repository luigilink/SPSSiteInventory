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
}
