# The collaboration signals of the collector reach the record of an assessed site, and are empty for a site that failed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function global:Get-SPSite {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }
}

Describe 'Invoke-SPSiteAssessment and the collaboration signals' {
    It 'carries the audience targeting and site notebook signals of the collector into the record, and leaves them empty for a site that failed' {
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
                    CustomizationInventoryComplete = $true
                    ContentTypes = @()
                    AudienceTargetedListCount = 2
                    AudienceTargetedItemCount = 12
                    AudienceTargetedExamples = '/sites/a/Lists/News (7 item(s): Sales)'
                    SiteNotebookCount = 1
                    SiteNotebookExamples = '/sites/a/SiteAssets/Team Notebook'
                }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }

            $inventory = @(
                [PSCustomObject]@{ Url = 'https://intranet/sites/a'; Title = 'A'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; Title = 'Denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
            )
            $scoring = @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring $scoring
            $assessed = $result.Inventory[0]
            $failed = $result.Inventory[1]

            $assessed.AudienceTargetedListCount | Should -Be 2
            $assessed.AudienceTargetedItemCount | Should -Be 12
            $assessed.AudienceTargetedExamples | Should -Be '/sites/a/Lists/News (7 item(s): Sales)'
            $assessed.SiteNotebookCount | Should -Be 1
            $assessed.SiteNotebookExamples | Should -Be '/sites/a/SiteAssets/Team Notebook'
            $failed.AssessmentStatus | Should -Be 'Failed'
            foreach ($field in 'AudienceTargetedListCount', 'AudienceTargetedItemCount', 'AudienceTargetedExamples', 'SiteNotebookCount', 'SiteNotebookExamples') {
                $failed.PSObject.Properties.Name | Should -Contain $field
                $failed.$field | Should -BeNullOrEmpty -Because $field
            }
        }
    }
}
