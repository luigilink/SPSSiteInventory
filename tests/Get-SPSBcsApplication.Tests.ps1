# Behavior tests for Get-SPSBcsApplication (no farm needed: the SharePoint commands are mocked).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # The module calls SharePoint commands, which do not exist outside a farm.
    function global:Get-SPWebApplication {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }
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

    function Get-TestWebApplication {
        param ([string]$Url, [string]$ContextError = '')
        [PSCustomObject]@{ Url = $Url; ContextError = $ContextError }
    }

    # Mocks the farm: the web applications, and a store (or an error message when it is a string) per
    # service context. The mocks read global variables: a closure would lose the mocked parameters.
    function Set-TestFarm {
        param ([object[]]$WebApplications, [hashtable]$Stores = @{})
        $global:SPSTestBcsWebApplications = $WebApplications
        $global:SPSTestBcsStores = $Stores
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common -MockWith {
            if ($Identity) { return @($global:SPSTestBcsWebApplications | Where-Object { $_.Url -eq $Identity }) }
            $global:SPSTestBcsWebApplications
        }
        Mock Get-SPSWebApplicationServiceContext -ModuleName SPSSiteInventory.Common -MockWith {
            if ($WebApplication.ContextError) { throw $WebApplication.ContextError }
            'context:' + $WebApplication.Url
        }
        Mock Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -MockWith {
            $store = $global:SPSTestBcsStores[[string]$ServiceContext]
            if ($store -is [string]) { throw $store }
            $store
        }
    }
}

