# Behavior tests for Get-SPSBcsApplication (no farm needed: the web applications are mocked and the BDC proxies are fakes).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # The module calls a SharePoint command, which does not exist outside a farm.
    function global:Get-SPWebApplication {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }

    $script:BdcProxyType = 'Microsoft.SharePoint.BusinessData.SharedService.BdcServiceApplicationProxy'

    function Get-TestLobSystem {
        param ([string]$Name, [string[]]$Instances = @('Instance'), [string[]]$Entities = @())
        [PSCustomObject]@{
            Name = $Name
            SystemType = 'Wcf'
            LobSystemInstances = @($Instances | ForEach-Object { [PSCustomObject]@{ Name = $_ } })
            Entities = @($Entities | ForEach-Object { [PSCustomObject]@{ Namespace = 'Contoso'; Name = $_ } })
        }
    }

    # The catalog Id only identifies an object inside one store, so distinct stores can share it.
    function Get-TestCatalog {
        param ([int]$Id = 1, [object[]]$LobSystems = @())
        $catalog = [PSCustomObject]@{ Id = $Id; LobSystems = $LobSystems; Calls = 0; Filters = [System.Collections.Generic.List[string]]::new() }
        $catalog | Add-Member -MemberType ScriptMethod -Name GetLobSystems -Value {
            param ($Filter)
            $this.Calls++
            $this.Filters.Add($Filter)
            return , @($this.LobSystems)
        }
        return $catalog
    }

    # A fake BDC proxy: it has the type name the function looks for and the two methods it calls.
    function Get-TestBdcProxy {
        param ([string]$ServiceApplicationId, $Catalog, [string]$IdError = '', [string]$CatalogError = '')
        $proxy = [PSCustomObject]@{
            PSTypeName = $script:BdcProxyType
            ServiceApplicationId = $ServiceApplicationId
            Catalog = $Catalog
            IdError = $IdError
            CatalogError = $CatalogError
            IdCalls = 0
            CatalogCalls = 0
        }
        $proxy | Add-Member -MemberType ScriptMethod -Name GetServiceApplicationId -Value {
            $this.IdCalls++
            if ($this.IdError) { throw $this.IdError }
            if ($this.ServiceApplicationId) { return [guid]$this.ServiceApplicationId }
            return $null
        }
        $proxy | Add-Member -MemberType ScriptMethod -Name GetAdministrationMetadataCatalog -Value {
            $this.CatalogCalls++
            if ($this.CatalogError) { throw $this.CatalogError }
            return $this.Catalog
        }
        return $proxy
    }

    function Get-TestOtherProxy {
        [PSCustomObject]@{ PSTypeName = 'Microsoft.Office.Server.Search.Administration.SearchServiceApplicationProxy'; Name = 'Search' }
    }

    function Get-TestWebApplication {
        param ([string]$Url, [object[]]$Proxies = @(), [switch]$NoProxyGroup, [switch]$NoProxies)
        $group = if ($NoProxyGroup) { $null } elseif ($NoProxies) { [PSCustomObject]@{ Proxies = $null } } else { [PSCustomObject]@{ Proxies = $Proxies } }
        [PSCustomObject]@{ Url = $Url; ServiceApplicationProxyGroup = $group }
    }

    # The mock reads a global variable: a closure would lose the mocked command's parameters.
    function Set-TestFarm {
        param ([object[]]$WebApplications)
        $global:SPSTestBcsWebApplications = $WebApplications
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common -MockWith {
            if ($Identity) { return @($global:SPSTestBcsWebApplications | Where-Object { $_.Url -eq $Identity }) }
            $global:SPSTestBcsWebApplications
        }
    }

    $script:IdA = '11111111-1111-1111-1111-111111111111'
    $script:IdB = '22222222-2222-2222-2222-222222222222'
}

