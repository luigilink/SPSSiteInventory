# Behavior tests for the Scope handling of Get-SPSSiteInventory: personal sites and site masters.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    function global:Get-SPWebApplication { throw 'Unmocked SharePoint call' }

    $script:MasterUrl = 'https://sitemaster-f5e4136f-1537-43de-a8af-d47447211c44'

    # A fake site collection that counts how often it is opened, read and disposed.
    function New-FakeSite {
        param ([string]$Url, [string]$Template = 'STS#0', [switch]$UnreadableRootWeb)
        $webTemplate, $configuration = $Template -split '#'
        $root = [PSCustomObject]@{
            Title = "Root of $Url"; WebTemplate = $webTemplate; Configuration = [int]$configuration
            LastItemModifiedDate = [datetime]'2026-01-01'; Language = 1033; Disposed = 0
        }
        $root | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed++ }
        $site = [PSCustomObject]@{
            Url = $Url; Root = $root; Disposed = 0; RootWebReads = 0; DetailReads = 0
        }
        $site | Add-Member -MemberType ScriptProperty -Name RootWeb -Value {
            $this.RootWebReads++
            if ($null -eq $this.Root) { throw 'Access denied to the root web' }
            $this.Root
        }
        if ($UnreadableRootWeb) {
            $site.Root = $null
        }
        $site | Add-Member -MemberType ScriptProperty -Name ContentDatabase -Value { $this.DetailReads++; [PSCustomObject]@{ Name = 'WSS_Content' } }
        $site | Add-Member -MemberType ScriptProperty -Name Usage -Value { $this.DetailReads++; [PSCustomObject]@{ Storage = 1GB } }
        $site | Add-Member -MemberType ScriptProperty -Name AllWebs -Value { $this.DetailReads++; , @($this.Root) }
        $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed++ }
        $site
    }

    function New-FakeWebApplication {
        param ([string]$Url, [object[]]$Site)
        [PSCustomObject]@{ Url = $Url; Name = 'Fake'; Sites = @($Site) }
    }
}

