# Behavior tests for Get-SPSBcsApplication (no farm needed: the Business Data Connectivity cmdlet is mocked).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # The module calls the SharePoint cmdlet, which does not exist outside a farm.
    function global:Get-SPBusinessDataCatalogMetadataObject {
        param ($BdcObjectType, $ServiceContext)
        throw 'Unmocked SharePoint call'
    }

    function Get-TestLobSystem {
        param ([string]$Name, [string[]]$Instances = @('Instance'), [string[]]$Entities = @())
        [PSCustomObject]@{
            Name = $Name
            SystemType = 'Wcf'
            LobSystemInstances = @($Instances | ForEach-Object { [PSCustomObject]@{ Name = $_ } })
            Entities = @($Entities | ForEach-Object { [PSCustomObject]@{ Namespace = 'Contoso'; Name = $_ } })
        }
    }

    function Get-TestCatalog {
        param ([int]$Id, [object[]]$LobSystems = @())
        $catalog = [PSCustomObject]@{ Id = $Id; LobSystems = $LobSystems; Calls = 0; Filters = [System.Collections.Generic.List[string]]::new() }
        $catalog | Add-Member -MemberType ScriptMethod -Name GetLobSystems -Value {
            param ($Filter)
            $this.Calls++
            $this.Filters.Add($Filter)
            return , @($this.LobSystems)
        }
        return $catalog
    }

    function Get-TestSite {
        param ([string]$WebApp, [string]$Path)
        [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = "$WebApp$Path"; WebAppUrl = $WebApp }
    }

    # Maps a service context (the site URL) to a catalog, or to an error message when it is a string. The
    # mock reads the map from a global variable: a closure would lose the mocked command's parameters.
    function Set-TestStore {
        param ([hashtable]$Stores)
        $global:SPSTestBcsStores = $Stores
        Mock Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -MockWith {
            $store = $global:SPSTestBcsStores[[string]$ServiceContext]
            if ($store -is [string]) { throw $store }
            $store
        }
    }
}

