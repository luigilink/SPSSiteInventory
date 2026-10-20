BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    function global:Get-SPAuthenticationProvider {
        param($WebApplication, $Zone)
        throw "Unmocked SharePoint call for $WebApplication / $Zone"
    }
    function global:Get-SPWebApplication { throw 'Unmocked SharePoint call' }
}

Describe 'Get-SPSWebApplicationAuthentication' {
    BeforeEach {
        $script:webApp = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com'
            IisSettings = @{ Default = @{}; Extranet = @{} }
            UseClaimsAuthentication = $true
        }
    }

    It 'detects FBA in a non-default zone even with Windows in another zone' {
        Mock Get-SPAuthenticationProvider -ModuleName SPSSiteInventory.Common {
            if ($Zone -eq 'Extranet') {
                [PSCustomObject]@{
                    ClaimProviderName = 'Forms'; DisplayName = 'Forms provider'
                    MembershipProvider = 'ContosoMembers'; RoleProvider = 'ContosoRoles'
                }
            }
            else {
                [PSCustomObject]@{ ClaimProviderName = 'AD'; DisplayName = 'Windows provider' }
            }
        }

        $result = Get-SPSWebApplicationAuthentication -WebApplication $script:webApp

        $result.HasFbaZone | Should -BeTrue
        $result.AuthenticationModes | Should -Be 'FBA; Windows'
        $result.AuthenticationZones | Should -Match 'Default: Windows'
        $result.AuthenticationZones | Should -Match 'Extranet: FBA'
        $result.FbaMembershipProviders | Should -Be 'ContosoMembers'
        $result.FbaRoleProviders | Should -Be 'ContosoRoles'
        $result.AuthenticationReviewRequired | Should -BeFalse
        Should -Invoke Get-SPAuthenticationProvider -ModuleName SPSSiteInventory.Common -Times 2 -Exactly
    }

    It 'reports a federated provider for review without claiming FBA' {
        Mock Get-SPAuthenticationProvider -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{ ClaimProviderName = 'Trusted'; DisplayName = 'Contoso Federation' }
        }

        $result = Get-SPSWebApplicationAuthentication -WebApplication $script:webApp -WarningAction SilentlyContinue

        $result.HasFbaZone | Should -BeFalse
        $result.AuthenticationReviewRequired | Should -BeTrue
        $result.AuthenticationZones | Should -Match 'Federated / custom'
    }

    It 'reports unknown FBA status when a provider cannot be identified' {
        Mock Get-SPAuthenticationProvider -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{ ClaimProviderName = ''; DisplayName = 'Unknown' }
        }

        $result = Get-SPSWebApplicationAuthentication -WebApplication $script:webApp -WarningAction SilentlyContinue

        $result.HasFbaZone | Should -BeNullOrEmpty
        $result.AuthenticationReviewRequired | Should -BeTrue
    }

    It 'does not suppress a provider read failure' {
        Mock Get-SPAuthenticationProvider -ModuleName SPSSiteInventory.Common { throw 'Cannot inspect the zone' }

        { Get-SPSWebApplicationAuthentication -WebApplication $script:webApp } |
            Should -Throw '*Cannot inspect the zone*'
    }

    It 'fails when a claims zone has no readable providers' {
        Mock Get-SPAuthenticationProvider -ModuleName SPSSiteInventory.Common { }

        { Get-SPSWebApplicationAuthentication -WebApplication $script:webApp } |
            Should -Throw '*No authentication providers*'
    }

    It 'does not infer an authentication model when the property is unavailable' {
        $script:webApp.UseClaimsAuthentication = $null

        { Get-SPSWebApplicationAuthentication -WebApplication $script:webApp } |
            Should -Throw '*authentication model*'
    }

    It 'reports classic Windows without querying claims providers' {
        $script:webApp.UseClaimsAuthentication = $false
        Mock Get-SPAuthenticationProvider -ModuleName SPSSiteInventory.Common { throw 'Unexpected provider query' }

        $result = Get-SPSWebApplicationAuthentication -WebApplication $script:webApp

        $result.AuthenticationModes | Should -Be 'Classic Windows'
        $result.HasFbaZone | Should -BeFalse
        Should -Invoke Get-SPAuthenticationProvider -ModuleName SPSSiteInventory.Common -Times 0 -Exactly
    }

    It 'reads authentication once for the web application and propagates it to each site' {
        $root = [PSCustomObject]@{
            Title = 'Team'; WebTemplate = 'STS'; Configuration = 0
            LastItemModifiedDate = [datetime]'2026-01-01'
        }
        $root | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $sites = foreach ($suffix in @('one', 'two')) {
            $site = [PSCustomObject]@{
                Url = "https://intranet.contoso.com/sites/$suffix"
                RootWeb = $root
                ContentDatabase = [PSCustomObject]@{ Name = 'WSS_Content' }
                Usage = [PSCustomObject]@{ Storage = 1GB }
                AllWebs = @($root)
            }
            $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            $site
        }
        $script:webApp | Add-Member -NotePropertyName Name -NotePropertyValue 'Intranet'
        $script:webApp | Add-Member -NotePropertyName Sites -NotePropertyValue @($sites)
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { $script:webApp }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{
                AuthenticationModes = 'FBA; Windows'; AuthenticationZones = 'Extranet: FBA'
                HasFbaZone = $true; AuthenticationReviewRequired = $false
            }
        }

        $inventory = @(Get-SPSSiteInventory)

        $inventory | Should -HaveCount 2
        $inventory[0].HasFbaZone | Should -BeTrue
        $inventory[1].AuthenticationZones | Should -Be 'Extranet: FBA'
        Should -Invoke Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common -Times 1 -Exactly
    }
}
