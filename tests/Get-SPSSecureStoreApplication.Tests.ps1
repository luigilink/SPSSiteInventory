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
        param ([object[]]$Proxies = @(), [object[]]$Applications = @(), [string]$ListError = '', [string]$ContextError = '')
        [PSCustomObject]@{ Proxies = $Proxies; Applications = $Applications; ListError = $ListError; ContextError = $ContextError; Calls = 0; ContextCalls = 0 }
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
            if ($Identity) { return @($global:SPSTestSecureStoreWebApplications | Where-Object { $_.Url -eq $Identity }) }
            $global:SPSTestSecureStoreWebApplications
        }
        Mock Get-SPSProxyGroupServiceContext -ModuleName SPSSiteInventory.Common -MockWith {
            $ProxyGroup.ContextCalls++
            if ($ProxyGroup.ContextError) { throw $ProxyGroup.ContextError }
            [PSCustomObject]@{ Group = $ProxyGroup }
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

    It 'reports no Secure Store, without a warning and without reading anything, for a web application whose proxy group has no Secure Store proxy' {
        $group = Get-TestGroup -Proxies @((Get-TestOtherProxy))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group), (Get-TestWebApplication -Url 'https://b' -Group (Get-TestGroup)))

        $result = Get-SPSSecureStoreApplication

        $result.Applications | Should -HaveCount 0
        $result.Complete | Should -BeTrue
        $result.Warnings | Should -HaveCount 0
        $group.ContextCalls | Should -Be 0
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

    It 'marks the result incomplete when a proxy group holds several Secure Store proxies: a service context binds the default one only' {
        $group = Get-TestGroup -Proxies @((Get-TestSecureStoreProxy -Id $script:IdA -Name 'First'), (Get-TestSecureStoreProxy -Id $script:IdB -Name 'Second')) -Applications @((Get-TestTarget -Name 'SapTarget'))
        Set-TestFarm -WebApplications @((Get-TestWebApplication -Url 'https://a' -Group $group))

        $result = Get-SPSSecureStoreApplication

        $result.Complete | Should -BeFalse
        $result.Applications | Should -HaveCount 1
        $result.Applications[0].SecureStoreProxyId | Should -Be ('{0}; {1}' -f $script:IdA, $script:IdB)
        $result.Applications[0].SecureStoreProxyName | Should -Be 'First; Second'
        ($result.Warnings -join ';') | Should -Match "Web application 'https://a' has 2 Secure Store proxies"
        $group.Calls | Should -Be 1
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