AfterAll {
    Remove-Variable -Name SPSTestBcsWebApplications, SPSTestBcsStores -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-SPSBcsApplication' {
    It 'returns one row per LOB system with its type, instances and entities' {
        $catalog = Get-TestCatalog -Id 7 -LobSystems @(
            (Get-TestLobSystem -Name 'SapSystem' -Instances @('SapInstance') -Entities @('Order', 'Material'))
            (Get-TestLobSystem -Name 'CrmSystem' -Instances @('CrmProd', 'CrmDev') -Entities @('Customer'))
        )
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://intranet')) -Stores @{ 'context:https://intranet' = $catalog }

        $result = Get-SPSBcsApplication

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
        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $BdcObjectType -eq 'Catalog' }
    }

    It 'reads every web application through its own service context, including one without any site collection' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a'), (Get-TestWebApplication -Url 'https://empty')) -Stores @{
            'context:https://a' = (Get-TestCatalog -Id 7 -LobSystems @((Get-TestLobSystem -Name 'CrmSystem')))
            'context:https://empty' = (Get-TestCatalog -Id 8 -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        }

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeTrue
        $result.Applications | Should -HaveCount 2
        $result.Applications[1].WebApplicationUrls | Should -Be 'https://empty'
        Should -Invoke Get-SPSWebApplicationServiceContext -ModuleName SPSSiteInventory.Common -Times 2 -Exactly
        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $ServiceContext -eq 'context:https://empty' }
    }

    It 'reads only the requested web applications' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a'), (Get-TestWebApplication -Url 'https://b')) -Stores @{
            'context:https://a' = (Get-TestCatalog -Id 7)
            'context:https://b' = (Get-TestCatalog -Id 8 -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        }

        $result = Get-SPSBcsApplication -WebApplicationUrl 'https://b'

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://b'
        Should -Invoke Get-SPWebApplication -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $Identity -eq 'https://b' }
        Should -Invoke Get-SPSWebApplicationServiceContext -ModuleName SPSSiteInventory.Common -Times 1 -Exactly
        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 0 -Exactly -ParameterFilter { $ServiceContext -eq 'context:https://a' }
    }

    It 'reads a metadata store shared by several web applications once and lists every web application that sees it' {
        $shared = Get-TestCatalog -Id 7 -LobSystems @((Get-TestLobSystem -Name 'CrmSystem'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a'), (Get-TestWebApplication -Url 'https://b')) -Stores @{
            'context:https://a' = $shared
            'context:https://b' = $shared
        }

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a; https://b'
        $shared.Calls | Should -Be 1
    }

    It 'keeps the LOB systems of distinct metadata stores separate' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a'), (Get-TestWebApplication -Url 'https://b')) -Stores @{
            'context:https://a' = (Get-TestCatalog -Id 7 -LobSystems @((Get-TestLobSystem -Name 'CrmSystem')))
            'context:https://b' = (Get-TestCatalog -Id 8 -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        }

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 2
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a'
        $result.Applications[1].WebApplicationUrls | Should -Be 'https://b'
    }

    It 'returns an empty complete result when the metadata store defines no LOB system' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a')) -Stores @{ 'context:https://a' = (Get-TestCatalog -Id 7) }

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
    }

    It 'does not call the Business Data Connectivity service when the farm has no web application' {
        Set-TestFarm -WebApplications @()

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 0 -Exactly
    }

    It 'marks a metadata store that cannot be read as incomplete and keeps the other web applications' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a'), (Get-TestWebApplication -Url 'https://b')) -Stores @{
            'context:https://a' = 'Access denied to the metadata store'
            'context:https://b' = (Get-TestCatalog -Id 8 -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        }

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].LobSystemName | Should -Be 'SapSystem'
        ($result.Warnings -join ';') | Should -Match "metadata store could not be read for web application 'https://a'"
        ($result.Warnings -join ';') | Should -Match 'Access denied to the metadata store'
    }

    It 'marks a web application whose service context cannot be created as incomplete and keeps the others' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -ContextError 'No proxy group'), (Get-TestWebApplication -Url 'https://b')) -Stores @{
            'context:https://b' = (Get-TestCatalog -Id 8 -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        }

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        ($result.Warnings -join ';') | Should -Match "web application 'https://a': No proxy group"
        Should -Invoke Get-SPBusinessDataCatalogMetadataObject -ModuleName SPSSiteInventory.Common -Times 0 -Exactly -ParameterFilter { $ServiceContext -eq 'context:https://a' }
    }

    It 'marks a web application without a readable URL as incomplete without calling SharePoint for it' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url ''), (Get-TestWebApplication -Url 'https://b')) -Stores @{
            'context:https://b' = (Get-TestCatalog -Id 8)
        }

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "web application '\(unknown web application\)': The web application URL could not be read"
        Should -Invoke Get-SPSWebApplicationServiceContext -ModuleName SPSSiteInventory.Common -Times 1 -Exactly
    }

    It 'marks a missing or unidentifiable metadata store as incomplete instead of reporting an empty store' {
        $noId = Get-TestCatalog -Id 0
        $noId.Id = $null
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a'), (Get-TestWebApplication -Url 'https://b')) -Stores @{
            'context:https://a' = $null
            'context:https://b' = $noId
        }

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 0
        ($result.Warnings -join ';') | Should -Match 'metadata store is unavailable'
        ($result.Warnings -join ';') | Should -Match 'metadata store has no readable ID'
    }

    It 'marks an unreadable LOB system as incomplete and keeps the others' {
        $broken = Get-TestLobSystem -Name ''
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a')) -Stores @{
            'context:https://a' = (Get-TestCatalog -Id 7 -LobSystems @($broken, (Get-TestLobSystem -Name 'CrmSystem')))
        }

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].LobSystemName | Should -Be 'CrmSystem'
        ($result.Warnings -join ';') | Should -Match "A BCS LOB system could not be read for web application 'https://a'"
        ($result.Warnings -join ';') | Should -Match 'no readable name'
    }

    It 'marks a missing LOB system list as incomplete' {
        $catalog = [PSCustomObject]@{ Id = 7 }
        $catalog | Add-Member -MemberType ScriptMethod -Name GetLobSystems -Value { param ($Filter) return $null }
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a')) -Stores @{ 'context:https://a' = $catalog }

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match 'list of LOB systems is unavailable'
    }
}
