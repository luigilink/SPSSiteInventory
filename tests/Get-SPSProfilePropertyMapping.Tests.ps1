# Behavior tests for Get-SPSProfilePropertyMapping (no farm needed: the web applications are mocked, the proxies and the connections are
# fakes, and the commands that need SharePoint are mocks).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # The module calls a SharePoint command, which does not exist outside a farm.
    function global:Get-SPWebApplication {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }

    $script:ProxyType = 'Microsoft.Office.Server.Administration.UserProfileApplicationProxy'
    $script:IdA = '11111111-1111-1111-1111-111111111111'
    $script:IdB = '22222222-2222-2222-2222-222222222222'

    function New-Map {
        param ([string]$Property, [string]$Attribute, [string]$Direction = 'Import')
        [PSCustomObject]@{ ProfilePropertyName = $Property; DataSourcePropertyName = $Attribute; Direction = $Direction }
    }

    function New-Connection {
        param ([string]$Name = 'Contoso', [string]$Type = 'ActiveDirectoryImport', [object[]]$Map = @(), [string]$ErrorText = '')
        [PSCustomObject]@{ DisplayName = $Name; Type = $Type; Maps = $Map; ErrorText = $ErrorText }
    }

    function New-Core {
        param ([string]$Name, [string]$DisplayName = '', $Length = 25)
        [PSCustomObject]@{ Name = $Name; DisplayName = $(if ($DisplayName) { $DisplayName } else { $Name }); Length = $Length }
    }

    # A configuration manager: its connections, the definitions of the properties and the number of profiles of each.
    function New-Manager {
        param ([object[]]$Connection = @(), [object[]]$Core = @(), [hashtable]$Count = @{}, [switch]$NoConnections, [string]$CoreError = '', [string[]]$CountError = @())
        $properties = [PSCustomObject]@{ Core = $Core; CoreError = $CoreError }
        $properties | Add-Member -MemberType ScriptMethod -Name GetCoreProperties -Value {
            if ($this.CoreError) { throw $this.CoreError }
            # A .NET method returns its collection as it is, an empty one included: the comma keeps PowerShell from unrolling it.
            if ($null -eq $this.Core) { return $null }
            return , $this.Core
        }
        $manager = [PSCustomObject]@{
            ConnectionManager = $null
            ProfilePropertyManager = $properties
            Count = $Count
            CountError = $CountError
            CountCalls = [System.Collections.Generic.List[string]]::new()
        }
        if (-not $NoConnections) {
            $manager.ConnectionManager = @($Connection)
        }
        $manager | Add-Member -MemberType ScriptMethod -Name CountProfilesWithProperty -Value {
            param ($Name)
            $this.CountCalls.Add($Name)
            if ($this.CountError -contains $Name) { throw 'The count is unavailable' }
            return [int]$this.Count[$Name]
        }
        return $manager
    }

    function New-Proxy {
        param ([string]$Id, [string]$Name = 'User Profile Service Proxy')
        [PSCustomObject]@{ PSTypeName = $script:ProxyType; Id = $(if ($Id) { [guid]$Id } else { $null }); Name = $Name }
    }

    function New-OtherProxy {
        [PSCustomObject]@{ PSTypeName = 'Microsoft.Office.Server.Search.Administration.SearchServiceApplicationProxy'; Id = [guid]'99999999-9999-9999-9999-999999999999'; Name = 'Search'; TypeName = 'Search Service Application Proxy' }
    }

    # What the mocks give for a proxy group: its manager, and how often it was read.
    function New-Group {
        param ([object[]]$Proxies = @(), $Manager = $null, [string]$ContextError = '', [string]$ManagerError = '', $Default = $null, [string]$DefaultError = '')
        [PSCustomObject]@{ Proxies = $Proxies; Manager = $Manager; ContextError = $ContextError; ManagerError = $ManagerError; Default = $Default; DefaultError = $DefaultError; ContextCalls = 0 }
    }

    function New-WebApplication {
        param ([string]$Url, $Group, [switch]$NoProxyGroup, [switch]$NoProxies)
        $effective = if ($NoProxyGroup) { $null } elseif ($NoProxies) { [PSCustomObject]@{ Proxies = $null } } else { $Group }
        [PSCustomObject]@{ Url = $Url; ServiceApplicationProxyGroup = $effective }
    }

    # The mocks read a global variable: a closure would lose the mocked command's parameters.
    function Set-TestFarm {
        param ([object[]]$WebApplications, $BuiltIn = @('AccountName', 'FirstName', 'LastName', 'PreferredName', 'Department', 'WorkEmail', 'PhoneticFirstName', 'SPS-SipAddress', 'SID'))
        $global:SPSTestProfileWebApplications = $WebApplications
        $global:SPSTestBuiltInNames = $BuiltIn
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common -MockWith {
            if ($Identity) {
                $found = @($global:SPSTestProfileWebApplications | Where-Object { $_.Url -eq $Identity })
                if ($found.Count -eq 0) { throw "Cannot find the web application '$Identity'." }
                return $found
            }
            $global:SPSTestProfileWebApplications
        }
        Mock Get-SPSBuiltInProfilePropertyName -ModuleName SPSSiteInventory.Common -MockWith { $global:SPSTestBuiltInNames }
        Mock Get-SPSProxyGroupServiceContext -ModuleName SPSSiteInventory.Common -MockWith {
            $ProxyGroup.ContextCalls++
            if ($ProxyGroup.ContextError) { throw $ProxyGroup.ContextError }
            $context = [PSCustomObject]@{ Group = $ProxyGroup }
            # What a service context answers when it is asked for its default proxy of a type.
            $context | Add-Member -MemberType ScriptMethod -Name GetDefaultProxy -Value {
                param ($Type)
                if ($this.Group.DefaultError) { throw $this.Group.DefaultError }
                $this.Group.Default
            }
            $context
        }
        Mock Get-SPSUserProfileConfigManager -ModuleName SPSSiteInventory.Common -MockWith {
            if ($ServiceContext.Group.ManagerError) { throw $ServiceContext.Group.ManagerError }
            $ServiceContext.Group.Manager
        }
        Mock Get-SPSConnectionPropertyMap -ModuleName SPSSiteInventory.Common -MockWith {
            if ($Connection.ErrorText) { throw $Connection.ErrorText }
            $Connection.Maps
        }
    }

    function Get-StandardManager {
        New-Manager -Connection @(
            (New-Connection -Name 'contoso-local' -Map @(
                    (New-Map 'FirstName' 'givenName'), (New-Map 'CostCenter' 'costCenter'), (New-Map 'PhoneticFirstName' 'msDS-PhoneticFirstName'), (New-Map 'WorkEmail' 'mail')))
        ) -Core @((New-Core 'FirstName' 'First name' 25), (New-Core 'CostCenter' 'Cost center' 50), (New-Core 'PhoneticFirstName' 'Phonetic first name' 25), (New-Core 'WorkEmail' 'Work e-mail' 300)) `
            -Count @{ FirstName = 1000; CostCenter = 7; PhoneticFirstName = 900; WorkEmail = 990 }
    }
}

AfterAll {
    Remove-Variable -Name SPSTestProfileWebApplications, SPSTestBuiltInNames -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-SPSProfilePropertyMapping' {
    It 'returns one row per mapping with its service, connection, property, attribute, direction, length and number of profiles, sorted by connection and property' {
        $manager = New-Manager -Connection @(
            (New-Connection -Name 'zeta' -Type 'BusinessDataCatalog' -Map @((New-Map 'Title' 'JobTitle' 'Export'), (New-Map 'Title' 'Position' 'Import')))
            (New-Connection -Name 'alpha' -Map @((New-Map 'LastName' 'sn'), (New-Map 'CostCenter' 'costCenter')))
        ) -Core @((New-Core 'LastName' 'Last name' 25), (New-Core 'CostCenter' 'Cost center' 50), (New-Core 'Title' 'Title' 255)) -Count @{ LastName = 100; CostCenter = 7; Title = 90 }
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://intranet' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager $manager)))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $result.Mappings | Should -HaveCount 4
        @($result.Mappings | ForEach-Object { '{0}/{1}/{2}' -f $_.ConnectionName, $_.PropertyName, $_.Direction }) | Should -Be @('alpha/CostCenter/Import', 'alpha/LastName/Import', 'zeta/Title/Export', 'zeta/Title/Import')
        $first = $result.Mappings[0]
        $first.WebApplicationUrls | Should -Be 'https://intranet'
        $first.UserProfileProxyId | Should -Be $script:IdA
        $first.UserProfileProxyName | Should -Be 'User Profile Service Proxy'
        $first.ConnectionType | Should -Be 'ActiveDirectoryImport'
        $first.PropertyName | Should -Be 'CostCenter'
        $first.PropertyDisplayName | Should -Be 'Cost center'
        $first.PropertyMapping | Should -Be 'costCenter'
        $first.PropertyLength | Should -Be 50
        $first.PropertyUsage | Should -Be 7
        $result.Mappings[2].ConnectionType | Should -Be 'BusinessDataCatalog'
        $result.Mappings[2].PropertyMapping | Should -Be 'JobTitle'
    }

    It 'says whether SharePoint Online fills the property, and whether SharePoint ships it, and leaves the second empty when the list of the shipped ones cannot be read' {
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://intranet' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (Get-StandardManager))))

        $rows = @((Get-SPSProfilePropertyMapping).Mappings | Sort-Object PropertyName)

        $byName = @{}
        foreach ($row in $rows) { $byName[$row.PropertyName] = $row }
        $byName['FirstName'].SynchronizedInSharePointOnline | Should -BeTrue
        $byName['FirstName'].BuiltInProperty | Should -BeTrue
        $byName['WorkEmail'].SynchronizedInSharePointOnline | Should -BeTrue
        $byName['PhoneticFirstName'].SynchronizedInSharePointOnline | Should -BeFalse
        $byName['PhoneticFirstName'].BuiltInProperty | Should -BeTrue
        $byName['CostCenter'].SynchronizedInSharePointOnline | Should -BeFalse
        $byName['CostCenter'].BuiltInProperty | Should -BeFalse

        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://intranet' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (Get-StandardManager)))) -BuiltIn $null
        $unknownResult = Get-SPSProfilePropertyMapping
        $unknown = @($unknownResult.Mappings)
        $unknown | Should -HaveCount 4
        foreach ($row in $unknown) { $row.BuiltInProperty | Should -BeNullOrEmpty }
        @($unknown | Where-Object { $_.PropertyName -eq 'FirstName' })[0].SynchronizedInSharePointOnline | Should -BeTrue
    }

    It 'marks the result incomplete, and says what follows from it, when the list of the properties that SharePoint ships cannot be read' {
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://intranet' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (Get-StandardManager)))) -BuiltIn $null

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 4
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match 'The list of the profile properties that SharePoint ships \(PropertyConstants\) could not be read, so BuiltInProperty is empty and every mapping of a property that SharePoint Online does not fill is reported as a possible custom one'
    }

    It 'stays complete, with no warning, when the list of the properties that SharePoint ships is read' {
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://intranet' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (Get-StandardManager))))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'identifies a property by its internal name, in any case, without stripping its punctuation, and never by its display name' {
        $manager = New-Manager -Connection @((New-Connection -Map @(
                    (New-Map 'sps-sipaddress' 'msRTCSIP'), (New-Map 'Custom1' 'attr1'), (New-Map 'Custom2' 'attr2'), (New-Map 'SPSSipAddress' 'attr3'), (New-Map 'workemail' 'mail'), (New-Map 'Custom3' 'attr4')))) `
            -Core @((New-Core 'sps-sipaddress' 'sip address'), (New-Core 'Custom1' 'Work Email'), (New-Core 'Custom2' 'Cost Center'), (New-Core 'SPSSipAddress' 'SIP Address'), (New-Core 'workemail' 'Mail'), (New-Core 'Custom3' 'WorkEmail'))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://intranet' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager $manager))) -BuiltIn @('SPS-SipAddress', 'WorkEmail')

        $rows = @((Get-SPSProfilePropertyMapping).Mappings)

        $byName = @{}
        foreach ($row in $rows) { $byName[$row.PropertyName] = $row }
        $byName['sps-sipaddress'].SynchronizedInSharePointOnline | Should -BeTrue -Because 'the internal name is SPS-SipAddress, in another case'
        $byName['sps-sipaddress'].BuiltInProperty | Should -BeTrue
        $byName['workemail'].SynchronizedInSharePointOnline | Should -BeTrue
        $byName['workemail'].BuiltInProperty | Should -BeTrue
        $byName['Custom1'].SynchronizedInSharePointOnline | Should -BeFalse -Because 'its display name is the one of Work Email, and a display name is not an identity'
        $byName['Custom1'].BuiltInProperty | Should -BeFalse
        $byName['Custom2'].SynchronizedInSharePointOnline | Should -BeFalse
        $byName['Custom3'].SynchronizedInSharePointOnline | Should -BeFalse -Because 'its display name is the internal name of a property that SharePoint Online fills, which does not make it that property'
        $byName['Custom3'].BuiltInProperty | Should -BeFalse
        $byName['SPSSipAddress'].SynchronizedInSharePointOnline | Should -BeFalse -Because 'the hyphen of SPS-SipAddress is part of its name'
        $byName['SPSSipAddress'].BuiltInProperty | Should -BeFalse
    }

    It 'asks for the number of profiles once for each property, and leaves it empty, without making the result incomplete, when it cannot be read' {
        $manager = New-Manager -Connection @(
            (New-Connection -Name 'a' -Map @((New-Map 'FirstName' 'givenName'), (New-Map 'CostCenter' 'costCenter')))
            (New-Connection -Name 'b' -Map @((New-Map 'FirstName' 'givenName')))
        ) -Count @{ FirstName = 10 } -CountError @('CostCenter')
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://intranet' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager $manager)))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        @($manager.CountCalls | Where-Object { $_ -eq 'FirstName' }) | Should -HaveCount 1
        @($result.Mappings | Where-Object PropertyName -eq 'CostCenter')[0].PropertyUsage | Should -BeNullOrEmpty
        @($result.Mappings | Where-Object PropertyName -eq 'FirstName')[0].PropertyUsage | Should -Be 10
    }

    It 'leaves the display name and the length empty, with a warning, when the definitions cannot be read, and keeps the mappings' -ForEach @(
        @{ Case = 'throws'; CoreError = 'The definitions are denied' }
        @{ Case = 'null'; CoreError = '' }
    ) {
        $manager = New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName')))) -Core $(if ($Case -eq 'null') { $null } else { @() }) -CoreError $CoreError
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://intranet' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager $manager)))

        $result = Get-SPSProfilePropertyMapping

        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].PropertyDisplayName | Should -Be ''
        $result.Mappings[0].PropertyLength | Should -BeNullOrEmpty
        $result.Complete | Should -BeTrue
        ($result.Warnings -join ';') | Should -Match 'property definitions could not be read for web application .https://intranet.'
    }

    It 'finds the User Profile proxy by its type name or by its display name, and ignores the other proxies' {
        $byText = [PSCustomObject]@{ PSTypeName = 'Some.Other.ProxyType'; TypeName = 'User Profile Service Application Proxy'; Id = [guid]$script:IdB; Name = 'Text proxy' }
        $a = New-Group -Proxies @((New-OtherProxy), (New-Proxy -Id $script:IdA)) -Manager (New-Manager -Connection @((New-Connection -Name 'a' -Map @((New-Map 'FirstName' 'givenName')))))
        $b = New-Group -Proxies @($byText) -Manager (New-Manager -Connection @((New-Connection -Name 'b' -Map @((New-Map 'LastName' 'sn')))))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $a), (New-WebApplication -Url 'https://b' -Group $b))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeTrue
        $result.Mappings | Should -HaveCount 2
        $result.Mappings[0].UserProfileProxyId | Should -Be $script:IdA
        $result.Mappings[1].UserProfileProxyName | Should -Be 'Text proxy'
    }

    It 'reports nothing, complete and without reading anything, for a web application whose proxy group has no User Profile proxy, as long as another one has a proxy' {
        $none = New-Group -Proxies @((New-OtherProxy))
        $has = New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName')))))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $none), (New-WebApplication -Url 'https://b' -Group (New-Group)), (New-WebApplication -Url 'https://c' -Group $has))

        $result = Get-SPSProfilePropertyMapping

        $result.Mappings | Should -HaveCount 1
        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $none.ContextCalls | Should -Be 0
    }

    It 'says once in the run log, and stays complete, when no web application has a User Profile proxy at all: a farm without the service, or a proxy type that is not recognized' {
        $group = New-Group -Proxies @((New-OtherProxy))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $group), (New-WebApplication -Url 'https://b' -Group (New-Group)))

        $result = Get-SPSProfilePropertyMapping

        $result.Mappings | Should -HaveCount 0
        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match 'No User Profile service application proxy was found in the service application proxy group of the 2 web application\(s\) that were read'
        $group.ContextCalls | Should -Be 0
    }

    It 'does not add that note when no web application could be read at all: the other warnings say why' {
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://nogroup' -NoProxyGroup))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match 'service application proxy group could not be read'
    }

    It 'reads only the requested web applications' {
        $a = New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (New-Manager -Connection @((New-Connection -Name 'a' -Map @((New-Map 'FirstName' 'givenName')))))
        $b = New-Group -Proxies @((New-Proxy -Id $script:IdB)) -Manager (New-Manager -Connection @((New-Connection -Name 'b' -Map @((New-Map 'LastName' 'sn')))))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $a), (New-WebApplication -Url 'https://b' -Group $b))

        $result = Get-SPSProfilePropertyMapping -WebApplicationUrl 'https://b'

        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].WebApplicationUrls | Should -Be 'https://b'
        $a.ContextCalls | Should -Be 0
        Should -Invoke Get-SPWebApplication -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $Identity -eq 'https://b' }
    }

    It 'reads a User Profile proxy shared by several web applications once and lists every web application that sees it' {
        $shared = New-Proxy -Id $script:IdA
        $manager = New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName'))))
        $first = New-Group -Proxies @($shared) -Manager $manager
        $second = New-Group -Proxies @($shared) -Manager $manager
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $first), (New-WebApplication -Url 'https://b' -Group $second))

        $result = Get-SPSProfilePropertyMapping

        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].WebApplicationUrls | Should -Be 'https://a; https://b'
        $first.ContextCalls + $second.ContextCalls | Should -Be 1
        $second.ContextCalls | Should -Be 0 -Because 'a group with a single proxy has nothing to resolve: its context is built only for the read'
    }

    It 'keeps distinct User Profile proxies separate' {
        $a = New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName')))))
        $b = New-Group -Proxies @((New-Proxy -Id $script:IdB)) -Manager (New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName')))))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $a), (New-WebApplication -Url 'https://b' -Group $b))

        $result = Get-SPSProfilePropertyMapping

        $result.Mappings | Should -HaveCount 2
        $result.Mappings[0].UserProfileProxyId | Should -Be $script:IdA
        $result.Mappings[1].UserProfileProxyId | Should -Be $script:IdB
    }

    It 'identifies the service by the default proxy that the service context binds, when the group holds several, and says that the others are not read' {
        $first = New-Proxy -Id $script:IdA -Name 'First'
        $second = New-Proxy -Id $script:IdB -Name 'Second'
        $group = New-Group -Proxies @($first, $second) -Manager (New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName'))))) -Default $second
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSProfilePropertyMapping

        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].UserProfileProxyId | Should -Be $script:IdB
        $result.Mappings[0].UserProfileProxyName | Should -Be 'Second'
        $result.Complete | Should -BeFalse
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match ("The User Profile proxy 'First' \({0}\) is not the default User Profile proxy of the service application proxy group of any web application" -f $script:IdA)
        $group.ContextCalls | Should -Be 1
    }

    It 'reads each default proxy once when groups that hold the same proxies have different defaults, and stays complete' {
        $first = New-Proxy -Id $script:IdA -Name 'First'
        $second = New-Proxy -Id $script:IdB -Name 'Second'
        $groupA = New-Group -Proxies @($first, $second) -Manager (New-Manager -Connection @((New-Connection -Name 'a' -Map @((New-Map 'FirstName' 'givenName'))))) -Default $first
        $groupB = New-Group -Proxies @($first, $second) -Manager (New-Manager -Connection @((New-Connection -Name 'b' -Map @((New-Map 'LastName' 'sn'))))) -Default $second
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $groupA), (New-WebApplication -Url 'https://b' -Group $groupB))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $result.Mappings | Should -HaveCount 2
        $result.Mappings[0].ConnectionName | Should -Be 'a'
        $result.Mappings[0].WebApplicationUrls | Should -Be 'https://a'
        $result.Mappings[0].UserProfileProxyId | Should -Be $script:IdA
        $result.Mappings[1].ConnectionName | Should -Be 'b'
        $result.Mappings[1].WebApplicationUrls | Should -Be 'https://b'
        $result.Mappings[1].UserProfileProxyId | Should -Be $script:IdB
    }

    It 'reports a proxy once when a group that holds only it and a group that holds it and another one, with it as the default, see it' {
        $first = New-Proxy -Id $script:IdA -Name 'First'
        $second = New-Proxy -Id $script:IdB -Name 'Second'
        $manager = New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName'))))
        $only = New-Group -Proxies @($first) -Manager $manager
        $both = New-Group -Proxies @($first, $second) -Manager $manager -Default $first
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $only), (New-WebApplication -Url 'https://b' -Group $both))

        $result = Get-SPSProfilePropertyMapping

        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].WebApplicationUrls | Should -Be 'https://a; https://b'
        $result.Mappings[0].UserProfileProxyId | Should -Be $script:IdA
        $result.Complete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "'Second' \($($script:IdB)\) is not the default"
    }

    It 'marks the result incomplete when the default proxy of a group that holds several cannot be told: the IDs and the names are listed in the same order' {
        $zeta = New-Proxy -Id $script:IdA -Name 'Zeta'
        $alpha = New-Proxy -Id $script:IdB -Name 'Alpha'
        $group = New-Group -Proxies @($alpha, $zeta) -Manager (New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName')))))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].UserProfileProxyId | Should -Be ('{0}; {1}' -f $script:IdA, $script:IdB)
        $result.Mappings[0].UserProfileProxyName | Should -Be 'Zeta; Alpha'
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match "Web application 'https://a' has 2 User Profile proxies .* default one could not be determined \(the service context has no default User Profile proxy among them\)"
    }

    It 'gives the reason when the service context cannot answer for its default proxy, and still reads the service once' {
        $group = New-Group -Proxies @((New-Proxy -Id $script:IdA -Name 'First'), (New-Proxy -Id $script:IdB -Name 'Second')) -Manager (New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName'))))) -DefaultError 'The default proxy is unavailable'
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 1
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match 'default one could not be determined \(.*The default proxy is unavailable.*\)'
        $group.ContextCalls | Should -Be 1
    }

    It 'does not read a group that holds several proxies when its service context cannot be built, and says it once' {
        $group = New-Group -Proxies @((New-Proxy -Id $script:IdA), (New-Proxy -Id $script:IdB)) -Manager (New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName'))))) -ContextError 'The service context is unavailable'
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 0
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match "The profile synchronization connections could not be read for web application 'https://a': The service context is unavailable"
    }

    It 'warns about a web application that cannot be found and still reads the others' {
        $good = New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (New-Manager -Connection @((New-Connection -Name 'good' -Map @((New-Map 'FirstName' 'givenName')))))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://good' -Group $good))

        $result = Get-SPSProfilePropertyMapping -WebApplicationUrl @('https://stale', 'https://good')

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].WebApplicationUrls | Should -Be 'https://good'
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match "The web application 'https://stale' could not be read: Cannot find the web application 'https://stale'"
    }

    It 'warns about every web application that cannot be found, and does not add the note about a missing User Profile service' {
        Set-TestFarm -WebApplications @()

        $result = Get-SPSProfilePropertyMapping -WebApplicationUrl @('https://stale', 'https://gone')

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 0
        $result.Warnings | Should -HaveCount 2
        ($result.Warnings -join ';') | Should -Not -Match 'No User Profile service application proxy'
    }

    It 'returns an empty complete result when the service has no connection, or when the farm has no web application' {
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (New-Manager))))
        $none = Get-SPSProfilePropertyMapping
        Set-TestFarm -WebApplications @()
        $empty = Get-SPSProfilePropertyMapping

        $none.Mappings | Should -HaveCount 0
        $none.Complete | Should -BeTrue
        $empty.Mappings | Should -HaveCount 0
        $empty.Complete | Should -BeTrue
    }

    It 'marks the result incomplete, and says which permission is missing, when the connections cannot be read' {
        $group = New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (New-Manager -NoConnections)
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 0
        ($result.Warnings -join ';') | Should -Match "connections could not be read for web application 'https://a'.*has to administer the User Profile service application"
    }

    It 'marks the result incomplete when the service context or the manager cannot be built, and keeps the other web applications' {
        $noContext = New-Group -Proxies @((New-Proxy -Id $script:IdA)) -ContextError 'The service context is unavailable'
        $noManager = New-Group -Proxies @((New-Proxy -Id $script:IdB)) -ManagerError 'The manager type is not available'
        $good = New-Group -Proxies @((New-Proxy -Id '33333333-3333-3333-3333-333333333333')) -Manager (New-Manager -Connection @((New-Connection -Name 'good' -Map @((New-Map 'FirstName' 'givenName')))))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $noContext), (New-WebApplication -Url 'https://b' -Group $noManager), (New-WebApplication -Url 'https://c' -Group $good))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].ConnectionName | Should -Be 'good'
        ($result.Warnings -join ';') | Should -Match 'The service context is unavailable'
        ($result.Warnings -join ';') | Should -Match 'The manager type is not available'
    }

    It 'reports the failure of a service shared by several web applications once' {
        $shared = New-Proxy -Id $script:IdA
        $first = New-Group -Proxies @($shared) -Manager (New-Manager -NoConnections)
        $second = New-Group -Proxies @($shared) -Manager (New-Manager -NoConnections)
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $first), (New-WebApplication -Url 'https://b' -Group $second))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Warnings | Should -HaveCount 1
    }

    It 'marks a connection that cannot be read as incomplete and keeps the others' {
        $manager = New-Manager -Connection @(
            (New-Connection -Name 'broken' -ErrorText "The property mappings of the Active Directory import connection 'broken' could not be read")
            (New-Connection -Name 'good' -Map @((New-Map 'FirstName' 'givenName')))
        )
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager $manager)))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].ConnectionName | Should -Be 'good'
        ($result.Warnings -join ';') | Should -Match "property mappings of a connection could not be read for web application 'https://a'.*connection 'broken'"
    }

    It 'marks an unreadable proxy ID, proxy group or list of proxies as incomplete instead of guessing, and keeps the others' {
        $noId = New-Group -Proxies @((New-Proxy)) -Manager (New-Manager)
        $emptyId = New-Group -Proxies @((New-Proxy -Id '00000000-0000-0000-0000-000000000000')) -Manager (New-Manager)
        $good = New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager (New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName')))))
        Set-TestFarm -WebApplications @(
            (New-WebApplication -Url 'https://good' -Group $good)
            (New-WebApplication -Url 'https://noid' -Group $noId)
            (New-WebApplication -Url 'https://emptyid' -Group $emptyId)
            (New-WebApplication -Url 'https://nogroup' -NoProxyGroup)
            (New-WebApplication -Url 'https://noproxies' -NoProxies)
            (New-WebApplication -Url '')
        )

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 1
        @($result.Warnings | Where-Object { $_ -match 'ID of a User Profile proxy could not be read' }) | Should -HaveCount 2
        ($result.Warnings -join ';') | Should -Match "web application 'https://nogroup': The service application proxy group could not be read"
        ($result.Warnings -join ';') | Should -Match "web application 'https://noproxies': The service application proxies could not be read"
        ($result.Warnings -join ';') | Should -Match "web application '\(unknown web application\)': The web application URL could not be read"
    }

    It 'reads only: no profile, no connection test, and nothing is written' {
        $path = Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/Public/Get-SPSProfilePropertyMapping.ps1'
        $commands = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null).FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }

        @($commands | Where-Object { $_ -match '^(Set|Remove|Update|Clear|Add|Grant|Revoke|Start|Invoke)-' -and $_ -ne 'Add-SPSInventoryEvent' }) | Should -HaveCount 0
        @($commands | Where-Object { $_ -match '^New-SP' }) | Should -HaveCount 0
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should -Not -Match 'UserProfileManager|GetUserProfile|AddNewMapping|AddPropertyMapping|RemovePropertyMapping|\.Update\(\)'
    }
}
