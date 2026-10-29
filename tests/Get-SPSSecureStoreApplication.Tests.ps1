# Behavior tests for Get-SPSSecureStoreApplication (no farm needed: the web applications are mocked, the proxies are
# fakes, and the SharePoint command that lists the applications of a service context is a mock).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # The module calls SharePoint commands, which do not exist outside a farm.
    function global:Get-SPWebApplication {
        param ($Identity)
        throw 'Unmocked SharePoint call'
    }
    function global:Get-SPSecureStoreApplication {
        param ($ServiceContext, [switch]$All, $Name)
        throw 'Unmocked SharePoint call'
    }

    $script:ProxyType = 'Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplicationProxy'

    function Get-TestTarget {
        param ([string]$Name, [string]$Type = 'Group')
        [PSCustomObject]@{
            Name = $Name; FriendlyName = ($Name + ' display'); ContactEmail = 'owner@contoso.com'; Type = $Type
            CredentialManagementUrl = $null; TicketTimeoutInMinutes = 2
        }
    }

    # A fake Secure Store proxy: it has the type name that the function looks for, an ID and a name.
    function Get-TestSecureStoreProxy {
        param ([string]$Id, [string]$Name = 'Secure Store Service Proxy')
        [PSCustomObject]@{ PSTypeName = $script:ProxyType; Id = $(if ($Id) { [guid]$Id } else { $null }); Name = $Name }
    }

    function Get-TestOtherProxy {
        [PSCustomObject]@{ PSTypeName = 'Microsoft.Office.Server.Search.Administration.SearchServiceApplicationProxy'; Id = [guid]'99999999-9999-9999-9999-999999999999'; Name = 'Search'; TypeName = 'Search Service Application Proxy' }
    }

    # What the mocked command returns for a proxy group, and how often it was asked.
    function Get-TestGroup {
        param ([object[]]$Proxies = @(), [object[]]$Applications = @(), [string]$ListError = '', [string]$ContextError = '', $Default = $null, [string]$DefaultError = '')
        [PSCustomObject]@{ Proxies = $Proxies; Applications = $Applications; ListError = $ListError; ContextError = $ContextError; Default = $Default; DefaultError = $DefaultError; Calls = 0; ContextCalls = 0 }
    }

    function Get-TestWebApplication {
        param ([string]$Url, $Group, [switch]$NoProxyGroup, [switch]$NoProxies)
        $effective = if ($NoProxyGroup) { $null } elseif ($NoProxies) { [PSCustomObject]@{ Proxies = $null } } else { $Group }
        [PSCustomObject]@{ Url = $Url; ServiceApplicationProxyGroup = $effective }
    }

    # The mocks read a global variable: a closure would lose the mocked command's parameters.
    function Set-TestFarm {
        param ([object[]]$WebApplications)
        $global:SPSTestSecureStoreWebApplications = $WebApplications
        Mock Get-SPWebApplication -ModuleName SPSSiteInventory.Common -MockWith {
            if ($Identity) {
                $found = @($global:SPSTestSecureStoreWebApplications | Where-Object { $_.Url -eq $Identity })
                if ($found.Count -eq 0) { throw "Cannot find the web application '$Identity'." }
                return $found
            }
            $global:SPSTestSecureStoreWebApplications
        }
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
        Mock Get-SPSecureStoreApplication -ModuleName SPSSiteInventory.Common -MockWith {
            $ServiceContext.Group.Calls++
            if ($ServiceContext.Group.ListError) { throw $ServiceContext.Group.ListError }
            $ServiceContext.Group.Applications
        }
    }

    $script:IdA = '11111111-1111-1111-1111-111111111111'
    $script:IdB = '22222222-2222-2222-2222-222222222222'
}

