BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    Add-Type -TypeDefinition @'
using System;
using System.Collections;

public sealed class SPSSiteInventorySiteCollectionThrowAfterOne : IEnumerable
{
    private readonly object first;

    public SPSSiteInventorySiteCollectionThrowAfterOne(object first)
    {
        this.first = first;
    }

    public IEnumerator GetEnumerator()
    {
        return new Enumerator(first);
    }

    private sealed class Enumerator : IEnumerator
    {
        private readonly object first;
        private int state;

        public Enumerator(object first)
        {
            this.first = first;
        }

        public object Current
        {
            get
            {
                if (state == 1) { return first; }
                throw new InvalidOperationException("Enumerator has no current item.");
            }
        }

        public bool MoveNext()
        {
            if (state == 0)
            {
                state = 1;
                return true;
            }
            throw new InvalidOperationException("Access denied while advancing the site collection enumerator.");
        }

        public void Reset()
        {
            state = 0;
        }
    }
}
'@
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
        Mock Get-SPSWebApplicationPolicy -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{
                BrowserFileHandling = 'Strict'; WebAppPolicyCount = 2
                WebAppPolicyExamples = 'CONTOSO\farm: Full Control; CONTOSO\crawl: Full Read'; Policies = @()
            }
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
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }

        $inventory = @(Get-SPSSiteInventory)

        $inventory | Should -HaveCount 2
        $inventory[0].SiteInventoryComplete | Should -BeTrue
        $inventory[0].InventoryScope | Should -Be 'SiteCollection'
        $inventory[0].HasFbaZone | Should -BeTrue
        $inventory[1].AuthenticationZones | Should -Be 'Extranet: FBA'
        Should -Invoke Write-Progress -ModuleName SPSSiteInventory.Common -Times 4 -Exactly
        Should -Invoke Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common -Times 1 -Exactly
    }

    It 'retains a site with partial metadata and marks the inventory incomplete' {
        $root = [PSCustomObject]@{
            Title = 'Team'; WebTemplate = 'STS'; Configuration = 0
            LastItemModifiedDate = [datetime]'2026-01-01'
        }
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/partial'
            RootWeb = $root
            ContentDatabase = [PSCustomObject]@{ Name = 'WSS_Content' }
            Usage = [PSCustomObject]@{ Storage = 1GB }
            AllWebs = @($root)
        }
        $site | Add-Member -MemberType ScriptProperty -Name RootWeb -Value { throw 'Access denied' } -Force
        $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $script:webApp | Add-Member -NotePropertyName Name -NotePropertyValue 'Intranet' -Force
        $script:webApp | Add-Member -NotePropertyName Sites -NotePropertyValue @($site) -Force
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { $script:webApp }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{
                AuthenticationModes = 'Windows'; AuthenticationZones = 'Default: Windows'
                HasFbaZone = $false; AuthenticationReviewRequired = $false
            }
        }
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }

        $inventory = @(Get-SPSSiteInventory)

        $inventory | Should -HaveCount 1
        $inventory[0].Url | Should -Be 'https://intranet.contoso.com/sites/partial'
        $inventory[0].SiteInventoryComplete | Should -BeFalse
        $inventory[0].SiteInventoryWarnings | Should -Match 'Root web metadata could not be fully read'
    }

    It 'keeps an unreadable storage value null and marks the site inventory partial' {
        $root = [PSCustomObject]@{
            Title = 'Team'; WebTemplate = 'STS'; Configuration = 0
            LastItemModifiedDate = [datetime]'2026-01-01'
        }
        $root | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $usage = [PSCustomObject]@{ Storage = 1GB }
        $usage | Add-Member -MemberType ScriptProperty -Name Storage -Value { throw 'Storage getter denied' } -Force
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/storage-unreadable'
            RootWeb = $root
            ContentDatabase = [PSCustomObject]@{ Name = 'WSS_Content' }
            Usage = $usage
            AllWebs = @($root)
        }
        $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $script:webApp | Add-Member -NotePropertyName Name -NotePropertyValue 'Intranet' -Force
        $script:webApp | Add-Member -NotePropertyName Sites -NotePropertyValue @($site) -Force
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { $script:webApp }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{
                AuthenticationModes = 'Windows'; AuthenticationZones = 'Default: Windows'
                HasFbaZone = $false; AuthenticationReviewRequired = $false
            }
        }
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }

        $inventory = @(Get-SPSSiteInventory -ErrorAction SilentlyContinue)

        $inventory | Should -HaveCount 1
        $inventory[0].SizeGB | Should -BeNullOrEmpty
        $inventory[0].SiteInventoryComplete | Should -BeFalse
        $inventory[0].SiteInventoryWarnings | Should -Match 'Storage usage could not be read'
        $inventory[0].SiteInventoryWarnings | Should -Match 'Storage usage is unavailable'
    }

    It 'keeps four decimals of a GB, so that a small site collection is not recorded as 0' {
        $root = [PSCustomObject]@{
            Title = 'Team'; WebTemplate = 'STS'; Configuration = 0
            LastItemModifiedDate = [datetime]'2026-01-01'
        }
        $root | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $sites = foreach ($case in @(@{ Name = 'small'; Bytes = 3MB }, @{ Name = 'large'; Bytes = 150GB })) {
            $site = [PSCustomObject]@{
                Url = "https://intranet.contoso.com/sites/$($case.Name)"
                RootWeb = $root
                ContentDatabase = [PSCustomObject]@{ Name = 'WSS_Content' }
                Usage = [PSCustomObject]@{ Storage = [int64]$case.Bytes }
                AllWebs = @($root)
            }
            $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            $site
        }
        $script:webApp | Add-Member -NotePropertyName Name -NotePropertyValue 'Intranet' -Force
        $script:webApp | Add-Member -NotePropertyName Sites -NotePropertyValue @($sites) -Force
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { $script:webApp }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{
                AuthenticationModes = 'Windows'; AuthenticationZones = 'Default: Windows'
                HasFbaZone = $false; AuthenticationReviewRequired = $false
            }
        }
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }

        $inventory = @(Get-SPSSiteInventory)

        $inventory | Should -HaveCount 2
        $inventory[0].SizeGB | Should -Be 0.0029
        $inventory[1].SizeGB | Should -Be 150
    }

    It 'continues with later web applications when one site collection list is inaccessible' {
        $root = [PSCustomObject]@{
            Title = 'Other web app'; WebTemplate = 'STS'; Configuration = 0
            LastItemModifiedDate = [datetime]'2026-01-01'
        }
        $root | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $site = [PSCustomObject]@{
            Url = 'https://other.contoso.com/sites/team'
            RootWeb = $root
            ContentDatabase = [PSCustomObject]@{ Name = 'WSS_Other' }
            Usage = [PSCustomObject]@{ Storage = 1GB }
            AllWebs = @($root)
        }
        $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }

        $inaccessibleWebApp = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com'
            Name = 'Intranet'
        }
        $inaccessibleWebApp | Add-Member -MemberType ScriptProperty -Name Sites -Value { throw 'Access denied' }

        $availableWebApp = [PSCustomObject]@{
            Url = 'https://other.contoso.com'
            Name = 'Other'
            Sites = @($site)
        }
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { @($inaccessibleWebApp, $availableWebApp) }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{
                AuthenticationModes = 'Windows'; AuthenticationZones = 'Default: Windows'
                HasFbaZone = $false; AuthenticationReviewRequired = $false
            }
        }
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }

        $inventory = @(Get-SPSSiteInventory)

        $inventory | Should -HaveCount 2
        $inventory[0].InventoryScope | Should -Be 'WebApplication'
        $inventory[0].Url | Should -Be 'https://intranet.contoso.com'
        $inventory[0].SiteInventoryComplete | Should -BeFalse
        $inventory[0].SiteInventoryWarnings | Should -Match 'site collection list'
        $inventory[1].Url | Should -Be 'https://other.contoso.com/sites/team'
        $inventory[1].InventoryScope | Should -Be 'SiteCollection'
        $inventory[1].SiteInventoryComplete | Should -BeTrue
        Should -Invoke Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common -Times 2 -Exactly
    }

    It 'retains enumerated sites and reports a lazy site-list enumeration failure' {
        $root = [PSCustomObject]@{
            Title = 'Team'; WebTemplate = 'STS'; Configuration = 0
            LastItemModifiedDate = [datetime]'2026-01-01'
        }
        $root | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            RootWeb = $root
            ContentDatabase = [PSCustomObject]@{ Name = 'WSS_Content' }
            Usage = [PSCustomObject]@{ Storage = 1GB }
            AllWebs = @($root)
        }
        $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $script:webApp = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com'
            Name = 'Intranet'
            Sites = [SPSSiteInventorySiteCollectionThrowAfterOne]::new($site)
        }
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { $script:webApp }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{
                AuthenticationModes = 'Windows'; AuthenticationZones = 'Default: Windows'
                HasFbaZone = $false; AuthenticationReviewRequired = $false
            }
        }
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }

        $inventory = @(Get-SPSSiteInventory)

        $inventory | Should -HaveCount 2
        $inventory[0].Url | Should -Be 'https://intranet.contoso.com/sites/team'
        $inventory[0].SiteInventoryComplete | Should -BeTrue
        $inventory[1].InventoryScope | Should -Be 'WebApplication'
        $inventory[1].SiteInventoryComplete | Should -BeFalse
        $inventory[1].SiteInventoryWarnings | Should -Match 'stopped early after 1 site collection'
        $inventory[1].SiteInventoryWarnings | Should -Match 'Access denied while advancing'
    }

    It 'propagates web application policies and browser file handling to each site and to the failure row' {
        $root = [PSCustomObject]@{
            Title = 'Team'; WebTemplate = 'STS'; Configuration = 0
            LastItemModifiedDate = [datetime]'2026-01-01'
        }
        $root | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            RootWeb = $root
            ContentDatabase = [PSCustomObject]@{ Name = 'WSS_Content' }
            Usage = [PSCustomObject]@{ Storage = 1GB }
            AllWebs = @($root)
        }
        $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $script:webApp | Add-Member -NotePropertyName Name -NotePropertyValue 'Intranet'
        $script:webApp | Add-Member -NotePropertyName Sites -NotePropertyValue @($site)
        $inaccessibleWebApp = [PSCustomObject]@{ Url = 'https://other.contoso.com'; Name = 'Other' }
        $inaccessibleWebApp | Add-Member -MemberType ScriptProperty -Name Sites -Value { throw 'Access denied' }
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { @($script:webApp, $inaccessibleWebApp) }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{ AuthenticationModes = 'Windows'; AuthenticationZones = 'Default: Windows'; HasFbaZone = $false; AuthenticationReviewRequired = $false }
        }
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }

        $inventory = @(Get-SPSSiteInventory)

        $inventory | Should -HaveCount 2
        $inventory[1].InventoryScope | Should -Be 'WebApplication'
        foreach ($record in $inventory) {
            $record.BrowserFileHandling | Should -Be 'Strict'
            $record.WebAppPolicyCount | Should -Be 2
            $record.WebAppPolicyExamples | Should -Be 'CONTOSO\farm: Full Control; CONTOSO\crawl: Full Read'
        }
        $inventory[0].SiteInventoryComplete | Should -BeTrue
        Should -Invoke Get-SPSWebApplicationPolicy -ModuleName SPSSiteInventory.Common -Times 2 -Exactly
    }

    It 'keeps collecting and marks sites partial when the web application policies cannot be read' {
        $root = [PSCustomObject]@{
            Title = 'Team'; WebTemplate = 'STS'; Configuration = 0
            LastItemModifiedDate = [datetime]'2026-01-01'
        }
        $root | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $site = [PSCustomObject]@{
            Url = 'https://intranet.contoso.com/sites/team'
            RootWeb = $root
            ContentDatabase = [PSCustomObject]@{ Name = 'WSS_Content' }
            Usage = [PSCustomObject]@{ Storage = 1GB }
            AllWebs = @($root)
        }
        $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $script:webApp | Add-Member -NotePropertyName Name -NotePropertyValue 'Intranet'
        $script:webApp | Add-Member -NotePropertyName Sites -NotePropertyValue @($site)
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { $script:webApp }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{ AuthenticationModes = 'Windows'; AuthenticationZones = 'Default: Windows'; HasFbaZone = $false; AuthenticationReviewRequired = $false }
        }
        Mock Get-SPSWebApplicationPolicy -ModuleName SPSSiteInventory.Common { throw 'Policy store access denied' }
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }

        $inventory = @(Get-SPSSiteInventory)

        $inventory | Should -HaveCount 1
        $inventory[0].Url | Should -Be 'https://intranet.contoso.com/sites/team'
        $inventory[0].BrowserFileHandling | Should -BeNullOrEmpty
        $inventory[0].WebAppPolicyCount | Should -BeNullOrEmpty
        $inventory[0].SiteInventoryComplete | Should -BeFalse
        $inventory[0].SiteInventoryWarnings | Should -Match 'Web application policies could not be read: Policy store access denied'
        Should -Invoke Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'Could not read the policies of web application' } -Times 1 -Exactly
    }
}
