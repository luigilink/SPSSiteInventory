# Behavior tests for Get-SPSReportOption (pure, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-Option {
        param ([object]$Settings, [switch]$NoSettings)
        if ($NoSettings) {
            & $script:Module { Get-SPSReportOption }
        }
        else {
            & $script:Module { param ($Section) Get-SPSReportOption -Settings $Section } $Settings
        }
    }
}

Describe 'Get-SPSReportOption' {
    It 'splits above 3000 site collections, on pages of 500, by default: with no section, an empty one or no value' {
        foreach ($option in @((Get-Option -NoSettings), (Get-Option -Settings $null), (Get-Option -Settings @{}), (Get-Option -Settings @{ Other = 1 }))) {
            $option.HtmlSplitThreshold | Should -Be 3000
            $option.HtmlRowsPerPage | Should -Be 500
        }
    }

    It 'returns both options as integers' {
        $option = Get-Option -Settings @{ HtmlSplitThreshold = [long]10; HtmlRowsPerPage = [long]60 }

        $option.HtmlSplitThreshold | Should -BeOfType [int]
        $option.HtmlRowsPerPage | Should -BeOfType [int]
        $option.HtmlSplitThreshold | Should -Be 10
        $option.HtmlRowsPerPage | Should -Be 60
    }

    It 'honors each option on its own, and the bounds of their ranges' {
        (Get-Option -Settings @{ HtmlSplitThreshold = 0 }).HtmlSplitThreshold | Should -Be 0
        (Get-Option -Settings @{ HtmlSplitThreshold = 0 }).HtmlRowsPerPage | Should -Be 500
        (Get-Option -Settings @{ HtmlSplitThreshold = 10000000 }).HtmlSplitThreshold | Should -Be 10000000
        (Get-Option -Settings @{ HtmlRowsPerPage = 50 }).HtmlRowsPerPage | Should -Be 50
        (Get-Option -Settings @{ HtmlRowsPerPage = 5000 }).HtmlRowsPerPage | Should -Be 5000
        (Get-Option -Settings @{ HtmlRowsPerPage = 5000 }).HtmlSplitThreshold | Should -Be 3000
        (Get-Option -Settings ([ordered]@{ HtmlSplitThreshold = 1; HtmlRowsPerPage = 100 })).HtmlRowsPerPage | Should -Be 100
    }

    It 'rejects <Description> for <Name> instead of coercing it' -ForEach @(
        @{ Name = 'HtmlSplitThreshold'; Description = "the text '3000'"; Value = '3000' }
        @{ Name = 'HtmlSplitThreshold'; Description = 'a boolean'; Value = $true }
        @{ Name = 'HtmlSplitThreshold'; Description = 'a null value'; Value = $null }
        @{ Name = 'HtmlSplitThreshold'; Description = 'a negative number'; Value = -1 }
        @{ Name = 'HtmlSplitThreshold'; Description = 'a number above the range'; Value = 10000001 }
        @{ Name = 'HtmlSplitThreshold'; Description = 'a fraction'; Value = 2.5 }
        @{ Name = 'HtmlRowsPerPage'; Description = 'a number below the range'; Value = 49 }
        @{ Name = 'HtmlRowsPerPage'; Description = 'a number above the range'; Value = 5001 }
        @{ Name = 'HtmlRowsPerPage'; Description = 'an empty string'; Value = '' }
        @{ Name = 'HtmlRowsPerPage'; Description = 'a boolean'; Value = $false }
    ) {
        { Get-Option -Settings @{ $Name = $Value } } | Should -Throw -ExpectedMessage "Report.$Name must be a whole number from*"
    }
}
