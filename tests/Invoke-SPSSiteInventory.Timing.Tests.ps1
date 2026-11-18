# The orchestrator reads SharePoint, so it cannot run here: these tests read its code, and check that the run is timed as a whole and
# phase by phase, that the durations reach the manifest, and that the log ends with the recap.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:Path = Join-Path $repoRoot 'src/Invoke-SPSSiteInventory.ps1'
    $script:Text = Get-Content -LiteralPath $script:Path -Raw
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$null)
    $script:Commands = @($script:Ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))

    # The phases, in the order of the run.
    $script:Phase = @(
        'Loading the settings and the SharePoint commands'
        'Building the farm-solution map'
        'Inspecting the solution packages'
        'Enumerating the site collections'
        'Collecting the customization signals'
        'Reading the Business Connectivity Services definitions'
        'Reading the Secure Store target applications'
        'Reading the profile property mappings'
        'Writing the reports'
    )
}

Describe 'Invoke-SPSSiteInventory.ps1 and the duration of the scan' {
    It 'is valid PowerShell' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It 'starts the clocks of the run and of the first phase before anything is logged, in the try block' {
        $start = $script:Text.IndexOf('$scanWatch = [System.Diagnostics.Stopwatch]::StartNew()')

        $start | Should -BeGreaterThan $script:Text.IndexOf('try {')
        $script:Text.IndexOf('$phaseWatch = [System.Diagnostics.Stopwatch]::StartNew()') | Should -BeGreaterThan 0
        $script:Text.IndexOf('$scanStartedAt = Get-Date') | Should -BeGreaterThan 0
        $firstLog = $script:Text.IndexOf('Add-SPSInventoryEvent -Message "SPSSiteInventory $($context.Version) started by')
        $firstLog | Should -BeGreaterThan 0
        $start | Should -BeLessThan $firstLog
        $script:Text.IndexOf('$phaseWatch = [System.Diagnostics.Stopwatch]::StartNew()') | Should -BeLessThan $firstLog
    }

    It 'ends each phase once, in the order of the run, through the private function of the module' {
        $position = foreach ($name in $script:Phase) {
            [regex]::Matches($script:Text, [regex]::Escape("& `$endPhase '$name'")).Count | Should -Be 1 -Because $name
            $script:Text.IndexOf("& `$endPhase '$name'")
        }

        @($position) | Should -Be @($position | Sort-Object)
        $script:Text | Should -Match 'Complete-SPSScanPhase -Name \$PhaseName -Stopwatch \$Watch -Timing \$Rows -Detail \$PhaseDetail'
        $script:Text | Should -Match '\} \$Name \$phaseWatch \$phaseTiming \$Detail'
    }

    It 'ends the phase of the packages only when they were inspected' {
        $script:Text | Should -Match 'if \(\$ExportSolutionPackage -or \$packagePath\.Count -gt 0\) \{\s*& \$endPhase ''Inspecting the solution packages'''
    }

    It 'says in the log what the phases of the site collections handled' {
        $script:Text | Should -Match "& \`$endPhase 'Enumerating the site collections' \('\{0\} site collection\(s\)' -f @\(\`$inventory\)\.Count\)"
        $script:Text | Should -Match "& \`$endPhase 'Collecting the customization signals' \('\{0\} site collection\(s\)' -f @\(\`$assessment\.SiteDuration\)\.Count\)"
    }

    It 'ends the collection of the signals right after the assessment, before the results are read' {
        $script:Text.IndexOf("& `$endPhase 'Collecting the customization signals'") | Should -BeGreaterThan $script:Text.IndexOf('Invoke-SPSiteAssessment -Inventory')
        $script:Text.IndexOf("& `$endPhase 'Collecting the customization signals'") | Should -BeLessThan $script:Text.IndexOf('$scored = @($assessment.Inventory)')
    }

    It 'gives the export the durations that are known before the reports are written, built just before the call' {
        $export = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Export-SPSInventoryReport' })

        $export | Should -HaveCount 1
        $export[0].Extent.Text | Should -Match '-Timing \$scanTiming @packageExportParams'
        $script:Text | Should -Match '\$scanTiming = \[PSCustomObject\]@\{\s*StartedAt = \$scanStartedAt\.ToString\(''o''\)\s*ScanSeconds = \[System\.Math\]::Round\(\$scanWatch\.Elapsed\.TotalSeconds, 1\)\s*Phase = @\(\$phaseTiming\.ToArray\(\)\)\s*Site = @\(\$assessment\.SiteDuration\)\s*\}'
        $script:Text.IndexOf('$scanTiming = [PSCustomObject]@{') | Should -BeLessThan $script:Text.IndexOf('$output = Export-SPSInventoryReport')
        $script:Text.IndexOf('$scanTiming = [PSCustomObject]@{') | Should -BeGreaterThan $script:Text.IndexOf('Export-SPSSolutionReport')
    }

    It 'ends the phase of the reports right after they are written, and logs the recap last, once, at the information level' {
        $recap = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Add-SPSInventoryEvent' -and $_.Extent.Text -match 'Format-SPSScanTiming' })

        $recap | Should -HaveCount 1
        $recap[0].Extent.Text | Should -Match '-Level Information'
        $recap[0].Extent.Text | Should -Match 'Format-SPSScanTiming -Phase \$Rows -Seconds \$Total \} \$phaseTiming\.ToArray\(\) \$scanSeconds'
        $script:Text.IndexOf("& `$endPhase 'Writing the reports'") | Should -BeGreaterThan $script:Text.IndexOf('$output = Export-SPSInventoryReport')
        $script:Text.IndexOf("& `$endPhase 'Writing the reports'") | Should -BeLessThan $script:Text.IndexOf('Add-SPSInventoryEvent -Message "Inventory complete. CSV:')
        # The recap comes after the last line that names a report, and before the catch of the run, which is the last one of the script.
        $script:Text.IndexOf('Format-SPSScanTiming') | Should -BeGreaterThan $script:Text.LastIndexOf('The farm-solution report only gives')
        $script:Text.IndexOf('Format-SPSScanTiming') | Should -BeLessThan $script:Text.LastIndexOf('catch {')
        $script:Text | Should -Match '\$scanSeconds = \[System\.Math\]::Round\(\$scanWatch\.Elapsed\.TotalSeconds, 1\)'
    }
}
