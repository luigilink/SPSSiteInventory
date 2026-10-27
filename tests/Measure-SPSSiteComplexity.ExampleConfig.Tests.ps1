# The example configuration is documented in the wiki: these tests keep the documented behavior true.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Settings = Get-SPSInventorySetting -Path (Join-Path $repoRoot 'src/config/inventory-settings.example.psd1')
    $script:Wiki = Get-Content -Path (Join-Path $repoRoot 'wiki/Configuration.md') -Raw
}

Describe 'The example configuration and the subsite structure' {
    It 'weights the subsite count and depth lightly' {
        $script:Settings.Scoring.Weights['SubsiteCount'] | Should -BeGreaterThan 0
        $script:Settings.Scoring.Weights['SubsiteCount'] | Should -BeLessThan 0.2
        $script:Settings.Scoring.Weights['MaxSubsiteDepth'] | Should -BeGreaterThan 0
        $script:Settings.Scoring.Weights['MaxSubsiteDepth'] | Should -BeLessThan 0.5
    }

    It 'never blocks on the subsite structure, as the issue asks' {
        $script:Settings.Scoring.BlockingSignals | Should -Not -Contain 'SubsiteCount'
        $script:Settings.Scoring.BlockingSignals | Should -Not -Contain 'MaxSubsiteDepth'
    }

    It 'keeps a few subsites Simple and does not block a deep hierarchy' {
        $few = Measure-SPSSiteComplexity -Signals @{ SubsiteCount = 5; MaxSubsiteDepth = 1 } -Scoring $script:Settings.Scoring
        $deep = Measure-SPSSiteComplexity -Signals @{ SubsiteCount = 60; MaxSubsiteDepth = 8 } -Scoring $script:Settings.Scoring

        $few.CategoryName | Should -Be 'Simple'
        $deep.CategoryName | Should -Not -Be 'Blocking'
    }

    It 'makes a site Moderate from 15 subsites directly below the root web, or from four levels of subsites, as the wiki says' {
        (Measure-SPSSiteComplexity -Signals @{ SubsiteCount = 14; MaxSubsiteDepth = 1 } -Scoring $script:Settings.Scoring).CategoryName | Should -Be 'Simple'
        (Measure-SPSSiteComplexity -Signals @{ SubsiteCount = 15; MaxSubsiteDepth = 1 } -Scoring $script:Settings.Scoring).CategoryName | Should -Be 'Moderate'
        (Measure-SPSSiteComplexity -Signals @{ SubsiteCount = 3; MaxSubsiteDepth = 3 } -Scoring $script:Settings.Scoring).CategoryName | Should -Be 'Simple'
        (Measure-SPSSiteComplexity -Signals @{ SubsiteCount = 4; MaxSubsiteDepth = 4 } -Scoring $script:Settings.Scoring).CategoryName | Should -Be 'Moderate'
        $script:Wiki | Should -Match 'from 15 subsites directly below\s+the root web, or from four levels of subsites'
    }

    It 'documents the same weights as the example configuration' {
        $script:Wiki | Should -Match ('SubsiteCount\s+= {0}' -f $script:Settings.Scoring.Weights['SubsiteCount'].ToString([System.Globalization.CultureInfo]::InvariantCulture))
        $script:Wiki | Should -Match ('MaxSubsiteDepth\s+= {0}' -f $script:Settings.Scoring.Weights['MaxSubsiteDepth'].ToString([System.Globalization.CultureInfo]::InvariantCulture))
    }
}
