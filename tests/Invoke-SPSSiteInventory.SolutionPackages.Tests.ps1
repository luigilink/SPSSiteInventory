# The orchestrator reads SharePoint, so it cannot run here: these tests read its code, and check that the packages of
# -SolutionPackagePath and the ones that -ExportSolutionPackage saves from the farm are inspected once, before the scan, without a
# failure being able to stop the site report, that the packages saved from the farm are in a temporary folder that is removed whatever
# happens, never in the reports folder, that what is inspected reaches the export, and that a scan without either parameter ends by
# telling how to inspect the packages.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:Path = Join-Path $repoRoot 'src/Invoke-SPSSiteInventory.ps1'
    $script:Text = Get-Content -LiteralPath $script:Path -Raw
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$null)
    $script:Commands = @($script:Ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    $script:Tries = @($script:Ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.TryStatementAst] }, $true))

    function Get-CommandText {
        param ([string]$Name)
        @($script:Commands | Where-Object { $_.GetCommandName() -eq $Name })
    }

    function Get-EnclosingTry {
        param ($Node)
        $parent = $Node.Parent
        while ($null -ne $parent -and $parent -isnot [System.Management.Automation.Language.TryStatementAst]) {
            $parent = $parent.Parent
        }
        return $parent
    }

    # The if statement that holds the node, the position of its clause (0 for the if, 1 and more for the elseif) and the condition of that clause.
    function Get-EnclosingClause {
        param ($Node)
        $parent = $Node.Parent
        while ($null -ne $parent) {
            if ($parent -is [System.Management.Automation.Language.IfStatementAst]) {
                for ($index = 0; $index -lt $parent.Clauses.Count; $index++) {
                    $body = $parent.Clauses[$index].Item2
                    if ($body.Extent.StartOffset -le $Node.Extent.StartOffset -and $body.Extent.EndOffset -ge $Node.Extent.EndOffset) {
                        return [PSCustomObject]@{ If = $parent; Index = $index; Condition = $parent.Clauses[$index].Item1.Extent.Text }
                    }
                }
            }
            $parent = $parent.Parent
        }
        return $null
    }
}

