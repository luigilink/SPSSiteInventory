BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:Driver = Join-Path $repoRoot 'tools/lab/Invoke-SPSLabTest.ps1'
    $script:Toolkit = Join-Path $repoRoot 'src'
    $script:HostPath = (Get-Process -Id $PID).Path

    function Write-Lab {
        param
        (
            [System.String] $Folder,
            [System.Collections.IDictionary] $Subsites
        )

        $reports = Join-Path -Path $Folder -ChildPath 'Reports'
        $null = New-Item -Path $reports -ItemType Directory -Force
        $manifest = [PSCustomObject]@{
            ManifestVersion = 1; WebApplicationUrl = 'https://lab'; Prefix = 'spslab'; Owner = 'CONTOSO\jc'
            Scenario        = @([PSCustomObject]@{ Name = 'subsites'; Url = 'https://lab/sites/spslab-subsites'; Status = 'Created'; Detail = '' })
        }
        ConvertTo-Json -InputObject $manifest -Depth 5 | Set-Content -Path (Join-Path $Folder 'lab-manifest.json') -Encoding UTF8
        $record = [ordered]@{ Url = 'https://lab/sites/spslab-subsites'; AssessmentStatus = 'Complete'; AssessmentWarnings = '' }
        foreach ($key in $Subsites.Keys) { $record[$key] = $Subsites[$key] }
        ConvertTo-Json -InputObject @([PSCustomObject]$record) -Depth 5 | Set-Content -Path (Join-Path $reports 'SPSSiteInventory-LAB-sites-1.json') -Encoding UTF8
        ConvertTo-Json -InputObject @([PSCustomObject]@{ AlertType = 'Subsites'; Url = 'https://lab/sites/spslab-subsites' }) -Depth 5 | Set-Content -Path (Join-Path $reports 'SPSSiteInventory-LAB-alerts-1.json') -Encoding UTF8
    }

    # A child process of the same PowerShell edition, to test the real exit code of the script.
    function Invoke-Driver {
        param ([System.String[]] $Argument)

        $output = & $script:HostPath -NoProfile -NonInteractive -File $script:Driver @Argument | Out-String
        return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    $script:Good = @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3); a/b (level 2)' }
}

Describe 'Invoke-SPSLabTest.ps1' {
    It 'parses, and takes the web application on purpose, with no default' {
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Driver, [ref]$null, [ref]$errors)

        @($errors).Count | Should -Be 0
        $parameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'WebApplicationUrl' }
        $parameter.DefaultValue | Should -BeNullOrEmpty
        $parameter.Attributes.NamedArguments.ArgumentName | Should -Contain 'Mandatory'
    }

    It 'supports -WhatIf, and does not run the inventory with it' {
        $text = Get-Content -LiteralPath $script:Driver -Raw

        $text | Should -Match 'SupportsShouldProcess = \$true'
        $text | Should -Match 'if \(\$runInventory -and -not \$WhatIfPreference\)'
    }

    It 'only asks to remove the lab at the end of All when -Cleanup is given' {
        $text = Get-Content -LiteralPath $script:Driver -Raw

        $text | Should -Match "\`$runRemove = \(\`$Action -eq 'Remove'\) -or \(\`$Action -eq 'All' -and \`$Cleanup\)"
    }

    It 'verifies the reports of a run and exits with 0 when every check passes' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'good'
        Write-Lab -Folder $folder -Subsites $script:Good

        $run = Invoke-Driver -Argument @('-Action', 'Verify', '-WebApplicationUrl', 'https://lab', '-ToolkitPath', $script:Toolkit, '-WorkFolder', $folder)

        $run.ExitCode | Should -Be 0
        $run.Output | Should -Match '== Verify =='
        $run.Output | Should -Match '== subsites \(https://lab/sites/spslab-subsites\) =='
        $run.Output | Should -Match '\[PASS\]\s+SubsiteCount eq 5'
        $run.Output | Should -Match '\[PASS\]\s+Alert Subsites'
        $run.Output | Should -Match 'Summary: \d+ passed, 0 failed'
    }

    It 'exits with 1 and shows the actual value when a check fails' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'bad'
        Write-Lab -Folder $folder -Subsites @{ SubsiteCount = 2; MaxSubsiteDepth = 1; SubWebCount = 3; SubsiteExamples = 'a (level 1)' }

        $run = Invoke-Driver -Argument @('-Action', 'Verify', '-WebApplicationUrl', 'https://lab', '-ToolkitPath', $script:Toolkit, '-WorkFolder', $folder)

        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[FAIL\]\s+SubsiteCount eq 5 - actual: 2'
        $run.Output | Should -Match 'Summary: \d+ passed, [1-9]\d* failed'
    }

    It 'stops with an error, and a non-zero exit code, when there is nothing to verify' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'empty'
        $null = New-Item -Path $folder -ItemType Directory -Force

        $run = Invoke-Driver -Argument @('-Action', 'Verify', '-WebApplicationUrl', 'https://lab', '-ToolkitPath', $script:Toolkit, '-WorkFolder', $folder)

        $run.ExitCode | Should -Not -Be 0
    }

    It 'refuses a toolkit folder that is not one, before doing anything' {
        $run = Invoke-Driver -Argument @('-Action', 'Verify', '-WebApplicationUrl', 'https://lab', '-ToolkitPath', $TestDrive, '-WorkFolder', (Join-Path $TestDrive 'x'))

        $run.ExitCode | Should -Not -Be 0
    }

    It 'refuses a prefix that is not lowercase letters and digits' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'prefix'
        Write-Lab -Folder $folder -Subsites $script:Good

        $run = Invoke-Driver -Argument @('-Action', 'Verify', '-WebApplicationUrl', 'https://lab', '-ToolkitPath', $script:Toolkit, '-WorkFolder', $folder, '-Prefix', 'Bad Prefix')

        $run.ExitCode | Should -Not -Be 0
    }
}
