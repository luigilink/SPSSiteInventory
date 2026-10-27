# Behavior tests for Get-SPSSharePointAlertOption (pure, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-Option {
        param ([object]$Settings, [switch]$NoSettings)
        if ($NoSettings) {
            & $script:Module { Get-SPSSharePointAlertOption }
        }
        else {
            & $script:Module { param ($Section) Get-SPSSharePointAlertOption -Settings $Section } $Settings
        }
    }
}

Describe 'Get-SPSSharePointAlertOption' {
    It 'includes the user login by default, when there is no section, an empty one or no value' {
        (Get-Option -NoSettings).IncludeUserLogin | Should -BeTrue
        (Get-Option -Settings $null).IncludeUserLogin | Should -BeTrue
        (Get-Option -Settings @{}).IncludeUserLogin | Should -BeTrue
        (Get-Option -Settings @{ Other = 1 }).IncludeUserLogin | Should -BeTrue
    }

    It 'honors an explicit boolean' {
        (Get-Option -Settings @{ IncludeUserLogin = $false }).IncludeUserLogin | Should -BeFalse
        (Get-Option -Settings @{ IncludeUserLogin = $true }).IncludeUserLogin | Should -BeTrue
        (Get-Option -Settings ([ordered]@{ IncludeUserLogin = $false })).IncludeUserLogin | Should -BeFalse
    }

    It 'rejects <Description> instead of coercing it, so a typo cannot collect the names' -ForEach @(
        @{ Description = "the string 'false'"; Value = 'false' }
        @{ Description = 'the number 0'; Value = 0 }
        @{ Description = 'the number 1'; Value = 1 }
        @{ Description = 'an empty string'; Value = '' }
        @{ Description = 'a null value'; Value = $null }
    ) {
        { Get-Option -Settings @{ IncludeUserLogin = $Value } } | Should -Throw -ExpectedMessage '*SharePointAlerts.IncludeUserLogin must be $true or $false*'
    }
}
