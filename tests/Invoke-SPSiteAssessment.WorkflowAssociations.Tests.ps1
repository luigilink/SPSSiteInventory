# Behavior tests for the workflow association detail of Invoke-SPSiteAssessment: the rows of every site and the examples in the
# record. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function global:Get-SPSite {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }
}

Describe 'Invoke-SPSiteAssessment workflow associations' {
    BeforeEach {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                param ($Identity)
                if ($Identity -match '/denied$') { throw 'Access denied' }
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                param ($Site)
                $row = [PSCustomObject]@{ SiteUrl = $Site.Url; WebUrl = $Site.Url; Scope = 'Web'; ListTitle = ''; ListUrl = ''; WorkflowName = 'Approval'; Counted = $true; RunningInstances = 2 }
                @{
                    Workflow2010Count = 1
                    Workflow2010RunningInstanceCount = 2
                    Workflow2010Examples = ('Approval (web {0}): 2 running instance(s)' -f $Site.Url)
                    WorkflowAssociations = @($row)
                    CustomizationInventoryComplete = $true
                    ContentTypeInventoryComplete = $true
                }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }
        }
    }

    It 'gives the examples of each site in its record, and keeps them null for a site that failed' {
        $result = InModuleScope SPSSiteInventory.Common {
            $inventory = @(
                [PSCustomObject]@{ Url = 'https://intranet/sites/first'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
            )
            Invoke-SPSiteAssessment -Inventory $inventory -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
        }

        $result.Inventory[0].Workflow2010Count | Should -Be 1
        $result.Inventory[0].Workflow2010Examples | Should -BeExactly 'Approval (web https://intranet/sites/first): 2 running instance(s)'
        $result.Inventory[1].AssessmentStatus | Should -Be 'Failed'
        $result.Inventory[1].Workflow2010Examples | Should -BeNullOrEmpty
    }

    It 'returns the workflow association rows of all the sites that were assessed, in the order of the sites' {
        $result = InModuleScope SPSSiteInventory.Common {
            $inventory = @(
                [PSCustomObject]@{ Url = 'https://intranet/sites/first'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/last'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
            )
            Invoke-SPSiteAssessment -Inventory $inventory -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
        }

        @($result.WorkflowAssociations | ForEach-Object { $_.SiteUrl }) | Should -BeExactly @('https://intranet/sites/first', 'https://intranet/sites/last')
    }

    It 'returns no row for sites without rows' {
        $result = InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSSiteCustomization { @{ Workflow2010Count = 0; CustomizationInventoryComplete = $true; ContentTypeInventoryComplete = $true } }
            Invoke-SPSiteAssessment -Inventory @([PSCustomObject]@{ Url = 'https://intranet/sites/first'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }) -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
        }

        @($result.WorkflowAssociations) | Should -HaveCount 0
        $result.Inventory[0].Workflow2010Examples | Should -BeNullOrEmpty
    }
}
