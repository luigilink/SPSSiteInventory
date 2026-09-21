# Behavior tests for Measure-SPSSiteComplexity.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:Scoring = @{
        Weights = @{
            Workflow2010Count        = 3.0
            Workflow2013Count        = 1.5
            InfoPathFormCount        = 3.0
            SandboxSolutions         = 3.0
            CustomMasterPage         = 2.0
            EventReceivers           = 1.5
            UniquePermissionsCount   = 0.01
            SizeGB                   = 0.02
        }
        Thresholds = @{
            Moderate = 1.0
            Complex  = 6.0
        }
        BlockingSignals = @(
            'UsesCustomFarmFeature'
            'UsesFullTrustCode'
            'InfoPathFormCount'
        )
    }
}

Describe 'Measure-SPSSiteComplexity' {
    It 'scores a plain site as Simple (category 1)' {
        $signals = @{ Workflow2010Count = 0; Workflow2013Count = 0; SandboxSolutions = 0; SizeGB = 1 }

        $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $script:Scoring

        $result.Category | Should -Be 1
        $result.CategoryName | Should -Be 'Simple'
    }

    It 'promotes a site with a couple of workflows to Moderate (category 2)' {
        $signals = @{ Workflow2013Count = 1 }

        $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $script:Scoring

        $result.Category | Should -Be 2
        $result.CategoryName | Should -Be 'Moderate'
    }

    It 'weighs a 2010 workflow more heavily than a 2013 workflow' {
        $result2010 = Measure-SPSSiteComplexity -Signals @{ Workflow2010Count = 1 } -Scoring $script:Scoring
        $result2013 = Measure-SPSSiteComplexity -Signals @{ Workflow2013Count = 1 } -Scoring $script:Scoring

        $result2010.Score | Should -BeGreaterThan $result2013.Score
    }

    It 'promotes a heavily customized site to Complex (category 3)' {
        $signals = @{ SandboxSolutions = 1; Workflow2010Count = 1; CustomMasterPage = $true }

        $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $script:Scoring

        $result.Score | Should -BeGreaterOrEqual 6
        $result.Category | Should -Be 3
        $result.CategoryName | Should -Be 'Complex'
    }

    It 'forces Blocking (category 4) when a blocking signal is true, whatever the score' {
        $signals = @{ Workflow2010Count = 0; UsesCustomFarmFeature = $true }

        $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $script:Scoring

        $result.Category | Should -Be 4
        $result.CategoryName | Should -Be 'Blocking'
    }

    It 'forces Blocking (category 4) when a site uses InfoPath forms' {
        $signals = @{ InfoPathFormCount = 1 }

        $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $script:Scoring

        $result.Category | Should -Be 4
        $result.CategoryName | Should -Be 'Blocking'
    }

    It 'forces Blocking (category 4) when a site activates custom full-trust code' {
        $signals = @{ UsesFullTrustCode = $true }

        $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $script:Scoring

        $result.Category | Should -Be 4
        $result.CategoryName | Should -Be 'Blocking'
    }

    It 'treats missing signals as zero' {
        $result = Measure-SPSSiteComplexity -Signals @{} -Scoring $script:Scoring

        $result.Category | Should -Be 1
        $result.Score | Should -Be 0
    }

    It 'reports the drivers in Reasons' {
        $signals = @{ SandboxSolutions = 1 }

        $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $script:Scoring

        ($result.Reasons -join ' ') | Should -Match 'SandboxSolutions'
    }

    It 'counts booleans as 1 in the weighted score' {
        $signals = @{ CustomMasterPage = $true }

        $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $script:Scoring

        $result.Score | Should -Be 2
    }
}
