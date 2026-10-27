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
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:ExamplePath = Join-Path $repoRoot 'src/config/inventory-settings.example.psd1'
    }

    It 'treats external lists as a weighted migration blocker because BCS is retired in SharePoint Online' {
        $settings = Import-PowerShellDataFile -Path $script:ExamplePath

        $settings.Scoring.BlockingSignals | Should -Contain 'ExternalListCount'
        $settings.Scoring.Weights.ExternalListCount | Should -BeGreaterThan 0
    }

    It 'classifies a site with an external list as Blocking and a site without one as Simple' {
        $settings = Import-PowerShellDataFile -Path $script:ExamplePath

        $with = Measure-SPSSiteComplexity -Signals @{ ExternalListCount = 1 } -Scoring $settings.Scoring
        $without = Measure-SPSSiteComplexity -Signals @{ ExternalListCount = 0 } -Scoring $settings.Scoring

        $with.Category | Should -Be 4
        $with.Reasons | Should -Contain 'blocking: ExternalListCount'
        $without.Category | Should -Be 1
    }

    It 'documents the alert row cap and keeps SharePoint alerts informational' {
        $settings = Import-PowerShellDataFile -Path $script:ExamplePath

        $settings.LargeContentThresholds.MaxAlertRowsPerSite | Should -Be 5000
        $settings.Scoring.BlockingSignals | Should -Not -Contain 'SharePointAlertCount'
        $settings.Scoring.Weights.ContainsKey('SharePointAlertCount') | Should -BeFalse
    }

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