Describe 'Invoke-SPSSiteInventory.ps1 and the solution packages' {
    It 'is valid PowerShell' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It 'has an optional SolutionPackagePath parameter that takes a list of paths, and keeps ConfigPath as it was' {
        $parameter = @($script:Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'SolutionPackagePath' })
        $configPath = @($script:Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ConfigPath' })

        $parameter | Should -HaveCount 1
        $parameter[0].StaticType.FullName | Should -Be 'System.String[]'
        $parameter[0].Attributes[0].TypeName.Name | Should -Be 'Parameter'
        @($parameter[0].Attributes[0].NamedArguments | Where-Object { $_.ArgumentName -eq 'Mandatory' }) | Should -HaveCount 0
        $parameter[0].DefaultValue | Should -BeNullOrEmpty
        $configPath | Should -HaveCount 1
        $configPath[0].StaticType.FullName | Should -Be 'System.String'
        $configPath[0].DefaultValue.Extent.Text | Should -Match 'Join-Path -Path \$PSScriptRoot -ChildPath ''config\\inventory-settings\.psd1'''
    }

    It 'has an optional ExportSolutionPackage switch with no default, and keeps the other parameters' {
        $parameter = @($script:Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ExportSolutionPackage' })

        $parameter | Should -HaveCount 1
        $parameter[0].StaticType.FullName | Should -Be 'System.Management.Automation.SwitchParameter'
        $parameter[0].Attributes[0].TypeName.Name | Should -Be 'Parameter'
        @($parameter[0].Attributes[0].NamedArguments | Where-Object { $_.ArgumentName -eq 'Mandatory' }) | Should -HaveCount 0
        $parameter[0].DefaultValue | Should -BeNullOrEmpty
        @($script:Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) | Should -Be @('ConfigPath', 'SolutionPackagePath', 'ExportSolutionPackage')
    }

    It 'documents the parameter and gives an example in its help' {
        $script:Text | Should -Match '(?m)^\s+\.PARAMETER SolutionPackagePath\s*$'
        $script:Text | Should -Match '(?m)^\s+\.\\Invoke-SPSSiteInventory\.ps1 -SolutionPackagePath D:\\Packages\s*$'
        $script:Text | Should -Match 'SaveAs\(\(Join-Path ''D:\\Packages'' \$_\.Name\)\)'
    }

    It 'documents the switch and gives an example in its help, and says that nothing goes in the reports folder and that the folder is removed' {
        $script:Text | Should -Match '(?m)^\s+\.PARAMETER ExportSolutionPackage\s*$'
        $script:Text | Should -Match '(?m)^\s+\.\\Invoke-SPSSiteInventory\.ps1 -ExportSolutionPackage\s*$'
        $script:Text | Should -Match 'in a temporary folder of the\s+account that runs the scan'
        $script:Text | Should -Match 'removes the folder as soon as they are read'
        $script:Text | Should -Match 'none goes in the reports folder'
        $script:Text | Should -Match 'with -ExportSolutionPackage or -SolutionPackagePath, inspects the WSP packages'
    }

    It 'inspects the packages once, with the paths, the subfolders, the farm-solution map and the Microsoft prefixes of the settings' {
        $call = @(Get-CommandText -Name 'Get-SPSSolutionPackageInfo')

        $call | Should -HaveCount 1
        $call[0].Extent.Text | Should -Be 'Get-SPSSolutionPackageInfo @packageParams'
        $script:Text | Should -Match '\$packageParams = @\{ Path = \$inspectPath; Recurse = \$true; FarmSolutionMap = @\(\$solutionMap\) \}'
        $script:Text | Should -Match "if \(\`$settings\.ContainsKey\('KnownMicrosoftSolutionPrefix'\)\) \{\s+\`$packageParams\['KnownMicrosoftPrefix'\] = \`$settings\.KnownMicrosoftSolutionPrefix"
    }

    It 'ignores an empty path, and inspects only when there is something to inspect' {
        $call = @(Get-CommandText -Name 'Get-SPSSolutionPackageInfo')

        $script:Text | Should -Match '\$packagePath = @\(\$SolutionPackagePath \| Where-Object \{ -not \[string\]::IsNullOrWhiteSpace\(\$_\) \}\)'
        $script:Text | Should -Match '\$inspectPath = @\(\$packagePath\)'
        $clause = Get-EnclosingClause -Node $call[0]
        $clause.Index | Should -Be 0
        $clause.Condition | Should -Be '$inspectPath.Count -gt 0'
    }

    It 'saves the packages of the farm only when asked, once, in the module, before it inspects them' {
        $call = @(Get-CommandText -Name 'Save-SPSFarmSolutionPackage')

        $call | Should -HaveCount 1
        $call[0].Extent.Text | Should -Be 'Save-SPSFarmSolutionPackage -Path $Path'
        $script:Text | Should -Match '\$packageExport = & \$commonModule \{\s+param \(\$Path\)\s+Save-SPSFarmSolutionPackage -Path \$Path\s+\} \$exportFolder'
        $clause = Get-EnclosingClause -Node $call[0]
        $clause.Index | Should -Be 0
        $clause.Condition | Should -Be '$ExportSolutionPackage'
        $call[0].Extent.StartOffset | Should -BeGreaterThan $script:Text.IndexOf('Get-SPSFarmSolutionMap @solutionMapParams')
        $call[0].Extent.StartOffset | Should -BeLessThan $script:Text.IndexOf('Get-SPSSolutionPackageInfo @packageParams')
        $call[0].Extent.StartOffset | Should -BeLessThan $script:Text.IndexOf('Get-SPSSiteInventory -WebApplicationUrl')
    }

    It 'names the folder of the packages of the farm in the temporary folder, with a name that is new for each run, and never in the reports folder' {
        $script:Text | Should -Match '\$exportFolder = \$null\s+\$packageFolderLeft = \$null\s+if \(\$ExportSolutionPackage\) \{\s+\$exportFolder = Join-Path -Path \(\[System\.IO\.Path\]::GetTempPath\(\)\) -ChildPath \(''SPSSiteInventory-packages-'' \+ \[System\.Guid\]::NewGuid\(\)\.ToString\(''N''\)\)'
        @($script:Text -split "`n" | Where-Object { $_ -match '\$exportFolder' -and $_ -match 'outputFolder|OutputFolder' }) | Should -HaveCount 0
    }

    It 'does not let a failure of the save stop the site report: the call is in a try that only logs a warning' {
        $call = @(Get-CommandText -Name 'Save-SPSFarmSolutionPackage')
        $try = Get-EnclosingTry -Node $call[0]

        $try | Should -Not -BeNullOrEmpty
        $try.CatchClauses[0].Body.Extent.Text | Should -Match '-Level Warning'
        $try.CatchClauses[0].Body.Extent.Text | Should -Match 'The packages of the farm solutions could not be saved'
        $try.CatchClauses[0].Body.Extent.Text | Should -Not -Match 'throw'
    }

    It 'logs a warning, with the reason, for each package that could not be saved, and how many were saved, or that the farm has no solution' {
        $script:Text | Should -Match 'foreach \(\$exportFailure in @\(\$packageExport\.Failure\)\)'
        $script:Text | Should -Match "The package of the farm solution '\{0\}' could not be saved: \{1\}"" -f \`$exportFailure\.Name, \`$exportFailure\.Reason\) -Level Warning"
        $script:Text | Should -Match "if \(\`$packageExport\.Requested -eq 0\) \{\s+Add-SPSInventoryEvent -Message 'The farm has no solution, so there is no package to save\.' -Level Information"
        $script:Text | Should -Match "\{0\} of \{1\} farm solution package\(s\) saved\.' -f \`$packageExport\.Saved, \`$packageExport\.Requested\) -Level Information"
    }

    It 'inspects the folder of the packages of the farm only when a package was saved in it, and shows it as the packages saved from the farm, not by its path' {
        $script:Text | Should -Match "if \(\`$packageExport\.Saved -gt 0\) \{\s+\`$inspectPath \+= \`$exportFolder\s+\`$inspectLabel \+= 'the packages saved from the farm'"
        $script:Text | Should -Match "Inspecting the solution packages in \{0\}\.' -f \(\`$inspectLabel -join ', '\)\) -Level Information"
        $script:Text | Should -Match '\$inspectLabel = @\(\$packagePath \| ForEach-Object \{ "''\$_''" \}\)'
    }

    It 'removes the temporary folder in a finally that covers the save and the inspection, only when the scan made one' {
        $remove = @(Get-CommandText -Name 'Remove-SPSPackageWorkFolder')
        $try = @($script:Tries | Where-Object { $null -ne $_.Finally -and $_.Finally.Extent.Text -match 'Remove-SPSPackageWorkFolder' })
        $save = @(Get-CommandText -Name 'Save-SPSFarmSolutionPackage')[0]
        $inspect = @(Get-CommandText -Name 'Get-SPSSolutionPackageInfo')[0]

        $remove | Should -HaveCount 1
        $remove[0].Extent.Text | Should -Be 'Remove-SPSPackageWorkFolder -Path $Path'
        $try | Should -HaveCount 1
        $try[0].Finally.Extent.Text | Should -Match 'if \(\$null -ne \$exportFolder\) \{\s+\$removed = & \$commonModule \{\s+param \(\$Path\)\s+Remove-SPSPackageWorkFolder -Path \$Path\s+\} \$exportFolder'
        foreach ($covered in @($save, $inspect)) {
            $try[0].Body.Extent.StartOffset | Should -BeLessThan $covered.Extent.StartOffset
            $try[0].Body.Extent.EndOffset | Should -BeGreaterThan $covered.Extent.EndOffset
        }
        $try[0].Extent.EndOffset | Should -BeLessThan $script:Text.IndexOf('Enumerating site collections.')
    }

    It 'takes the temporary folders out of the records of the packages, in the module, after the inspection and before the log and the reports, whatever the packages are' {
        $call = @(Get-CommandText -Name 'Hide-SPSTemporaryPackagePath')

        $call | Should -HaveCount 1
        $call[0].Extent.Text | Should -Be 'Hide-SPSTemporaryPackagePath -Record $Record -Folder $Folder'
        $script:Text | Should -Match '& \$commonModule \{\s+param \(\$Record, \$Folder\)\s+Hide-SPSTemporaryPackagePath -Record \$Record -Folder \$Folder\s+\} \$solutionPackages \$exportFolder'
        $call[0].Extent.StartOffset | Should -BeGreaterThan $script:Text.IndexOf('Get-SPSSolutionPackageInfo @packageParams')
        $call[0].Extent.StartOffset | Should -BeLessThan $script:Text.IndexOf("Solution package '{0}' is {1}: {2}")
        $call[0].Extent.StartOffset | Should -BeLessThan $script:Text.IndexOf('$output = Export-SPSInventoryReport')
        # It is not in a condition on the folder: a package that the user gave can fail on a work folder too.
        (Get-EnclosingClause -Node $call[0]).Condition | Should -Be '$inspectPath.Count -gt 0'
    }

    It 'logs the path of the temporary folder when it starts to save, so that a run that is stopped leaves a pointer to it' {
        $event = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Add-SPSInventoryEvent' -and $_.Extent.Text -match 'Saving the packages of the farm solutions' })

        $event | Should -HaveCount 1
        $event[0].Extent.Text | Should -Match "in the temporary folder '\{0\}', to inspect them\."
        $event[0].Extent.Text | Should -Match 'if this run is stopped before that, remove it by hand'
        $event[0].Extent.Text | Should -Match '-f \$exportFolder\) -Level Information'
    }

    It 'reminds, at the end of the run, that the temporary folder is still there when it could not be removed, whatever the end of the run is' {
        $removeCall = @(Get-CommandText -Name 'Remove-SPSPackageWorkFolder')[0]
        $reminder = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Add-SPSInventoryEvent' -and $_.Extent.Text -match 'still holds the packages of the farm solutions' })
        $outer = @($script:Tries | Where-Object { $null -ne $_.Finally -and $_.Finally.Extent.Text -match 'Stop-Transcript' })

        $script:Text | Should -Match 'if \(-not \$removed\) \{\s+\$packageFolderLeft = \$exportFolder\s+\}'
        $script:Text | Should -Match '\$exportFolder = \$null\s+\$packageFolderLeft = \$null'
        $reminder | Should -HaveCount 1
        $reminder[0].Extent.Text | Should -Match "The temporary folder '\{0\}' still holds the packages of the farm solutions, because it could not be removed\. Remove it by hand\."
        $reminder[0].Extent.Text | Should -Match '-f \$packageFolderLeft\) -Level Warning'
        $outer | Should -HaveCount 1
        $outer[0].Finally.Extent.StartOffset | Should -BeLessThan $reminder[0].Extent.StartOffset
        $outer[0].Finally.Extent.EndOffset | Should -BeGreaterThan $reminder[0].Extent.EndOffset
        (Get-EnclosingClause -Node $reminder[0]).Condition | Should -Be '$null -ne $packageFolderLeft'
        $reminder[0].Extent.StartOffset | Should -BeGreaterThan $removeCall.Extent.StartOffset
        $reminder[0].Extent.StartOffset | Should -BeLessThan $script:Text.LastIndexOf('Stop-Transcript')
    }

    It 'says, in its help, what the code guarantees: the folder is removed after an error or Ctrl+C, and stays when the process is killed, with where to find it' {
        $script:Text | Should -Match 'removes the folder as soon as they are read, also after an\s+error or Ctrl\+C'
        $script:Text | Should -Match 'If the process is killed, the window is closed or\s+security software keeps a file open, the folder stays'
        $script:Text | Should -Match 'the log gives its path when the scan\s+saves the packages, a warning says at the end when the folder could not be removed'
        $script:Text | Should -Match 'telling how to inspect the packages, when the farm has solutions\.'
        $script:Text | Should -Not -Match '(?i)no package is\s+left|nothing is\s+left|none is\s+left|whatever happens'
    }

    It 'reads the packages after the farm-solution map and before the scan, so that a wrong path shows at once' {
        $inspect = $script:Text.IndexOf('Get-SPSSolutionPackageInfo @packageParams')

        $inspect | Should -BeGreaterThan $script:Text.IndexOf('Get-SPSFarmSolutionMap @solutionMapParams')
        $inspect | Should -BeLessThan $script:Text.IndexOf('Get-SPSSiteInventory -WebApplicationUrl')
        $inspect | Should -BeLessThan $script:Text.IndexOf('Invoke-SPSiteAssessment')
    }

    It 'does not let a failure of the inspection stop the site report: the call is in a try that only logs a warning, after an empty result' {
        $call = @(Get-CommandText -Name 'Get-SPSSolutionPackageInfo')
        $try = Get-EnclosingTry -Node $call[0]

        $try | Should -Not -BeNullOrEmpty
        $try.CatchClauses[0].Body.Extent.Text | Should -Match '-Level Warning'
        $try.CatchClauses[0].Body.Extent.Text | Should -Match 'The solution package inspection failed'
        $try.CatchClauses[0].Body.Extent.Text | Should -Not -Match 'throw'
        $script:Text.IndexOf('$solutionPackages = @()') | Should -BeLessThan $script:Text.IndexOf('Get-SPSSolutionPackageInfo @packageParams')
    }

    It 'logs a warning, with the reason, for each package that was not read in full, and how many were inspected' {
        $script:Text | Should -Match 'foreach \(\$solutionPackage in \$solutionPackages\) \{\s+if \(\$solutionPackage\.Status -ne ''Inspected''\)'
        $script:Text | Should -Match "Solution package '\{0\}' is \{1\}: \{2\}"" -f \`$solutionPackage\.PackageName, \`$solutionPackage\.Status, \`$solutionPackage\.Detail\) -Level Warning"
        $script:Text | Should -Match "\{0\} solution package\(s\) inspected: \{1\} custom, \{2\} with full-trust code, \{3\} not read in full\."
    }

    It 'gives the packages to the export only when there are some, through a splat that ends the call' {
        $export = @(Get-CommandText -Name 'Export-SPSInventoryReport')

        $export | Should -HaveCount 1
        $export[0].Extent.Text | Should -Match '-TargetMode \$targetMode @packageExportParams$'
        $script:Text | Should -Match "\`$packageExportParams = @\{\}\s+if \(\`$solutionPackages\.Count -gt 0\) \{\s+\`$packageExportParams\['SolutionPackages'\] = @\(\`$solutionPackages\)"
        $script:Text.IndexOf('$packageExportParams = @{}') | Should -BeLessThan $script:Text.IndexOf('$output = Export-SPSInventoryReport')
    }

    It 'logs the paths of the package report when packages were inspected' {
        $event = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Add-SPSInventoryEvent' -and $_.Extent.Text -match 'Solution package report\.' })

        $event | Should -HaveCount 1
        $event[0].Extent.Text | Should -Match 'CSV: \$\(\$output\.SolutionPackagesCsvPath\) \| Assemblies: \$\(\$output\.SolutionAssembliesCsvPath\) \| JSON: \$\(\$output\.SolutionPackagesJsonPath\)'
        $event[0].Extent.Text | Should -Match '-Level Information'
        $clause = Get-EnclosingClause -Node $event[0]
        $clause.Index | Should -Be 0
        $clause.Condition | Should -Be '$solutionPackages.Count -gt 0'
    }

    It 'ends the scan by telling how to inspect the packages, with -ExportSolutionPackage first, when the farm has solutions and neither parameter was given' {
        $event = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Add-SPSInventoryEvent' -and $_.Extent.Text -match 'The farm-solution report only gives' })

        $event | Should -HaveCount 1
        $event[0].Extent.Text | Should -Match '-Level Information'
        $event[0].Extent.Text | Should -Match 'run this script again with -ExportSolutionPackage: it saves the packages of the farm solutions in a temporary folder, reads them and removes the folder as soon as they are read, so that none goes in the reports folder'
        $event[0].Extent.Text | Should -Match 'give their folder to -SolutionPackagePath'
        $event[0].Extent.Text | Should -Match 'Get-SPSSolutionPackageInfo'
        $event[0].Extent.Text | Should -Match 'Inspecting WSP packages offline'
        $event[0].Extent.Text.IndexOf('-ExportSolutionPackage') | Should -BeLessThan $event[0].Extent.Text.IndexOf('-SolutionPackagePath')
        # It is the elseif of the report line, so it never comes with it, and a run that was given a path, or the switch, gets no advice to give one, even if the inspection returned nothing.
        $clause = Get-EnclosingClause -Node $event[0]
        $clause.Index | Should -Be 1
        $clause.If.Clauses[0].Item1.Extent.Text | Should -Be '$solutionPackages.Count -gt 0'
        $clause.Condition | Should -Be '-not $ExportSolutionPackage -and $packagePath.Count -eq 0 -and @($solutionMap).Count -gt 0'
        $event[0].Extent.StartOffset | Should -BeGreaterThan $script:Text.IndexOf('Profile property mappings report.')
        $event[0].Extent.StartOffset | Should -BeGreaterThan $script:Text.IndexOf('Solution package report.')
    }
}