AfterAll {
    Remove-Variable -Name SPSTestBcsWebApplications -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-SPSBcsApplication' {
    It 'returns one row per LOB system with its store, type, instances and entities' {
        $catalog = Get-TestCatalog -LobSystems @(
            (Get-TestLobSystem -Name 'SapSystem' -Instances @('SapInstance') -Entities @('Order', 'Material'))
            (Get-TestLobSystem -Name 'CrmSystem' -Instances @('CrmProd', 'CrmDev') -Entities @('Customer'))
        )
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://intranet' -Proxies @((Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $catalog))))

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $result.Applications | Should -HaveCount 2
        $result.Applications[0].LobSystemName | Should -Be 'CrmSystem'
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://intranet'
        $result.Applications[0].BdcServiceApplicationId | Should -Be $script:IdA
        $result.Applications[0].LobSystemType | Should -Be 'Wcf'
        $result.Applications[0].LobSystemInstances | Should -Be 'CrmDev; CrmProd'
        $result.Applications[0].EntityCount | Should -Be 1
        $result.Applications[0].LobEntities | Should -Be 'Contoso.Customer'
        $result.Applications[1].LobSystemName | Should -Be 'SapSystem'
        $result.Applications[1].LobEntities | Should -Be 'Contoso.Material; Contoso.Order'
        $catalog.Filters[0] | Should -Be '*'
    }

    It 'reads a web application without any site collection and ignores proxies that are not BDC proxies' {
        $catalog = Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name 'CrmSystem'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://empty' -Proxies @((Get-TestOtherProxy), (Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $catalog))))

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeTrue
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://empty'
    }

    It 'reports no BCS, without a warning, for a web application whose proxy group has no BDC proxy' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @((Get-TestOtherProxy))), (Get-TestWebApplication -Url 'https://b' -Proxies @()))

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'reads only the requested web applications' {
        $a = Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog (Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name 'CrmSystem')))
        $b = Get-TestBdcProxy -ServiceApplicationId $script:IdB -Catalog (Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @($a)), (Get-TestWebApplication -Url 'https://b' -Proxies @($b)))

        $result = Get-SPSBcsApplication -WebApplicationUrl 'https://b'

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://b'
        $a.CatalogCalls | Should -Be 0
        Should -Invoke Get-SPWebApplication -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $Identity -eq 'https://b' }
    }

    It 'reads a BDC service application shared by several web applications once and lists every web application that sees it' {
        $catalog = Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name 'CrmSystem'))
        $first = Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $catalog
        $second = Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $catalog
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @($first)), (Get-TestWebApplication -Url 'https://b' -Proxies @($second)))

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a; https://b'
        $catalog.Calls | Should -Be 1
        $first.CatalogCalls + $second.CatalogCalls | Should -Be 1
    }

    It 'lists a web application once when two of its proxies point to the same BDC service application' {
        $catalog = Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name 'CrmSystem'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @(
                    (Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $catalog)
                    (Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $catalog))))

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a'
    }

    It 'keeps distinct BDC service applications separate even when their catalogs share the same ID' {
        $catalogA = Get-TestCatalog -Id 1 -LobSystems @((Get-TestLobSystem -Name 'CrmSystem'))
        $catalogB = Get-TestCatalog -Id 1 -LobSystems @((Get-TestLobSystem -Name 'SapSystem'))
        Set-TestFarm -WebApplications @(
            (Get-TestWebApplication -Url 'https://a' -Proxies @((Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $catalogA)))
            (Get-TestWebApplication -Url 'https://b' -Proxies @((Get-TestBdcProxy -ServiceApplicationId $script:IdB -Catalog $catalogB)))
        )

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeTrue
        $result.Applications | Should -HaveCount 2
        $result.Applications[0].LobSystemName | Should -Be 'CrmSystem'
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a'
        $result.Applications[0].BdcServiceApplicationId | Should -Be $script:IdA
        $result.Applications[1].LobSystemName | Should -Be 'SapSystem'
        $result.Applications[1].WebApplicationUrls | Should -Be 'https://b'
        $result.Applications[1].BdcServiceApplicationId | Should -Be $script:IdB
        $catalogA.Calls | Should -Be 1
        $catalogB.Calls | Should -Be 1
    }

    It 'reads every BDC proxy of a web application' {
        $proxyA = Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog (Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name 'CrmSystem')))
        $proxyB = Get-TestBdcProxy -ServiceApplicationId $script:IdB -Catalog (Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @($proxyA, $proxyB)))

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 2
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a'
        $result.Applications[1].WebApplicationUrls | Should -Be 'https://a'
    }

    It 'returns an empty complete result when the metadata store defines no LOB system' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @((Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog (Get-TestCatalog)))))

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
    }

    It 'returns an empty complete result when the farm has no web application' {
        Set-TestFarm -WebApplications @()

        $result = Get-SPSBcsApplication

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
    }

    It 'marks a metadata store that cannot be read as incomplete and keeps the other web applications' {
        $broken = Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $null -CatalogError 'Access denied to the metadata store'
        $good = Get-TestBdcProxy -ServiceApplicationId $script:IdB -Catalog (Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name 'SapSystem')))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @($broken)), (Get-TestWebApplication -Url 'https://b' -Proxies @($good)))

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].LobSystemName | Should -Be 'SapSystem'
        ($result.Warnings -join ';') | Should -Match "metadata store could not be read for web application 'https://a'"
        ($result.Warnings -join ';') | Should -Match 'Access denied to the metadata store'
    }

    It 'marks an unreadable BDC service application ID as incomplete instead of guessing the store' {
        $failing = Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog (Get-TestCatalog) -IdError 'Service unavailable'
        $empty = Get-TestBdcProxy -ServiceApplicationId '00000000-0000-0000-0000-000000000000' -Catalog (Get-TestCatalog)
        $missing = Get-TestBdcProxy -ServiceApplicationId '' -Catalog (Get-TestCatalog)
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @($failing)), (Get-TestWebApplication -Url 'https://b' -Proxies @($empty)), (Get-TestWebApplication -Url 'https://c' -Proxies @($missing)))

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 0
        ($result.Warnings -join ';') | Should -Match 'Service unavailable'
        @($result.Warnings | Where-Object { $_ -match 'BDC service application ID could not be read' }) | Should -HaveCount 2
        $failing.CatalogCalls + $empty.CatalogCalls + $missing.CatalogCalls | Should -Be 0
    }

    It 'marks a missing metadata store or LOB system list as incomplete' {
        $noCatalog = Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $null
        $noList = [PSCustomObject]@{ Id = 1 }
        $noList | Add-Member -MemberType ScriptMethod -Name GetLobSystems -Value { param ($Filter) return $null }
        $noLobList = Get-TestBdcProxy -ServiceApplicationId $script:IdB -Catalog $noList
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @($noCatalog)), (Get-TestWebApplication -Url 'https://b' -Proxies @($noLobList)))

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match 'metadata store is unavailable'
        ($result.Warnings -join ';') | Should -Match 'list of LOB systems is unavailable'
    }

    It 'marks an unreadable LOB system as incomplete and keeps the others' {
        $catalog = Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name ''), (Get-TestLobSystem -Name 'CrmSystem'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Proxies @((Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog $catalog))))

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].LobSystemName | Should -Be 'CrmSystem'
        ($result.Warnings -join ';') | Should -Match "A BCS LOB system could not be read for web application 'https://a'"
        ($result.Warnings -join ';') | Should -Match 'no readable name'
    }

    It 'marks a web application whose proxy group or proxies cannot be read as incomplete and keeps the others' {
        $good = Get-TestBdcProxy -ServiceApplicationId $script:IdA -Catalog (Get-TestCatalog -LobSystems @((Get-TestLobSystem -Name 'CrmSystem')))
        Set-TestFarm -WebApplications @(
            (Get-TestWebApplication -Url 'https://good' -Proxies @($good))
            (Get-TestWebApplication -Url 'https://nogroup' -NoProxyGroup)
            (Get-TestWebApplication -Url 'https://noproxies' -NoProxies)
            (Get-TestWebApplication -Url '')
        )

        $result = Get-SPSBcsApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://good'
        $good.CatalogCalls | Should -Be 1
        ($result.Warnings -join ';') | Should -Match "web application 'https://nogroup': The service application proxy group could not be read"
        ($result.Warnings -join ';') | Should -Match "web application 'https://noproxies': The service application proxies could not be read"
        ($result.Warnings -join ';') | Should -Match "web application '\(unknown web application\)': The web application URL could not be read"
    }
}
