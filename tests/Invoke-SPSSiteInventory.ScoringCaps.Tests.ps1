# The orchestrator reads SharePoint, so it cannot run here: these tests read its code, and check that it logs the caps of
# the scoring that are in force when the scan starts, and only then.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:Path = Join-Path $repoRoot 'src/Invoke-SPSSiteInventory.ps1'
    $script:Text = Get-Content -LiteralPath $script:Path -Raw
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$null)
}

Describe 'Invoke-SPSSiteInventory.ps1 and the scoring caps' {
    It 'reads the caps of the settings through the module, with the function that the scoring uses, and says them with the formatter' {
        $script:Text | Should -Match 'Format-SPSScoringCap -Cap \(Get-SPSScoringCap -Scoring \$Scoring\)\s+\} \$settings\.Scoring'
    }

    It 'logs them as information, only when there is one' {
        $logs = @($script:Ast.FindAll({
                    param ($node)
                    $node -is [System.Management.Automation.Language.IfStatementAst] -and
                    $node.Clauses[0].Item1.Extent.Text -match 'IsNullOrEmpty\(\$scoringCapText\)'
                }, $true))

        $logs | Should -HaveCount 1
        $logs[0].Clauses[0].Item1.Extent.Text | Should -Match '^-not '
        $logs[0].Clauses[0].Item2.Extent.Text | Should -Match 'Add-SPSInventoryEvent -Message \("Scoring caps: \{0\}\.'
        $logs[0].Clauses[0].Item2.Extent.Text | Should -Match '-Level Information'
    }

    It 'logs them after the target mode and before the report folder, with the other lines that say how the scan is set' {
        $mode = $script:Text.IndexOf('Target mode: {0}')
        $caps = $script:Text.IndexOf('Scoring caps: {0}')
        $folder = $script:Text.IndexOf('Report folder: ')

        $mode | Should -BeGreaterThan -1
        $caps | Should -BeGreaterThan $mode
        $folder | Should -BeGreaterThan $caps
    }
}
