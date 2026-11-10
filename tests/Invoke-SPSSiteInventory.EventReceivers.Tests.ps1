# The orchestrator reads SharePoint, so it cannot run here: these tests read its code, and check that the assemblies of the inspected
# packages are indexed once, in the module, only when there are packages, that the index reaches the assessment, that the event receiver
# rows reach the export, and that the files are logged.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:Path = Join-Path $repoRoot 'src/Invoke-SPSSiteInventory.ps1'
    $script:Text = Get-Content -LiteralPath $script:Path -Raw
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$null)
    $script:Commands = @($script:Ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))

    function Get-CommandText {
        param ([string]$Name)
        @($script:Commands | Where-Object { $_.GetCommandName() -eq $Name })
    }

    # The condition of the if, or of the elseif, that holds the node.
    function Get-EnclosingCondition {
        param ($Node)
        $parent = $Node.Parent
        while ($null -ne $parent) {
            if ($parent -is [System.Management.Automation.Language.IfStatementAst]) {
                foreach ($clause in $parent.Clauses) {
                    if ($clause.Item2.Extent.StartOffset -le $Node.Extent.StartOffset -and $clause.Item2.Extent.EndOffset -ge $Node.Extent.EndOffset) {
                        return $clause.Item1.Extent.Text
                    }
                }
            }
            $parent = $parent.Parent
        }
        return $null
    }
}

Describe 'Invoke-SPSSiteInventory.ps1 and the event receivers' {
    It 'is valid PowerShell' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It 'indexes the assemblies of the inspected packages once, in the module, and only when there are packages' {
        $call = @(Get-CommandText -Name 'Get-SPSSolutionAssemblyIndex')

        $call | Should -HaveCount 1
        $call[0].Extent.Text | Should -Be 'Get-SPSSolutionAssemblyIndex -SolutionPackages $SolutionPackage'
        (Get-EnclosingCondition -Node $call[0]) | Should -Be '@($SolutionPackage).Count -gt 0'
        $script:Text | Should -Match '\$solutionAssemblyIndex = \$null\s+if \(@\(\$SolutionPackage\)\.Count -gt 0\)'
    }

    It 'reads the packages before it indexes their assemblies, and indexes them before the export' {
        $index = $script:Text.IndexOf('Get-SPSSolutionAssemblyIndex -SolutionPackages')

        $index | Should -BeGreaterThan $script:Text.IndexOf('Get-SPSSolutionPackageInfo @packageParams')
        $index | Should -BeLessThan $script:Text.IndexOf('$output = Export-SPSInventoryReport')
    }

    It 'gives the index to the assessment, and the inspected packages to the block that builds it' {
        $call = @(Get-CommandText -Name 'Invoke-SPSiteAssessment')

        $call | Should -HaveCount 1
        $call[0].Extent.Text | Should -Match '-SolutionAssemblyIndex \$solutionAssemblyIndex -TargetMode \$TargetMode$'
        $script:Text | Should -Match 'param \(\$Inventory, \$CustomFeatureId, \$FullTrustFeatureId, \$Scoring, \$LargeContentThresholds, \$PermissionLevels, \$SharePointAlertSettings, \$TargetMode, \$SolutionPackage\)'
        $script:Text | Should -Match '\} \$inventory \$customFeatureId \$fullTrustFeatureId \$settings\.Scoring \$largeContentThresholds \$permissionLevels \$sharePointAlertSettings \$targetMode \$solutionPackages\r?\n'
    }

    It 'gives the event receiver rows of the assessment to the export, before the splat of the packages' {
        $export = @(Get-CommandText -Name 'Export-SPSInventoryReport')

        $script:Text | Should -Match '\$eventReceiverClasses = @\(\$assessment\.EventReceiverClasses\)'
        $export | Should -HaveCount 1
        $export[0].Extent.Text | Should -Match '-EventReceiverClasses \$eventReceiverClasses '
        $export[0].Extent.Text.IndexOf('-EventReceiverClasses') | Should -BeLessThan $export[0].Extent.Text.IndexOf('@packageExportParams')
        $script:Text.IndexOf('$eventReceiverClasses = @($assessment.EventReceiverClasses)') | Should -BeLessThan $script:Text.IndexOf('$output = Export-SPSInventoryReport')
    }

    It 'logs the paths of the event receiver report, once, at the information level' {
        $event = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Add-SPSInventoryEvent' -and $_.Extent.Text -match 'Event receiver report\.' })

        $event | Should -HaveCount 1
        $event[0].Extent.Text | Should -Match 'CSV: \$\(\$output\.EventReceiversCsvPath\) \| JSON: \$\(\$output\.EventReceiversJsonPath\)'
        $event[0].Extent.Text | Should -Match '-Level Information'
    }
}
