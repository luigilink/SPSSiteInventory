# Behavior tests for Resolve-SPSContextProxy (no farm needed: the service context and the proxies are fakes).
BeforeAll {
    $script:ModulePath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $script:ModulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:IdA = '11111111-1111-1111-1111-111111111111'
    $script:IdB = '22222222-2222-2222-2222-222222222222'
    $script:IdC = '33333333-3333-3333-3333-333333333333'

    function Get-TestCandidate {
        param ([string] $Id, [string] $Name)
        [PSCustomObject]@{ Id = $Id; Name = $Name; Proxy = [PSCustomObject]@{ Id = [guid]$Id; Name = $Name } }
    }

    # A context whose default proxy is the one given (or none), that records the type it was asked for.
    function Get-TestContext {
        param ($Default, [string] $Failure = '')
        $context = [PSCustomObject]@{ Default = $Default; Failure = $Failure; AskedTypes = [System.Collections.Generic.List[object]]::new() }
        $context | Add-Member -MemberType ScriptMethod -Name GetDefaultProxy -Value {
            param ($Type)
            $this.AskedTypes.Add($Type)
            if ($this.Failure) { throw $this.Failure }
            $this.Default
        }
        $context
    }

    function Resolve-Proxy {
        param ($Candidate, $Context)
        & $script:Module { param ($Candidate, $Context) Resolve-SPSContextProxy -Candidate $Candidate -ServiceContext $Context } $Candidate $Context
    }
}

Describe 'Resolve-SPSContextProxy' {
    It 'returns the only proxy of a group without asking the context' {
        $only = Get-TestCandidate -Id $script:IdA -Name 'Only'
        $context = Get-TestContext -Default $null

        $result = Resolve-Proxy -Candidate @($only) -Context $context

        $result.Id | Should -Be $script:IdA
        $context.AskedTypes | Should -HaveCount 0
    }

    It 'returns the proxy that the service context binds, matched by its ID, whatever its position and its name' {
        $first = Get-TestCandidate -Id $script:IdA -Name 'First'
        $second = Get-TestCandidate -Id $script:IdB -Name 'Second'
        $third = Get-TestCandidate -Id $script:IdC -Name 'First'
        $context = Get-TestContext -Default ([PSCustomObject]@{ Id = [guid]$script:IdB; Name = 'First' })

        $result = Resolve-Proxy -Candidate @($first, $second, $third) -Context $context

        $result.Id | Should -Be $script:IdB
        $result.Name | Should -Be 'Second'
    }

    It 'asks the context for the type of the proxies of the group, once' {
        $first = Get-TestCandidate -Id $script:IdA -Name 'First'
        $second = Get-TestCandidate -Id $script:IdB -Name 'Second'
        $context = Get-TestContext -Default $second.Proxy

        $null = Resolve-Proxy -Candidate @($first, $second) -Context $context

        $context.AskedTypes | Should -HaveCount 1
        $context.AskedTypes[0] | Should -Be $first.Proxy.GetType()
    }

    It 'returns nothing when the context has no default proxy of the type, or one that is not in the group' {
        $first = Get-TestCandidate -Id $script:IdA -Name 'First'
        $second = Get-TestCandidate -Id $script:IdB -Name 'Second'

        Resolve-Proxy -Candidate @($first, $second) -Context (Get-TestContext -Default $null) | Should -BeNullOrEmpty
        Resolve-Proxy -Candidate @($first, $second) -Context (Get-TestContext -Default ([PSCustomObject]@{ Id = [guid]$script:IdC; Name = 'Other' })) | Should -BeNullOrEmpty
        Resolve-Proxy -Candidate @($first, $second) -Context (Get-TestContext -Default ([PSCustomObject]@{ Name = 'No ID' })) | Should -BeNullOrEmpty
    }

    It 'lets the failure of the context through, so that the caller can mark its inventory incomplete' {
        $first = Get-TestCandidate -Id $script:IdA -Name 'First'
        $second = Get-TestCandidate -Id $script:IdB -Name 'Second'

        { Resolve-Proxy -Candidate @($first, $second) -Context (Get-TestContext -Default $null -Failure 'The proxy is unavailable') } | Should -Throw '*The proxy is unavailable*'
    }
}
