# Behavior tests for Get-SPSInventorySetting.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'Get-SPSInventorySetting' {
    It 'loads a valid settings file and returns a hashtable with a Scoring section' {
        $path = Join-Path $TestDrive 'inventory-settings.psd1'
        @'
@{
    EnvName = 'TEST'
    Scoring = @{
        Weights = @{ SandboxSolutions = 3.0 }
        Thresholds = @{ Moderate = 1.0; Complex = 6.0 }
        BlockingSignals = @('UsesCustomFarmFeature')
    }
}
'@ | Set-Content -Path $path -Encoding UTF8

        $settings = Get-SPSInventorySetting -Path $path

        $settings | Should -BeOfType [hashtable]
        $settings.EnvName | Should -Be 'TEST'
        $settings.Scoring.Thresholds.Complex | Should -Be 6.0
    }

    It 'throws when the file does not exist' {
        $missing = Join-Path $TestDrive 'does-not-exist.psd1'

        { Get-SPSInventorySetting -Path $missing } | Should -Throw
    }

    It 'throws when the mandatory Scoring section is missing' {
        $path = Join-Path $TestDrive 'no-scoring.psd1'
        "@{ EnvName = 'TEST' }" | Set-Content -Path $path -Encoding UTF8

        { Get-SPSInventorySetting -Path $path } | Should -Throw '*Scoring*'
    }
}

Describe 'Example settings file' {
    It 'the shipped example is a valid settings file' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $example  = Join-Path $repoRoot 'src/config/inventory-settings.example.psd1'

        $settings = Import-PowerShellDataFile -Path $example

        $settings.ContainsKey('Scoring') | Should -BeTrue
        $settings.Scoring.ContainsKey('Weights') | Should -BeTrue
        $settings.Scoring.ContainsKey('Thresholds') | Should -BeTrue
        $settings.Scoring.ContainsKey('BlockingSignals') | Should -BeTrue
    }
}
