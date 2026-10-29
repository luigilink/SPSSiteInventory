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
        param ([object[]]$Proxies = @(), $Manager = $null, [string]$ContextError = '', [string]$ManagerError = '')
        [PSCustomObject]@{ Proxies = $Proxies; Manager = $Manager; ContextError = $ContextError; ManagerError = $ManagerError; ContextCalls = 0 }
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
            if ($Identity) { return @($global:SPSTestProfileWebApplications | Where-Object { $_.Url -eq $Identity }) }
            $global:SPSTestProfileWebApplications
        }
        Mock Get-SPSBuiltInProfilePropertyName -ModuleName SPSSiteInventory.Common -MockWith { $global:SPSTestBuiltInNames }
        Mock Get-SPSProxyGroupServiceContext -ModuleName SPSSiteInventory.Common -MockWith {
            $ProxyGroup.ContextCalls++
            if ($ProxyGroup.ContextError) { throw $ProxyGroup.ContextError }
            [PSCustomObject]@{ Group = $ProxyGroup }
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
        $unknown = @((Get-SPSProfilePropertyMapping).Mappings)
        foreach ($row in $unknown) { $row.BuiltInProperty | Should -BeNullOrEmpty }
    }

    It 'compares the names by their letters and digits, in any case, and also by the display name of the property' {
        $manager = New-Manager -Connection @((New-Connection -Map @((New-Map 'sps-sipaddress' 'msRTCSIP'), (New-Map 'Custom1' 'attr1'), (New-Map 'Custom2' 'attr2')))) `
            -Core @((New-Core 'sps-sipaddress' 'sip address'), (New-Core 'Custom1' 'Work Email'), (New-Core 'Custom2' 'Cost Center'))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://intranet' -Group (New-Group -Proxies @((New-Proxy -Id $script:IdA)) -Manager $manager))) -BuiltIn @('SPS-SipAddress')

        $rows = @((Get-SPSProfilePropertyMapping).Mappings | Sort-Object PropertyName)

        $rows[0].PropertyName | Should -Be 'Custom1'
        $rows[0].SynchronizedInSharePointOnline | Should -BeTrue -Because 'its display name is the one of Work Email'
        $rows[0].BuiltInProperty | Should -BeFalse
        $rows[1].SynchronizedInSharePointOnline | Should -BeFalse
        $rows[2].SynchronizedInSharePointOnline | Should -BeTrue
        $rows[2].BuiltInProperty | Should -BeTrue
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

    It 'reports nothing, without a warning and without reading anything, for a web application whose proxy group has no User Profile proxy' {
        $group = New-Group -Proxies @((New-OtherProxy))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $group), (New-WebApplication -Url 'https://b' -Group (New-Group)))

        $result = Get-SPSProfilePropertyMapping

        $result.Mappings | Should -HaveCount 0
        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $group.ContextCalls | Should -Be 0
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

    It 'marks the result incomplete when a proxy group holds several User Profile proxies: a service context binds the default one only' {
        $group = New-Group -Proxies @((New-Proxy -Id $script:IdA -Name 'First'), (New-Proxy -Id $script:IdB -Name 'Second')) -Manager (New-Manager -Connection @((New-Connection -Map @((New-Map 'FirstName' 'givenName')))))
        Set-TestFarm -WebApplications @((New-WebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSProfilePropertyMapping

        $result.Complete | Should -BeFalse
        $result.Mappings | Should -HaveCount 1
        $result.Mappings[0].UserProfileProxyId | Should -Be ('{0}; {1}' -f $script:IdA, $script:IdB)
        $result.Mappings[0].UserProfileProxyName | Should -Be 'First; Second'
        ($result.Warnings -join ';') | Should -Match "Web application 'https://a' has 2 User Profile proxies"
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
