# Invoke-SPSiteAssessment gives the target mode to the scoring: the same site is named after the question that is asked.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function global:Get-SPSite {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }

    $script:Inventory = @(
        [PSCustomObject]@{ Url = 'https://intranet/sites/code'; Title = 'Code'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
    )
    $script:Scoring = @{
        Weights         = @{ UsesFullTrustCode = 4.0 }
        Thresholds      = @{ Moderate = 1.0; Complex = 6.0 }
        BlockingSignals = @()
    }
}

AfterAll {
    Remove-Item -Path 'function:global:Get-SPSite' -ErrorAction SilentlyContinue
}

Describe 'Invoke-SPSiteAssessment and the target mode' {
    BeforeEach {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                @{ UsesFullTrustCode = $true; CustomizationInventoryComplete = $true; ContentTypeInventoryComplete = $true; ContentTypes = @() }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }
        }
    }

    It 'names the category after the migration when the mode is not given' {
        $result = InModuleScope SPSSiteInventory.Common -Parameters @{ Inventory = $script:Inventory; Scoring = $script:Scoring } {
            param ($Inventory, $Scoring)
            Invoke-SPSiteAssessment -Inventory $Inventory -Scoring $Scoring
        }

        $result.Inventory[0].Category | Should -Be 2
        $result.Inventory[0].CategoryName | Should -Be 'Moderate'
    }

    It 'names the category after the modernization with SharePointOnPrem, and keeps its number and its score' {
        $result = InModuleScope SPSSiteInventory.Common -Parameters @{ Inventory = $script:Inventory; Scoring = $script:Scoring } {
            param ($Inventory, $Scoring)
            Invoke-SPSiteAssessment -Inventory $Inventory -Scoring $Scoring -TargetMode 'SharePointOnPrem'
        }

        $result.Inventory[0].Category | Should -Be 2
        $result.Inventory[0].CategoryName | Should -Be 'Light remediation'
        $result.Inventory[0].Score | Should -Be 4
    }

    It 'keeps the status of a site that could not be assessed, in both modes' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite { throw 'Access denied' }
        }

        foreach ($mode in 'SharePointOnline', 'SharePointOnPrem') {
            $result = InModuleScope SPSSiteInventory.Common -Parameters @{ Inventory = $script:Inventory; Scoring = $script:Scoring; Mode = $mode } {
                param ($Inventory, $Scoring, $Mode)
                Invoke-SPSiteAssessment -Inventory $Inventory -Scoring $Scoring -TargetMode $Mode
            }

            $result.Inventory[0].AssessmentStatus | Should -Be 'Failed'
            $result.Inventory[0].CategoryName | Should -Be 'Not assessed'
        }
    }

    It 'refuses a mode that is not one of the two before it reads a site' {
        $run = {
            InModuleScope SPSSiteInventory.Common -Parameters @{ Inventory = $script:Inventory; Scoring = $script:Scoring } {
                param ($Inventory, $Scoring)
                Invoke-SPSiteAssessment -Inventory $Inventory -Scoring $Scoring -TargetMode 'OnPrem'
            }
        }

        $run | Should -Throw "TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'."
        Should -Invoke -ModuleName SPSSiteInventory.Common Get-SPSite -Times 0 -Exactly
    }
}
