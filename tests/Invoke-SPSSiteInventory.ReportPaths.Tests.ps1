# The orchestrator reads SharePoint, so it cannot run here: this test reads its code and the code of the export. Every path that
# the export returns has to be in the log of the run, which is where the person who runs the inventory finds the files.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:OrchestratorText = Get-Content -LiteralPath (Join-Path $repoRoot 'src/Invoke-SPSSiteInventory.ps1') -Raw
    $exportPath = Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/Public/Export-SPSInventoryReport.ps1'
    $exportAst = [System.Management.Automation.Language.Parser]::ParseFile($exportPath, [ref]$null, [ref]$null)

    # The object that the export returns is the hashtable that has the path of the manifest.
    $tables = @($exportAst.FindAll({ param ($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true))
    $output = @($tables | Where-Object { @($_.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text }) -contains 'ManifestJsonPath' }) | Select-Object -Last 1
    $script:OutputKeys = @($output.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text })
}

Describe 'The paths that the export returns, in the log of Invoke-SPSSiteInventory.ps1' {
    It 'finds the object that the export returns' {
        $script:OutputKeys | Should -Contain 'ManifestJsonPath'
        $script:OutputKeys | Should -Contain 'CollaborationJsonPath'
        $script:OutputKeys.Count | Should -BeGreaterThan 20
    }

    It 'logs <_>' -ForEach @(
        'CsvPath', 'JsonPath', 'HtmlPath', 'HtmlPagePaths', 'SitesJsonPath', 'AuthJsonPath', 'WorkflowsJsonPath', 'AppsJsonPath', 'PublishingJsonPath',
        'PermissionsJsonPath', 'IrmLocksJsonPath', 'LargeContentJsonPath', 'CollaborationJsonPath', 'AlertsJsonPath', 'AlertsCsvPath', 'ManifestJsonPath'
    ) {
        $script:OrchestratorText | Should -Match ([regex]::Escape('$output.' + $_))
    }

    It 'logs every path that the export returns, so that a file that is added to the export is not left out of the log' {
        $missing = @($script:OutputKeys | Where-Object { $script:OrchestratorText -notmatch [regex]::Escape('$output.' + $_) })

        $missing | Should -HaveCount 0 -Because ('these paths are returned by the export and not logged: ' + ($missing -join ', '))
    }
}
