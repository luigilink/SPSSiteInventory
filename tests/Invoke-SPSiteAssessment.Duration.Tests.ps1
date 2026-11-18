# The assessment times each site collection: the log says how long it took, the result has the durations for the manifest, and the
# end of the log gives the average and the slowest. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function global:Get-SPSite {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }
}

Describe 'Invoke-SPSiteAssessment and the duration of each site collection' {
    It 'gives the duration of each site collection in the order it was read, also for one that failed, and none for a web application failure row' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                if ($Identity -match '/denied$') { throw 'Access denied' }
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                if ($Site.Url -match '/slow$') { Start-Sleep -Milliseconds 400 }
                @{ ContentTypeInventoryComplete = $true; CustomizationInventoryComplete = $true; ContentTypes = @() }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }
            Mock Out-Host { }

            $inventory = @(
                [PSCustomObject]@{ Url = 'https://intranet/sites/slow'; Title = 'Slow'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/b'; Title = 'B'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; Title = 'Denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ InventoryScope = 'WebApplication'; Url = 'https://intranet'; Title = 'Intranet'; WebApp = 'Intranet'; SiteInventoryComplete = $false; SiteInventoryWarnings = 'The list could not be read' }
            )

            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            $duration = @($result.SiteDuration)
            $duration | Should -HaveCount 3
            @($duration | ForEach-Object { $_.Url }) | Should -Be @('https://intranet/sites/slow', 'https://intranet/sites/b', 'https://intranet/sites/denied')
            @($duration | ForEach-Object { $_.AssessmentStatus }) | Should -Be @('Complete', 'Complete', 'Failed')
            $duration[0].Seconds | Should -BeOfType [double]
            $duration[0].Seconds | Should -BeGreaterOrEqual 0.3
            $duration[0].Seconds | Should -BeLessThan 60
            foreach ($row in $duration) { [System.Math]::Round($row.Seconds, 1) | Should -Be $row.Seconds }
            $duration[1].Seconds | Should -BeLessThan 0.3
            $duration[2].Seconds | Should -BeLessThan 0.3
            @($result.Inventory) | Should -HaveCount 4
        }
    }

    It 'logs one line for each site collection, with its number, its duration, its status and its URL, and none for a web application failure row' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                if ($Identity -match '/denied$') { throw 'Access denied' }
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization { @{ ContentTypeInventoryComplete = $true; CustomizationInventoryComplete = $true; ContentTypes = @() } }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }
            Mock Out-Host { }

            $inventory = @(
                [PSCustomObject]@{ Url = 'https://intranet/sites/a'; Title = 'A'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ Url = 'https://intranet/sites/denied'; Title = 'Denied'; SiteInventoryComplete = $true; SiteInventoryWarnings = '' }
                [PSCustomObject]@{ InventoryScope = 'WebApplication'; Url = 'https://intranet'; Title = 'Intranet'; WebApp = 'Intranet'; SiteInventoryComplete = $false; SiteInventoryWarnings = 'The list could not be read' }
            )

            $null = Invoke-SPSiteAssessment -Inventory $inventory -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            Should -Invoke Add-SPSInventoryEvent -Times 1 -Exactly -ParameterFilter { $Level -eq 'Information' -and $Message -cmatch '^Site collection 1/3 done in \d+(\.\d)? s \(Complete\): https://intranet/sites/a$' }
            Should -Invoke Add-SPSInventoryEvent -Times 1 -Exactly -ParameterFilter { $Level -eq 'Information' -and $Message -cmatch '^Site collection 2/3 done in \d+(\.\d)? s \(Failed\): https://intranet/sites/denied$' }
            Should -Invoke Add-SPSInventoryEvent -Times 0 -Exactly -ParameterFilter { $Message -match '^Site collection 3/3' }
            Should -Invoke Add-SPSInventoryEvent -Times 2 -Exactly -ParameterFilter { $Message -match '^Site collection \d+/3 done in' }
        }
    }

    It 'ends the log with the number of site collections, the average and the three slowest, the slowest first and the ties by URL' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization {
                if ($Site.Url -match '/slow$') { Start-Sleep -Milliseconds 400 }
                @{ ContentTypeInventoryComplete = $true; CustomizationInventoryComplete = $true; ContentTypes = @() }
            }
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }
            Mock Out-Host { }

            $inventory = @('d', 'slow', 'c', 'a', 'b') | ForEach-Object { [PSCustomObject]@{ Url = "https://intranet/sites/$_"; Title = $_; SiteInventoryComplete = $true; SiteInventoryWarnings = '' } }

            $null = Invoke-SPSiteAssessment -Inventory $inventory -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            Should -Invoke Add-SPSInventoryEvent -Times 1 -Exactly -ParameterFilter { $Level -eq 'Information' -and $Message -cmatch '^5 site collection\(s\) read, (\d+(\.\d)?) s on average\. The slowest: https://intranet/sites/slow \(0\.[4-9] s\), https://intranet/sites/a \(\d+(\.\d)? s\), https://intranet/sites/b \(\d+(\.\d)? s\)\.$' -and [double]$Matches[1] -lt 0.3 }
        }
    }

    It 'leaves the log out of the duration of a site collection and out of the average, however slow the log is' {
        InModuleScope SPSSiteInventory.Common {
            Mock Get-SPSite {
                $site = [PSCustomObject]@{ Url = $Identity }
                $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                $site
            }
            Mock Get-SPSSiteCustomization { @{ ContentTypeInventoryComplete = $true; CustomizationInventoryComplete = $true; ContentTypes = @() } }
            Mock Add-SPSInventoryEvent { Start-Sleep -Milliseconds 400 }
            Mock Write-Progress { }
            Mock Out-Host { }

            $inventory = @('a', 'b', 'c') | ForEach-Object { [PSCustomObject]@{ Url = "https://intranet/sites/$_"; Title = $_; SiteInventoryComplete = $true; SiteInventoryWarnings = '' } }

            $result = Invoke-SPSiteAssessment -Inventory $inventory -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            # The first and the last site collection have a progress line before them, and each one has a line after it: 5 lines of 0.4 s.
            foreach ($row in @($result.SiteDuration)) { $row.Seconds | Should -BeLessThan 0.3 -Because $row.Url }
            Should -Invoke Add-SPSInventoryEvent -Times 1 -Exactly -ParameterFilter { $Message -match '^3 site collection\(s\) read, (\d+(\.\d)?) s on average\.' -and [double]$Matches[1] -lt 0.3 }
        }
    }

    It 'gives no duration and logs no summary for an empty inventory' {
        InModuleScope SPSSiteInventory.Common {
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }
            Mock Out-Host { }

            $result = Invoke-SPSiteAssessment -Inventory @() -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            @($result.SiteDuration) | Should -HaveCount 0
            Should -Invoke Add-SPSInventoryEvent -Times 0 -Exactly
        }
    }

    It 'adds a property to the result and changes none of the others' {
        InModuleScope SPSSiteInventory.Common {
            Mock Add-SPSInventoryEvent { }
            Mock Write-Progress { }
            Mock Out-Host { }

            $result = Invoke-SPSiteAssessment -Inventory @() -Scoring @{ Weights = @{}; Thresholds = @{}; BlockingSignals = @() }

            @($result.PSObject.Properties.Name) | Should -Be @('Inventory', 'ContentTypes', 'ManagedMetadataLists', 'ExternalLists', 'SharePointAlerts', 'EventReceiverClasses', 'WorkflowAssociations', 'SiteDuration')
        }
    }
}
