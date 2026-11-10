# Behavior tests for the event receiver detail of Invoke-SPSiteAssessment: the rows of every site, the examples in the record
# and the index of the packages that goes to the collector. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function global:Get-SPSite {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }
}

Describe 'Invoke-SPSiteAssessment event receivers' {
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
                $row = [PSCustomObject]@{ SiteUrl = $Site.Url; Assembly = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'; AssemblyName = 'Contoso.Intranet'; Class = 'Contoso.Intranet.ItemReceiver'; ReceiverCount = 3 }
                @{
                    EventReceivers = 3
                    EventReceiverExamples = ('Contoso.Intranet / Contoso.Intranet.ItemReceiver: 3 receiver(s) on 1 list(s) at {0}' -f $Site.Url)
                    EventReceiverClasses = @($row)
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

        $result.Inventory[0].EventReceivers | Should -Be 3
        $result.Inventory[0].EventReceiverExamples | Should -Be 'Contoso.Intranet / Contoso.Intranet.ItemReceiver: 3 receiver(s) on 1 list(s) at https://intranet/sites/first'
        $result.Inventory[1].AssessmentStatus | Should -Be 'Failed'
        $result.Inventory[1].EventReceiverExamples | Should -BeNullOrEmpty
    }

    It 'returns the event receiver rows of all the sites that were assessed' {
        $result = InModuleScope SPSSiteInventory.Common {
            $inventory = @(
                [PSCustomObject]@{ Url = 'https://intranet/sites/first'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/last'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
            )
            Invoke-SPSiteAssessment -Inventory $inventory -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
        }

        @($result.EventReceiverClasses | ForEach-Object { $_.SiteUrl }) | Should -Be @('https://intranet/sites/first', 'https://intranet/sites/last')
    }

    It 'returns no row for sites without rows' {
        $result = InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSSiteCustomization { @{ EventReceivers = 0; CustomizationInventoryComplete = $true; ContentTypeInventoryComplete = $true } }
            Invoke-SPSiteAssessment -Inventory @([PSCustomObject]@{ Url = 'https://intranet/sites/first'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }) -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
        }

        @($result.EventReceiverClasses) | Should -HaveCount 0
        $result.Inventory[0].EventReceiverExamples | Should -BeNullOrEmpty
    }

    It 'gives the index of the packages to the collector, and nothing when there is none' {
        InModuleScope SPSSiteInventory.Common {
            $index = @{ 'contoso.intranet' = @() }
            $inventory = @([PSCustomObject]@{ Url = 'https://intranet/sites/first'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' })
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            $null = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring -SolutionAssemblyIndex $index
            Should -Invoke Get-SPSSiteCustomization -Times 1 -Exactly -ParameterFilter { $null -ne $SolutionAssemblyIndex -and $SolutionAssemblyIndex.ContainsKey('contoso.intranet') }

            $null = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring
            Should -Invoke Get-SPSSiteCustomization -Times 1 -Exactly -ParameterFilter { $null -eq $SolutionAssemblyIndex }
        }
    }
}
