# A scan that reached its cap leaves a count that is a lower bound and does not make the assessment partial: the record names the
# signals, the site collection keeps its wave, and a site collection that failed has none.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function global:Get-SPSite {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }
}

Describe 'Invoke-SPSiteAssessment and the lower bounds' {
    It 'carries the lower bound signals of the collector into the record, keeps a site that only reached a cap complete and in its wave, and leaves them empty for a site that failed' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                if ($Identity -match '/denied$') { throw 'Access denied' }
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                @{
                    ContentTypeInventoryComplete = $true
                    CustomizationInventoryComplete = -not ($Site.Url -match '/both$')
                    ContentTypes = @()
                    FileVersionCount = 12
                    LowerBoundSignals = $(if ($Site.Url -match '/(capped|both)$') { 'FileVersionCount; HtmlFileCount' } else { '' })
                }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @(
                [PSCustomObject]@{ Url = 'https://intranet/sites/plain'; Title = 'Plain'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/capped'; Title = 'Capped'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/both'; Title = 'Both'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; Title = 'Denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }
            $waves = @(@{ Wave = 1; Name = 'Quick wins'; Categories = @(1) }, @{ Wave = 2; Name = 'Moderate'; Categories = @(2) }, @{ Wave = 3; Name = 'Complex'; Categories = @(3) }, @{ Wave = 4; Name = 'Blocking'; Categories = @(4) })

            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring
            $plain, $capped, $both, $failed = @(Group-SPSMigrationWave -InputObject $result.Inventory -MigrationWaves $waves)

            $plain.LowerBoundSignals | Should -BeExactly ''
            $plain.AssessmentStatus | Should -Be 'Complete'
            $capped.LowerBoundSignals | Should -BeExactly 'FileVersionCount; HtmlFileCount'
            $capped.AssessmentStatus | Should -Be 'Complete'
            $capped.WaveName | Should -Be 'Quick wins'
            $both.LowerBoundSignals | Should -BeExactly 'FileVersionCount; HtmlFileCount'
            $both.AssessmentStatus | Should -Be 'Partial'
            $both.WaveName | Should -Be 'Needs review'
            $failed.AssessmentStatus | Should -Be 'Failed'
            $failed.PSObject.Properties.Name | Should -Contain 'LowerBoundSignals'
            $failed.LowerBoundSignals | Should -BeExactly ''
        }
    }
}