Describe 'Get-SPSSiteInventory scope' {
    BeforeEach {
        $script:team = New-FakeSite -Url 'https://intranet.contoso.com/sites/team'
        $script:personal = New-FakeSite -Url 'https://intranet.contoso.com/personal/alice' -Template 'SPSPERS#10'
        $script:master = New-FakeSite -Url $script:MasterUrl -Template 'SPSPERS#10'
        $script:myHost = New-FakeSite -Url 'https://intranet.contoso.com' -Template 'SPSMSITEHOST#0'
        $script:other = New-FakeSite -Url 'https://intranet.contoso.com/sites/other' -Template 'SITEPAGEPUBLISHING#0'
        $script:allSites = @($script:team, $script:personal, $script:master, $script:myHost, $script:other)
        $script:webApp = New-FakeWebApplication -Url 'https://intranet.contoso.com' -Site $script:allSites

        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { $script:webApp }
        Mock Get-SPSWebApplicationAuthentication -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{
                AuthenticationModes = 'Windows'; AuthenticationZones = 'Default: Windows'
                HasFbaZone = $false; AuthenticationReviewRequired = $false
            }
        }
        Mock Get-SPSWebApplicationPolicy -ModuleName SPSSiteInventory.Common {
            [PSCustomObject]@{ BrowserFileHandling = 'Strict'; WebAppPolicyCount = 0; WebAppPolicyExamples = ''; Policies = @() }
        }
        Mock Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common { }
        Mock Write-Progress -ModuleName SPSSiteInventory.Common { }
    }

    It 'leaves out personal sites and site masters by default and keeps the other site collections' {
        $exclusion = @{}

        $inventory = @(Get-SPSSiteInventory -Exclusion $exclusion)

        @($inventory.Url) | Should -Be @('https://intranet.contoso.com/sites/team', 'https://intranet.contoso.com', 'https://intranet.contoso.com/sites/other')
        $inventory | ForEach-Object { $_.InventoryScope | Should -Be 'SiteCollection' }
        $exclusion.PersonalSites | Should -Be 1
        $exclusion.SiteMasters | Should -Be 1
    }

    It 'keeps the My Site host' {
        $inventory = @(Get-SPSSiteInventory)

        ($inventory | Where-Object { $_.Template -eq 'SPSMSITEHOST#0' }) | Should -HaveCount 1
    }

    It 'leaves out personal sites and site masters when called without any parameter' {
        @(Get-SPSSiteInventory) | Should -HaveCount 3
    }

    It 'skips a site master without reading its root web, and disposes the site' {
        $null = Get-SPSSiteInventory

        $script:master.RootWebReads | Should -Be 0
        $script:master.DetailReads | Should -Be 0
        $script:master.Disposed | Should -Be 1
        $script:master.Root.Disposed | Should -Be 0
    }

    It 'skips a site master whose root web cannot be read, without a warning' {
        $unreadable = New-FakeSite -Url 'https://sitemaster-00000000-1111-2222-3333-444444444444' -UnreadableRootWeb
        $script:webApp.Sites = @($script:team, $unreadable)

        $inventory = @(Get-SPSSiteInventory)

        $inventory | Should -HaveCount 1
        $unreadable.RootWebReads | Should -Be 0
        $unreadable.Disposed | Should -Be 1
        Should -Invoke Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common -ParameterFilter { $Level -eq 'Warning' } -Times 0 -Exactly
    }

    It 'skips a personal site once the template is read, without reading its storage, database or webs, and disposes the root web and the site' {
        $null = Get-SPSSiteInventory

        $script:personal.RootWebReads | Should -Be 1
        $script:personal.DetailReads | Should -Be 0
        $script:personal.Root.Disposed | Should -Be 1
        $script:personal.Disposed | Should -Be 1
    }

    It 'disposes every site collection it visited, and every root web it opened' {
        $null = Get-SPSSiteInventory

        foreach ($site in $script:allSites) {
            $site.Disposed | Should -Be 1 -Because "$($site.Url) must be disposed once"
        }
        foreach ($site in @($script:team, $script:personal, $script:myHost, $script:other)) {
            $site.Root.Disposed | Should -Be 1 -Because "the root web of $($site.Url) must be disposed once"
        }
    }

    It 'adds no record and no warning for the sites that it leaves out' {
        $inventory = @(Get-SPSSiteInventory)

        $inventory | ForEach-Object { $_.SiteInventoryComplete | Should -BeTrue }
        Should -Invoke Add-SPSInventoryEvent -ModuleName SPSSiteInventory.Common -ParameterFilter { $Level -eq 'Warning' } -Times 0 -Exactly
    }

    It 'keeps everything with both switches, as 1.x did' {
        $exclusion = @{}

        $inventory = @(Get-SPSSiteInventory -IncludePersonalSite -IncludeSiteMaster -Exclusion $exclusion)

        $inventory | Should -HaveCount 5
        $exclusion.PersonalSites | Should -Be 0
        $exclusion.SiteMasters | Should -Be 0
        ($inventory | Where-Object { $_.Url -eq $script:MasterUrl }).Template | Should -Be 'SPSPERS#10'
        ($inventory | Where-Object { $_.Url -eq $script:MasterUrl }).SizeGB | Should -Be 1
    }

    It 'keeps a site master when only IncludeSiteMaster is set, and still leaves out the personal sites' {
        $exclusion = @{}

        $inventory = @(Get-SPSSiteInventory -IncludeSiteMaster -Exclusion $exclusion)

        @($inventory.Url) | Should -Contain $script:MasterUrl
        @($inventory.Url) | Should -Not -Contain 'https://intranet.contoso.com/personal/alice'
        $exclusion.PersonalSites | Should -Be 1
        $exclusion.SiteMasters | Should -Be 0
    }

    It 'keeps a personal site when only IncludePersonalSite is set, and still leaves out the site masters' {
        $exclusion = @{}

        $inventory = @(Get-SPSSiteInventory -IncludePersonalSite -Exclusion $exclusion)

        @($inventory.Url) | Should -Contain 'https://intranet.contoso.com/personal/alice'
        @($inventory.Url) | Should -Not -Contain $script:MasterUrl
        $exclusion.PersonalSites | Should -Be 0
        $exclusion.SiteMasters | Should -Be 1
        $script:master.RootWebReads | Should -Be 0
    }

    It 'sets both counts to 0 when the scan starts, then adds up the web applications' {
        $second = New-FakeWebApplication -Url 'https://mysite.contoso.com' -Site @(
            (New-FakeSite -Url 'https://mysite.contoso.com/personal/bob' -Template 'SPSPERS#10'),
            (New-FakeSite -Url 'https://mysite.contoso.com/personal/carol' -Template 'SPSPERS#10'),
            (New-FakeSite -Url 'https://sitemaster-11111111-2222-3333-4444-555555555555' -Template 'SPSPERS#10')
        )
        $apps = @($script:webApp, $second)
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common { $apps }
        $exclusion = @{ PersonalSites = 40; SiteMasters = 7; Other = 'kept' }

        $inventory = @(Get-SPSSiteInventory -Exclusion $exclusion)

        $inventory | Should -HaveCount 3
        $exclusion.PersonalSites | Should -Be 3
        $exclusion.SiteMasters | Should -Be 2
        $exclusion.Other | Should -Be 'kept'
    }

    It 'sets both counts to 0 when nothing is left out' {
        $script:webApp.Sites = @($script:team)
        $exclusion = @{ PersonalSites = 5; SiteMasters = 5 }

        $null = Get-SPSSiteInventory -Exclusion $exclusion

        $exclusion.PersonalSites | Should -Be 0
        $exclusion.SiteMasters | Should -Be 0
    }

    It 'keeps a site whose root web cannot be read, so that an unknown template never excludes it' {
        $unreadable = New-FakeSite -Url 'https://intranet.contoso.com/personal/dave' -UnreadableRootWeb
        $script:webApp.Sites = @($unreadable)
        $exclusion = @{}

        $inventory = @(Get-SPSSiteInventory -Exclusion $exclusion)

        $inventory | Should -HaveCount 1
        $inventory[0].SiteInventoryComplete | Should -BeFalse
        $inventory[0].SiteInventoryWarnings | Should -Match 'Root web metadata could not be fully read'
        $exclusion.PersonalSites | Should -Be 0
    }

    It 'still reports the progress up to the last site collection, left out or not' {
        $null = Get-SPSSiteInventory

        1..5 | ForEach-Object {
            Should -Invoke Write-Progress -ModuleName SPSSiteInventory.Common -ParameterFilter { $Status -like "$_/5: *" } -Times 1 -Exactly
        }
        Should -Invoke Write-Progress -ModuleName SPSSiteInventory.Common -ParameterFilter { $Status -like '5/5: https://intranet.contoso.com/sites/other' } -Times 1 -Exactly
    }

    It 'does not change the records of the site collections that stay' {
        $default = @(Get-SPSSiteInventory)
        $everything = @(Get-SPSSiteInventory -IncludePersonalSite -IncludeSiteMaster)

        foreach ($record in $default) {
            $same = @($everything | Where-Object { $_.Url -eq $record.Url })
            $same | Should -HaveCount 1
            ($record | ConvertTo-Json -Depth 4) | Should -Be ($same[0] | ConvertTo-Json -Depth 4)
        }
        $default[0].SizeGB | Should -Be 1
        $default[0].ContentDb | Should -Be 'WSS_Content'
        $default[0].SubWebCount | Should -Be 1
        $default[0].Template | Should -Be 'STS#0'
    }
}