AfterAll {
    Remove-Variable -Name SPSTestSecureStoreWebApplications -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-SPSSecureStoreApplication' {
    It 'returns one row per target application with its proxy, name, display name, contact, type and time-out, sorted by name' {
        $group = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget'), (Get-TestTarget -Name 'CrmTarget' -Type 'RestrictedGroup'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://intranet' -Group $group))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $result.Applications | Should -HaveCount 2
        $result.Applications[0].Name | Should -Be 'CrmTarget'
        $result.Applications[0].ApplicationType | Should -Be 'RestrictedGroup'
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://intranet'
        $result.Applications[0].SecureStoreProxyId | Should -Be $script:IdA
        $result.Applications[0].SecureStoreProxyName | Should -Be 'Secure Store Service Proxy'
        $result.Applications[0].FriendlyName | Should -Be 'CrmTarget display'
        $result.Applications[0].ContactEmail | Should -Be 'owner@contoso.com'
        $result.Applications[0].CredentialManagementUrl | Should -Be ''
        $result.Applications[0].TicketTimeoutMinutes | Should -Be 2
        $result.Applications[1].Name | Should -Be 'SapTarget'
        $result.Applications[1].ApplicationType | Should -Be 'Group'
    }

    It 'asks for all the applications of the service context of the proxy group, without a site collection' {
        $group = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://empty' -Group $group))

        $null = Get-SPSSecureStoreApplication

        Should -Invoke Get-SPSProxyGroupServiceContext -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $ProxyGroup.Applications.Count -eq 1 }
        Should -Invoke Get-SPSecureStoreApplication -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $All -and $ServiceContext.Group.Applications.Count -eq 1 }
    }

    It 'finds the Secure Store proxy by its type name or by its display name, and ignores the other proxies' {
        $byText = [PSCustomObject]@{ PSTypeName = 'Some.Other.ProxyType'; TypeName = 'Secure Store Service Application Proxy'; Id = [guid]$script:IdB; Name = 'Text proxy' }
        $groupA = Get-TestGroup -Proxies @((Get-TestOtherProxy), (Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        $groupB = Get-TestGroup -Proxies @($byText) -Applications @((Get-TestTarget -Name 'CrmTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $groupA), (Get-TestWebApplication -Url 'https://b' -Group $groupB))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeTrue
        $result.Applications | Should -HaveCount 2
        $result.Applications[0].Name | Should -Be 'SapTarget'
        $result.Applications[0].SecureStoreProxyId | Should -Be $script:IdA
        $result.Applications[1].Name | Should -Be 'CrmTarget'
        $result.Applications[1].SecureStoreProxyName | Should -Be 'Text proxy'
    }

    It 'reports no Secure Store, complete and without reading anything, for a web application whose proxy group has no Secure Store proxy, as long as another one has a proxy' {
        $none = Get-TestGroup -Proxies @((Get-TestOtherProxy))
        $has = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $none), (Get-TestWebApplication -Url 'https://b' -Group (Get-TestGroup)), (Get-TestWebApplication -Url 'https://c' -Group $has))

        $result = Get-SPSSecureStoreApplication

        $result.Applications | Should -HaveCount 1
        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $none.ContextCalls | Should -Be 0
    }

    It 'says once in the run log, and stays complete, when no web application has a Secure Store proxy at all: a farm without the service, or a proxy type that is not recognized' {
        $group = Get-TestGroup -Proxies @((Get-TestOtherProxy))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group), (Get-TestWebApplication -Url 'https://b' -Group (Get-TestGroup)))

        $result = Get-SPSSecureStoreApplication

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match 'No Secure Store service application proxy was found in the service application proxy group of the 2 web application\(s\) that were read'
        $group.ContextCalls | Should -Be 0
    }

    It 'does not add that note when no web application could be read at all: the other warnings say why' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://nogroup' -NoProxyGroup))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match 'service application proxy group could not be read'
    }

    It 'reads only the requested web applications' {
        $a = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        $b = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdB)) -Applications @((Get-TestTarget -Name 'CrmTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $a), (Get-TestWebApplication -Url 'https://b' -Group $b))

        $result = Get-SPSSecureStoreApplication -WebApplicationUrl 'https://b'

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://b'
        $a.Calls | Should -Be 0
        Should -Invoke Get-SPWebApplication -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $Identity -eq 'https://b' }
    }

    It 'reads a Secure Store proxy shared by several web applications once and lists every web application that sees it' {
        $shared = Get-TestSecureStoreProxy -Id $script:IdA
        $first = Get-TestGroup -Proxies @($shared) -Applications @((Get-TestTarget -Name 'SapTarget'))
        $second = Get-TestGroup -Proxies @($shared) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $first), (Get-TestWebApplication -Url 'https://b' -Group $second))

        $result = Get-SPSSecureStoreApplication

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a; https://b'
        $first.Calls + $second.Calls | Should -Be 1
        # A group with a single Secure Store proxy has nothing to resolve: its context is built only for the read.
        $first.ContextCalls + $second.ContextCalls | Should -Be 1
    }

    It 'keeps distinct Secure Store proxies separate even when their applications have the same name' {
        $a = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        $b = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdB)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $a), (Get-TestWebApplication -Url 'https://b' -Group $b))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeTrue
        $result.Applications | Should -HaveCount 2
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a'
        $result.Applications[0].SecureStoreProxyId | Should -Be $script:IdA
        $result.Applications[1].WebApplicationUrls | Should -Be 'https://b'
        $result.Applications[1].SecureStoreProxyId | Should -Be $script:IdB
        $a.Calls | Should -Be 1
        $b.Calls | Should -Be 1
    }

    It 'identifies the store by the default proxy that the service context binds, when the group holds several, and says that the others are not read' {
        $first = Get-TestSecureStoreProxy -Id $script:IdA -Name 'First'
        $second = Get-TestSecureStoreProxy -Id $script:IdB -Name 'Second'
        $group = Get-TestGroup -Proxies @($first, $second) -Applications @((Get-TestTarget -Name 'SapTarget')) -Default $second
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSSecureStoreApplication

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].SecureStoreProxyId | Should -Be $script:IdB
        $result.Applications[0].SecureStoreProxyName | Should -Be 'Second'
        $result.Complete | Should -BeFalse
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match ("The Secure Store proxy 'First' \({0}\) is not the default Secure Store proxy of the service application proxy group of any web application" -f $script:IdA)
        $group.Calls | Should -Be 1
        $group.ContextCalls | Should -Be 1
    }

    It 'reads each default proxy once when groups that hold the same proxies have different defaults, and stays complete' {
        $first = Get-TestSecureStoreProxy -Id $script:IdA -Name 'First'
        $second = Get-TestSecureStoreProxy -Id $script:IdB -Name 'Second'
        $groupA = Get-TestGroup -Proxies @($first, $second) -Applications @((Get-TestTarget -Name 'SapTarget')) -Default $first
        $groupB = Get-TestGroup -Proxies @($first, $second) -Applications @((Get-TestTarget -Name 'CrmTarget')) -Default $second
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $groupA), (Get-TestWebApplication -Url 'https://b' -Group $groupB))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $result.Applications | Should -HaveCount 2
        $result.Applications[0].Name | Should -Be 'SapTarget'
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a'
        $result.Applications[0].SecureStoreProxyId | Should -Be $script:IdA
        $result.Applications[1].Name | Should -Be 'CrmTarget'
        $result.Applications[1].WebApplicationUrls | Should -Be 'https://b'
        $result.Applications[1].SecureStoreProxyId | Should -Be $script:IdB
        $groupA.Calls | Should -Be 1
        $groupB.Calls | Should -Be 1
    }

    It 'reports a proxy once when a group that holds only it and a group that holds it and another one, with it as the default, see it' {
        $first = Get-TestSecureStoreProxy -Id $script:IdA -Name 'First'
        $second = Get-TestSecureStoreProxy -Id $script:IdB -Name 'Second'
        $only = Get-TestGroup -Proxies @($first) -Applications @((Get-TestTarget -Name 'SapTarget'))
        $both = Get-TestGroup -Proxies @($first, $second) -Applications @((Get-TestTarget -Name 'SapTarget')) -Default $first
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $only), (Get-TestWebApplication -Url 'https://b' -Group $both))

        $result = Get-SPSSecureStoreApplication

        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://a; https://b'
        $result.Applications[0].SecureStoreProxyId | Should -Be $script:IdA
        $only.Calls + $both.Calls | Should -Be 1
        $result.Complete | Should -BeFalse
        ($result.Warnings -join ';') | Should -Match "'Second' \($($script:IdB)\) is not the default"
    }

    It 'marks the result incomplete when the default proxy of a group that holds several cannot be told: the IDs and the names are listed in the same order' {
        $zeta = Get-TestSecureStoreProxy -Id $script:IdA -Name 'Zeta'
        $alpha = Get-TestSecureStoreProxy -Id $script:IdB -Name 'Alpha'
        $group = Get-TestGroup -Proxies @($alpha, $zeta) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].SecureStoreProxyId | Should -Be ('{0}; {1}' -f $script:IdA, $script:IdB)
        $result.Applications[0].SecureStoreProxyName | Should -Be 'Zeta; Alpha'
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match "Web application 'https://a' has 2 Secure Store proxies .* default one could not be determined \(the service context has no default Secure Store proxy among them\)"
        $group.Calls | Should -Be 1
    }

    It 'gives the reason when the service context cannot answer for its default proxy, and still reads the store once' {
        $group = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA -Name 'First'), (Get-TestSecureStoreProxy -Id $script:IdB -Name 'Second')) -Applications @((Get-TestTarget -Name 'SapTarget')) -DefaultError 'The default proxy is unavailable'
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match 'default one could not be determined \(.*The default proxy is unavailable.*\)'
        $group.Calls | Should -Be 1
        $group.ContextCalls | Should -Be 1
    }

    It 'does not list the applications of a group that holds several proxies when its service context cannot be built' {
        $group = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA), (Get-TestSecureStoreProxy -Id $script:IdB)) -Applications @((Get-TestTarget -Name 'SapTarget')) -ContextError 'The service context is unavailable'
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 0
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match "The Secure Store applications could not be read for web application 'https://a': The service context is unavailable"
        $group.Calls | Should -Be 0
    }

    It 'warns about a web application that cannot be found and still reads the others' {
        $good = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://good' -Group $good))

        $result = Get-SPSSecureStoreApplication -WebApplicationUrl @('https://stale', 'https://good')

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://good'
        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -Match "The web application 'https://stale' could not be read: Cannot find the web application 'https://stale'"
    }

    It 'warns about every web application that cannot be found, and does not add the note about a missing Secure Store' {
        Set-TestFarm -WebApplications @()

        $result = Get-SPSSecureStoreApplication -WebApplicationUrl @('https://stale', 'https://gone')

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 0
        $result.Warnings | Should -HaveCount 2
        ($result.Warnings -join ';') | Should -Not -Match 'No Secure Store service application proxy'
    }

    It 'returns an empty complete result when the Secure Store defines no application' {
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group (Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)))))

        $result = Get-SPSSecureStoreApplication

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
    }

    It 'returns an empty complete result when the farm has no web application' {
        Set-TestFarm -WebApplications @()

        $result = Get-SPSSecureStoreApplication

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
    }

    It 'marks a Secure Store that cannot be read as incomplete and keeps the other web applications' {
        $broken = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -ListError 'Access is denied'
        $good = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdB)) -Applications @((Get-TestTarget -Name 'CrmTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $broken), (Get-TestWebApplication -Url 'https://b' -Group $good))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].Name | Should -Be 'CrmTarget'
        ($result.Warnings -join ';') | Should -Match "Secure Store applications could not be read for web application 'https://a'"
        ($result.Warnings -join ';') | Should -Match 'Access is denied'
    }

    It 'reports the failure of a Secure Store shared by several web applications once' {
        $shared = Get-TestSecureStoreProxy -Id $script:IdA
        $first = Get-TestGroup -Proxies @($shared) -ListError 'Access is denied'
        $second = Get-TestGroup -Proxies @($shared) -ListError 'Access is denied'
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $first), (Get-TestWebApplication -Url 'https://b' -Group $second))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Warnings | Should -HaveCount 1
        $first.Calls + $second.Calls | Should -Be 1
    }

    It 'marks a service context that cannot be built as incomplete, and does not list the applications' {
        $group = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget')) -ContextError 'The service context is unavailable'
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 0
        ($result.Warnings -join ';') | Should -Match 'The service context is unavailable'
        $group.Calls | Should -Be 0
    }

    It 'marks an unreadable proxy ID as incomplete instead of guessing the store' {
        $noId = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        $empty = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id '00000000-0000-0000-0000-000000000000')) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $noId), (Get-TestWebApplication -Url 'https://b' -Group $empty))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 0
        @($result.Warnings | Where-Object { $_ -match 'ID of a Secure Store proxy could not be read' }) | Should -HaveCount 2
        $noId.Calls + $empty.Calls | Should -Be 0
    }

    It 'marks an unreadable application as incomplete and keeps the others' {
        $group = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @([PSCustomObject]@{ Title = 'no name'; Type = 'Group' }, (Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].Name | Should -Be 'SapTarget'
        ($result.Warnings -join ';') | Should -Match "A Secure Store application could not be read for web application 'https://a'"
        ($result.Warnings -join ';') | Should -Match 'no readable name'
    }

    It 'marks a web application whose proxy group or proxies cannot be read as incomplete and keeps the others' {
        $good = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @(
            (Get-TestWebApplication -Url 'https://good' -Group $good)
            (Get-TestWebApplication -Url 'https://nogroup' -NoProxyGroup)
            (Get-TestWebApplication -Url 'https://noproxies' -NoProxies)
            (Get-TestWebApplication -Url '')
        )

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].WebApplicationUrls | Should -Be 'https://good'
        $good.Calls | Should -Be 1
        ($result.Warnings -join ';') | Should -Match "web application 'https://nogroup': The service application proxy group could not be read"
        ($result.Warnings -join ';') | Should -Match "web application 'https://noproxies': The service application proxies could not be read"
        ($result.Warnings -join ';') | Should -Match "web application '\(unknown web application\)': The web application URL could not be read"
    }

    It 'never writes anything: it only reads' {
        $group = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA)) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group))
        $path = Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/Public/Get-SPSSecureStoreApplication.ps1'

        $commands = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null).FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }

        @($commands | Where-Object { $_ -match '^(Set|New|Remove|Update|Clear|Add|Grant|Revoke)-SP' }) | Should -HaveCount 0
        @($commands | Where-Object { $_ -match 'Credential' -and $_ -ne 'Get-SPSecureStoreApplication' }) | Should -HaveCount 0
    }
}
