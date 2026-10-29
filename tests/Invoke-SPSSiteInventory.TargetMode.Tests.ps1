# The orchestrator reads SharePoint, so it cannot run here: these tests read its code, and check that the target mode
# is read once from the settings, given to the scoring and to the export, and that the warnings that only make sense
# for a migration to SharePoint Online are not raised in the other mode.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:Path = Join-Path $repoRoot 'src/Invoke-SPSSiteInventory.ps1'
    $script:Text = Get-Content -LiteralPath $script:Path -Raw
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$null)
    $script:Commands = @($script:Ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))

    function Get-CommandText {
        param ([string]$Name)
        @($script:Commands | Where-Object { $_.GetCommandName() -eq $Name } | ForEach-Object { $_.Extent.Text })
    }

    # The warnings of the orchestrator that talk about SharePoint Online: each is an if whose body logs a Warning.
    $script:Warnings = @($script:Ast.FindAll({
                param ($node)
                $node -is [System.Management.Automation.Language.IfStatementAst] -and
                $node.Clauses[0].Item2.Extent.Text -match '-Level Warning'
            }, $true) | ForEach-Object { $_ })
}

Describe 'Invoke-SPSSiteInventory.ps1 and the target mode' {
    It 'is valid PowerShell' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It 'reads the target mode from the settings, with the default mode when the setting is missing, and logs it' {
        $script:Text | Should -Match "Get-SPSTargetProfile -TargetMode"
        $script:Text | Should -Match "ContainsKey\('TargetMode'\)\) \{ \`$settings\.TargetMode \} else \{ 'SharePointOnline' \}"
        $script:Text | Should -Match 'Target mode: \{0\} \(\{1\}\)'
    }

    It 'gives the target mode to the assessment, which scores, and to the export, which words the reports' {
        @(Get-CommandText -Name 'Invoke-SPSiteAssessment') | Should -HaveCount 1
        @(Get-CommandText -Name 'Invoke-SPSiteAssessment')[0] | Should -Match '-TargetMode \$TargetMode'
        $script:Text | Should -Match '\} \$inventory \$customFeatureId \$fullTrustFeatureId \$settings\.Scoring \$largeContentThresholds \$permissionLevels \$sharePointAlertSettings \$targetMode'
        @(Get-CommandText -Name 'Export-SPSInventoryReport') | Should -HaveCount 1
        @(Get-CommandText -Name 'Export-SPSInventoryReport')[0] | Should -Match '-TargetMode \$targetMode'
    }

    It 'plans the default waves of the mode, and no longer a fixed list, when the settings have none' {
        $script:Text | Should -Match '@\(\$targetProfile\.MigrationWave\)'
        $script:Text | Should -Not -Match "Name = 'Quick wins'"
        $script:Text | Should -Not -Match "Name = 'Projects / blockers'"
    }

    It 'raises the warnings about the blocking signals of a migration to SharePoint Online only in that mode' {
        $about = @('HasFbaZone', 'IsUnsupportedSiteTemplate', 'HasNoAccessLock', 'IrmEnabledListCount', 'ExternalListCount')
        foreach ($signal in $about) {
            $warning = @($script:Warnings | Where-Object { $_.Clauses[0].Item1.Extent.Text -match ("-notcontains '{0}'" -f $signal) })

            $warning | Should -HaveCount 1 -Because "there is one warning about $signal"
            $warning[0].Clauses[0].Item1.Extent.Text | Should -Match "\`$targetMode -eq 'SharePointOnline'" -Because "the warning about $signal only fits a migration"
        }
    }

    It 'leaves the warnings that fit both modes without a condition on the mode' {
        $both = @($script:Warnings | Where-Object { $_.Clauses[0].Item2.Extent.Text -match 'custom permission levels|template languages require review' })

        $both | Should -HaveCount 2
        foreach ($warning in $both) {
            $warning.Clauses[0].Item1.Extent.Text | Should -Not -Match 'targetMode'
        }
    }

    It 'gives the readiness script the example of each mode, so that its comparison follows the mode' {
        $readiness = Get-Content -LiteralPath (Join-Path (Split-Path $script:Path -Parent) 'Test-SPSSiteInventoryReadiness.ps1') -Raw

        $readiness | Should -Match 'inventory-settings\.onprem\.example\.psd1'
        $readiness | Should -Match '-OnPremExampleConfigPath \$onPremExampleConfigPath'
    }
}
