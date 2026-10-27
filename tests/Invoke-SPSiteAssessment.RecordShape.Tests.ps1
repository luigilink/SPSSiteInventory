# The inventory record is what the CSV, the JSON and the HTML report show. A signal that is scored
# but is not a field of the record cannot be filtered, sorted or checked: these tests keep that from happening again.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # The fields of the record, read from the code that builds it: once for an assessed site, once for a failed assessment.
    $assessment = Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/Private/Invoke-SPSiteAssessment.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($assessment, [ref]$null, [ref]$null)
    $tables = $ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true)
    $script:Record = @()
    foreach ($table in $tables) {
        $keys = @($table.KeyValuePairs | ForEach-Object { [System.String]$_.Item1.Value })
        if ($keys -contains 'AssessmentStatus' -and $keys -contains 'Score' -and $keys -contains 'Workflow2010Count') {
            $script:Record += , $keys
        }
    }

    $script:Settings = Get-SPSInventorySetting -Path (Join-Path $repoRoot 'src/config/inventory-settings.example.psd1')
    $script:Usage = Get-Content -Path (Join-Path $repoRoot 'wiki/Usage.md') -Raw
    $script:ClassicSignal = @('UsesCustomFarmFeature', 'SandboxSolutions', 'CustomMasterPage', 'EventReceivers', 'UniquePermissionsCount')
}

Describe 'The inventory record' {
    It 'is built in two places, for an assessed site and for a failed assessment' {
        $script:Record | Should -HaveCount 2
        $script:Record[0].Count | Should -BeGreaterThan 50
    }

    It 'has the same fields when the assessment failed, so that the columns of the CSV line up' {
        $assessed = @($script:Record[0] | Sort-Object)
        $failed = @($script:Record[1] | Sort-Object)

        @($assessed | Where-Object { $failed -notcontains $_ }) | Should -BeNullOrEmpty
        @($failed | Where-Object { $assessed -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'has a field for every signal that the example configuration weights' {
        foreach ($signal in $script:Settings.Scoring.Weights.Keys) {
            $script:Record[0] | Should -Contain $signal -Because "the example configuration weights $signal, so a report must show it"
        }
    }

    It 'has a field for every blocking signal of the example configuration' {
        foreach ($signal in $script:Settings.Scoring.BlockingSignals) {
            $script:Record[0] | Should -Contain $signal -Because "the example configuration blocks on $signal, so a report must show it"
        }
    }

    It 'has a field for each classic customization signal, which were scored from 1.0.0 without being fields' {
        foreach ($signal in $script:ClassicSignal) {
            $script:Record[0] | Should -Contain $signal
            $script:Record[1] | Should -Contain $signal
        }
    }

    It 'documents each classic customization signal in the usage page' {
        foreach ($signal in $script:ClassicSignal) {
            $script:Usage | Should -Match ('\| `{0}` \|' -f $signal) -Because "$signal must be documented"
        }
    }
}
