# The orchestrator reads SharePoint, so it cannot run here: these tests read its code, and check that the packages of
# -SolutionPackagePath are inspected once, before the scan, without a failure being able to stop the site report, that what is
# inspected reaches the export, and that a scan without the parameter ends by telling how to inspect the packages.
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

    It 'documents the parameter and gives an example in its help' {
        $script:Text | Should -Match '(?m)^\s+\.PARAMETER SolutionPackagePath\s*$'
        $script:Text | Should -Match '(?m)^\s+\.\\Invoke-SPSSiteInventory\.ps1 -SolutionPackagePath D:\\Packages\s*$'
        $script:Text | Should -Match 'SaveAs\(\(Join-Path ''D:\\Packages'' \$_\.Name\)\)'
    }

    It 'inspects the packages once, with the paths, the subfolders, the farm-solution map and the Microsoft prefixes of the settings' {
        $call = @(Get-CommandText -Name 'Get-SPSSolutionPackageInfo')

        $call | Should -HaveCount 1
        $call[0].Extent.Text | Should -Be 'Get-SPSSolutionPackageInfo @packageParams'
        $script:Text | Should -Match '\$packageParams = @\{ Path = \$packagePath; Recurse = \$true; FarmSolutionMap = @\(\$solutionMap\) \}'
        $script:Text | Should -Match "if \(\`$settings\.ContainsKey\('KnownMicrosoftSolutionPrefix'\)\) \{\s+\`$packageParams\['KnownMicrosoftPrefix'\] = \`$settings\.KnownMicrosoftSolutionPrefix"
    }

    It 'ignores an empty path, and inspects only when a path was given' {
        $call = @(Get-CommandText -Name 'Get-SPSSolutionPackageInfo')

        $script:Text | Should -Match '\$packagePath = @\(\$SolutionPackagePath \| Where-Object \{ -not \[string\]::IsNullOrWhiteSpace\(\$_\) \}\)'
        $clause = Get-EnclosingClause -Node $call[0]
        $clause.Index | Should -Be 0
        $clause.Condition | Should -Be '$packagePath.Count -gt 0'
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

    It 'ends the scan by telling how to save the packages and how to inspect them, when the farm has solutions and no package path was given' {
        $event = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Add-SPSInventoryEvent' -and $_.Extent.Text -match 'SaveAs' })

        $event | Should -HaveCount 1
        $event[0].Extent.Text | Should -Match '-Level Information'
        $event[0].Extent.Text | Should -Match 'not the reports folder'
        $event[0].Extent.Text | Should -Match '-SolutionPackagePath ''''D:\\Packages'''''
        $event[0].Extent.Text | Should -Match 'Get-SPSSolutionPackageInfo'
        $event[0].Extent.Text | Should -Match 'Inspecting WSP packages offline'
        # It is the elseif of the report line, so it never comes with it, and a path that was given gets no advice to give one, even if the inspection returned nothing.
        $clause = Get-EnclosingClause -Node $event[0]
        $clause.Index | Should -Be 1
        $clause.If.Clauses[0].Item1.Extent.Text | Should -Be '$solutionPackages.Count -gt 0'
        $clause.Condition | Should -Be '$packagePath.Count -eq 0 -and @($solutionMap).Count -gt 0'
        $event[0].Extent.StartOffset | Should -BeGreaterThan $script:Text.IndexOf('Profile property mappings report.')
        $event[0].Extent.StartOffset | Should -BeGreaterThan $script:Text.IndexOf('Solution package report.')
    }
}