AfterAll {
    Remove-Variable -Name SPSTestBcsStores -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-SPSBcsApplication' {
    It 'returns one row per LOB system with its type, instances and entities' {
        $catalog = Get-TestCatalog -Id 7 -LobSystems @(
            (Get-TestLobSystem -Name 'SapSystem' -Instances @('SapInstance') -Entities @('Order', 'Material'))
            (Get-TestLobSystem -Name 'CrmSystem' -Instances @('CrmProd', 'CrmDev') -Entities @('Customer'))
        )
        Set-TestStore -Stores @{ 'https://intranet/sites/one' = $catalog }

        $result = Get-SPSBcsApplication -Inventory @((Get-TestSite -WebApp 'https://intranet' -Path '/sites/one'))

        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $result.Applications | Should -HaveCount 2
        $result.Applications[0].LobSystemName | Should -Be 'CrmSystem'
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://intranet'
        $result.Applications[0].LobSystemType | Should -Be 'Wcf'
        $result.Applications[0].LobSystemInstances | Should -Be 'CrmDev; CrmProd'
        $result.Applications[0].EntityCount | Should -Be 1
        $result.Applications[0].LobEntities | Should -Be 'Contoso.Customer'
        $result.Applications[1].LobSystemName | Should -Be 'SapSystem'
        $result.Applications[1].LobEntities | Should -Be 'Contoso.Material; Contoso.Order'
        $catalog.Filters[0] | Should -Be '*'
    }

    It 'uses the first site collection of each web application as the service context' {
        $catalog = Get-TestCatalog -Id 7
        Set-TestStore -Stores @{ 'https://a/sites/first' = $catalog; 'https://b/sites/first' = (Get-TestCatalog -Id 8) }

        $null = Get-SPSBcsApplication -Inventory @(
            (Get-TestSite -WebApp 'https://a' -Path '/sites/first')
            (Get-TestSite -WebApp 'https://a' -Path '/sites/second')
            (Get-TestSite -WebApp 'https://b' -Path '/sites/first')
        )

        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 2 -Exactly
        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $ServiceContext -eq 'https://a/sites/first' -and $BdcObjectType -eq 'Catalog' }
        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 0 -Exactly -ParameterFilter { $ServiceContext -eq 'https://a/sites/second' }
    }

    It 'reads a metadata store shared by several web applications once and lists every web application that sees it' {
        $shared = Get-TestCatalog -Id 7 -LobSystems @((Get-TestLobSystem -Name 'CrmSystem'))
        Set-TestStore -Stores @{ 'https://a/sites/one' = $shared; 'https://b/sites/one' = $shared }

        $result = Get-SPSBcsApplication -Inventory @((Get-TestSite -WebApp 'https://a' -Path '/sites/one'), (Get-TestSite -WebApp 'https://b' -Path '/sites/one'))

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a; https://b'
        $shared.Calls | Should -Be 1
    }

    It 'keeps the LOB systems of distinct metadata stores separate' {
        Set-TestStore -Stores @{
            'https://a/sites/one' = (Get-TestCatalog -Id 7 -LobSystems @((Get-TestLobSystem -Name 'CrmSystem')))
            'https://b/sites/one' = (Get-TestCatalog -Id 8 -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        }

        $result = Get-SPSBcsApplication -Inventory @((Get-TestSite -WebApp 'https://a' -Path '/sites/one'), (Get-TestSite -WebApp 'https://b' -Path '/sites/one'))

        $result.Applications | Should -HaveCount 2
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a'
        $result.Applications[1].WebApplicationUrls | Should -Be 'https://b'
    }

    It 'returns an empty complete result when the metadata store defines no LOB system' {
        Set-TestStore -Stores @{ 'https://a/sites/one' = (Get-TestCatalog -Id 7) }

        $result = Get-SPSBcsApplication -Inventory @((Get-TestSite -WebApp 'https://a' -Path '/sites/one'))

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
    }

    It 'does not call SharePoint for an empty inventory' {
        Set-TestStore -Stores @{}

        $result = Get-SPSBcsApplication -Inventory @()

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 0 -Exactly
    }

    It 'marks a metadata store that cannot be read as incomplete and keeps the other web applications' {
        Set-TestStore -Stores @{
            'https://a/sites/one' = 'Access denied to the metadata store'
            'https://b/sites/one' = (Get-TestCatalog -Id 8 -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        }

        $result = Get-SPSBcsApplication -Inventory @((Get-TestSite -WebApp 'https://a' -Path '/sites/one'), (Get-TestSite -WebApp 'https://b' -Path '/sites/one'))

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].LobSystemName | Should -Be 'SapSystem'
        ($result.Warnings -join ';') | Should -Match "metadata store could not be read for web application 'https://a'"
        ($result.Warnings -join ';') | Should -Match 'Access denied to the metadata store'
    }

    It 'marks a missing or unidentifiable metadata store as incomplete instead of reporting an empty store' {
        $noId = Get-TestCatalog -Id 0
        $noId.Id = $null
        Set-TestStore -Stores @{ 'https://a/sites/one' = $null; 'https://b/sites/one' = $noId }

        $result = Get-SPSBcsApplication -Inventory @((Get-TestSite -WebApp 'https://a' -Path '/sites/one'), (Get-TestSite -WebApp 'https://b' -Path '/sites/one'))

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 0
        ($result.Warnings -join ';') | Should -Match 'metadata store is unavailable'
        ($result.Warnings -join ';') | Should -Match 'metadata store has no readable ID'
    }

    It 'marks an unreadable LOB system as incomplete and keeps the others' {
        $broken = Get-TestLobSystem -Name ''
        Set-TestStore -Stores @{ 'https://a/sites/one' = (Get-TestCatalog -Id 7 -LobSystems @($broken, (Get-TestLobSystem -Name 'CrmSystem'))) }

        $result = Get-SPSBcsApplication -Inventory @((Get-TestSite -WebApp 'https://a' -Path '/sites/one'))

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].LobSystemName | Should -Be 'CrmSystem'
        ($result.Warnings -join ';') | Should -Match "A BCS LOB system could not be read for web application 'https://a'"
        ($result.Warnings -join ';') | Should -Match 'no readable name'
    }

    It 'marks a missing LOB system list as incomplete' {
        $catalog = [PSCustomObject]@{ Id = 7 }
        $catalog | Add-Member -MemberType ScriptMethod -Name GetLobSystems -Value { param ($Filter) return $null }
        Set-TestStore -Stores @{ 'https://a/sites/one' = $catalog }

        $result = Get-SPSBcsApplication -Inventory @((Get-TestSite -WebApp 'https://a' -Path '/sites/one'))

        $result.Complete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match 'list of LOB systems is unavailable'
    }

    It 'reports a web application without any site collection as not read' {
        Set-TestStore -Stores @{ 'https://a/sites/one' = (Get-TestCatalog -Id 7) }
        $failure = [PSCustomObject]@{ InventoryScope = 'WebApplication'; Url = 'https://c'; WebAppUrl = 'https://c' }

        $result = Get-SPSBcsApplication -Inventory @((Get-TestSite -WebApp 'https://a' -Path '/sites/one'), $failure)

        $result.Complete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "not read for web application 'https://c' because it has no site collection"
        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 1 -Exactly
    }

    It 'does not report a web application as unread when another record of it has a site collection' {
        Set-TestStore -Stores @{ 'https://a/sites/one' = (Get-TestCatalog -Id 7) }
        $failure = [PSCustomObject]@{ InventoryScope = 'WebApplication'; Url = 'https://a'; WebAppUrl = 'https://a' }

        $result = Get-SPSBcsApplication -Inventory @($failure, (Get-TestSite -WebApp 'https://a' -Path '/sites/one'))

        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }
}
