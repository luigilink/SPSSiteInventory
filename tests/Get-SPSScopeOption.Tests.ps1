# Behavior tests for Get-SPSScopeOption (pure, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-Option {
        param ([object]$Settings, [switch]$NoSettings)
        if ($NoSettings) {
            & $script:Module { Get-SPSScopeOption }
        }
        else {
            & $script:Module { param ($Section) Get-SPSScopeOption -Settings $Section } $Settings
        }
    }
}

Describe 'Get-SPSScopeOption' {
    It 'leaves out personal sites and site masters by default, when there is no section, an empty one or no value' {
        foreach ($option in @((Get-Option -NoSettings), (Get-Option -Settings $null), (Get-Option -Settings @{}), (Get-Option -Settings @{ Other = 1 }))) {
            $option.IncludePersonalSites | Should -BeFalse
            $option.IncludeSiteMasters | Should -BeFalse
        }
    }

    It 'returns both options as booleans' {
        $option = Get-Option -Settings @{}

        $option.IncludePersonalSites | Should -BeOfType [bool]
        $option.IncludeSiteMasters | Should -BeOfType [bool]
    }

    It 'honors an explicit boolean for each option on its own' {
        $personal = Get-Option -Settings @{ IncludePersonalSites = $true }
        $personal.IncludePersonalSites | Should -BeTrue
        $personal.IncludeSiteMasters | Should -BeFalse

        $masters = Get-Option -Settings @{ IncludeSiteMasters = $true }
        $masters.IncludePersonalSites | Should -BeFalse
        $masters.IncludeSiteMasters | Should -BeTrue

        $both = Get-Option -Settings ([ordered]@{ IncludePersonalSites = $true; IncludeSiteMasters = $true })
        $both.IncludePersonalSites | Should -BeTrue
        $both.IncludeSiteMasters | Should -BeTrue

        $off = Get-Option -Settings @{ IncludePersonalSites = $false; IncludeSiteMasters = $false }
        $off.IncludePersonalSites | Should -BeFalse
        $off.IncludeSiteMasters | Should -BeFalse
    }

    It 'rejects <Description> for <Name> instead of coercing it' -ForEach @(
        @{ Name = 'IncludePersonalSites'; Description = "the string 'false'"; Value = 'false' }
        @{ Name = 'IncludePersonalSites'; Description = 'the number 0'; Value = 0 }
        @{ Name = 'IncludePersonalSites'; Description = "the string 'yes'"; Value = 'yes' }
        @{ Name = 'IncludePersonalSites'; Description = 'a null value'; Value = $null }
        @{ Name = 'IncludeSiteMasters'; Description = "the string 'false'"; Value = 'false' }
        @{ Name = 'IncludeSiteMasters'; Description = 'the number 1'; Value = 1 }
        @{ Name = 'IncludeSiteMasters'; Description = "the string 'yes'"; Value = 'yes' }
        @{ Name = 'IncludeSiteMasters'; Description = 'an empty string'; Value = '' }
    ) {
        { Get-Option -Settings @{ $Name = $Value } } | Should -Throw -ExpectedMessage "*Scope.$Name must be `$true or `$false.*"
    }

    It 'rejects an invalid option even when the other one is valid' {
        { Get-Option -Settings @{ IncludePersonalSites = $true; IncludeSiteMasters = 'true' } } | Should -Throw -ExpectedMessage '*Scope.IncludeSiteMasters must be $true or $false*'
    }
}
