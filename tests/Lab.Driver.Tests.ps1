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

    It 'supports -WhatIf' {
        $text = Get-Content -LiteralPath $script:Driver -Raw

        $text | Should -Match 'SupportsShouldProcess = \$true'
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

# The steps of the driver, run with a fake module that only records what it is called with, so that
# what the driver passes on (-WhatIf, -Confirm, the scenarios, the scope of the manifest) and the order
# it runs the steps in can be tested without a farm.
Describe 'The steps of Invoke-SPSLabTest.ps1' {
    BeforeAll {
        function New-Harness {
            $root = Join-Path -Path $TestDrive -ChildPath ('harness-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
            $lab = Join-Path -Path $root -ChildPath 'lab'
            $toolkit = Join-Path -Path $root -ChildPath 'toolkit'
            $null = New-Item -Path (Join-Path $toolkit 'config') -ItemType Directory -Force
            $null = New-Item -Path $lab -ItemType Directory -Force
            Copy-Item -LiteralPath $script:Driver -Destination $lab
            Set-Content -Path (Join-Path $toolkit 'config\inventory-settings.example.psd1') -Value '@{}'
            Set-Content -Path (Join-Path $toolkit 'Invoke-SPSSiteInventory.ps1') -Value @'
param ($ConfigPath)
Add-Content -LiteralPath $env:SPSLAB_LOG -WhatIf:$false -Value 'inventory'
if ($env:SPSLAB_FAIL -match 'inventory') { throw 'The inventory failed.' }
'@
            Set-Content -Path (Join-Path $lab 'SPSInventoryLab.psm1') -Value @'
function New-SPSLabSettings {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param ($ExamplePath, $OutputPath, $WebApplicationUrl, $ReportFolder)
    Add-Content -LiteralPath $env:SPSLAB_LOG -WhatIf:$false -Value ('settings whatif={0} whatifbound={1}' -f [bool]$WhatIfPreference, $PSBoundParameters.ContainsKey('WhatIf'))
    if ($PSCmdlet.ShouldProcess($OutputPath, 'write')) {
        $null = New-Item -Path (Split-Path -Path $OutputPath -Parent) -ItemType Directory -Force
        Set-Content -LiteralPath $OutputPath -Value 'settings'
    }
    return $OutputPath
}
function New-SPSLabFixture {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param ($WebApplicationUrl, $ManifestPath, $Prefix, $Owner, $Scenario, $ContentDatabaseName, [switch]$NoContentDatabase)
    if ($PSBoundParameters.ContainsKey('ContentDatabaseName') -or $NoContentDatabase) {
        Add-Content -LiteralPath $env:SPSLAB_LOG -WhatIf:$false -Value ('database name={0} none={1}' -f $ContentDatabaseName, [bool]$NoContentDatabase)
    }
    Add-Content -LiteralPath $env:SPSLAB_LOG -WhatIf:$false -Value ('fixture whatif={0} confirm={1} scenario={2} prefix={3} whatifbound={4}' -f [bool]$WhatIfPreference, $ConfirmPreference, ($Scenario -join ','), $Prefix, $PSBoundParameters.ContainsKey('WhatIf'))
    if ($env:SPSLAB_FAIL -match 'fixture') { throw 'The fixture failed.' }
    if (-not $WhatIfPreference) {
        $null = New-Item -Path (Split-Path -Path $ManifestPath -Parent) -ItemType Directory -Force
        Set-Content -LiteralPath $ManifestPath -Value '{}'
    }
    [PSCustomObject]@{ Scenario = @([PSCustomObject]@{ Name = 'x'; Status = 'Created'; Detail = '' }) }
}
function Test-SPSLabResult {
    param ($ManifestPath, $ReportFolder, $Scenario)
    Add-Content -LiteralPath $env:SPSLAB_LOG -WhatIf:$false -Value ('verify scenario={0}' -f ($Scenario -join ','))
    $status = if ($env:SPSLAB_FAIL -match 'verify') { 'FAIL' } else { 'PASS' }
    @([PSCustomObject]@{ Scenario = 'x'; Url = 'u'; Check = 'c'; Expected = 1; Actual = 1; Kind = 'Must'; Status = $status })
}
function Write-SPSLabReport {
    param ($Result)
    [PSCustomObject]@{ Pass = @($Result | Where-Object { $_.Status -eq 'PASS' }).Count; Fail = @($Result | Where-Object { $_.Status -eq 'FAIL' }).Count; Info = 0; Skip = 0 }
}
function Remove-SPSLabFixture {
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Prefix')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Manifest')] $ManifestPath,
        [Parameter(Mandatory = $true, ParameterSetName = 'Prefix')][Parameter(ParameterSetName = 'Manifest')] $WebApplicationUrl,
        [Parameter(ParameterSetName = 'Prefix')][Parameter(ParameterSetName = 'Manifest')] $Prefix
    )
    Add-Content -LiteralPath $env:SPSLAB_LOG -WhatIf:$false -Value ('remove set={0} whatif={1} confirm={2} url={3} prefix={4} whatifbound={5}' -f $PSCmdlet.ParameterSetName, [bool]$WhatIfPreference, $ConfirmPreference, $WebApplicationUrl, $Prefix, $PSBoundParameters.ContainsKey('WhatIf'))
    if ($env:SPSLAB_FAIL -match 'remove') { throw 'The removal failed.' }
    @([PSCustomObject]@{ Url = 'u'; Status = 'Removed'; Detail = '' })
}
'@
            return [PSCustomObject]@{ Root = $root; Lab = $lab; Toolkit = $toolkit; Log = (Join-Path $root 'calls.log'); Work = (Join-Path $root 'work') }
        }

        function Invoke-Steps {
            param
            (
                [System.Object] $Harness,
                [System.String[]] $Argument,
                [System.String] $Fail = ''
            )

            $env:SPSLAB_LOG = $Harness.Log
            $env:SPSLAB_FAIL = $Fail
            $previous = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $output = & $script:HostPath -NoProfile -NonInteractive -File (Join-Path $Harness.Lab 'Invoke-SPSLabTest.ps1') -WebApplicationUrl 'https://lab' -ToolkitPath $Harness.Toolkit -WorkFolder $Harness.Work @Argument 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previous
                Remove-Item Env:\SPSLAB_LOG, Env:\SPSLAB_FAIL -ErrorAction SilentlyContinue
            }
            $calls = if (Test-Path -LiteralPath $Harness.Log) { @(Get-Content -LiteralPath $Harness.Log) } else { @() }
            return [PSCustomObject]@{ ExitCode = $exitCode; Output = $output; Call = $calls }
        }
    }

    It 'runs provision, inventory and verify in order, and does not remove the lab without -Cleanup' {
        $harness = New-Harness

        $run = Invoke-Steps $harness @('-Force')

        $run.ExitCode | Should -Be 0
        @($run.Call | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('settings', 'fixture', 'inventory', 'verify')
    }

    It 'passes the content database options on to the provisioning, and only when they are given' {
        $harness = New-Harness

        $without = Invoke-Steps $harness @('-Action', 'Provision', '-Force')
        $named = Invoke-Steps (New-Harness) @('-Action', 'Provision', '-Force', '-ContentDatabaseName', 'spslab_Mine')
        $none = Invoke-Steps (New-Harness) @('-Action', 'Provision', '-Force', '-NoContentDatabase')

        @($without.Call | Where-Object { $_ -like 'database *' }) | Should -HaveCount 0
        @($named.Call | Where-Object { $_ -like 'database *' }) | Should -Be @('database name=spslab_Mine none=False')
        @($none.Call | Where-Object { $_ -like 'database *' }) | Should -Be @('database name= none=True')
    }

    It 'rejects a content database name that is not a name' {
        $run = Invoke-Steps (New-Harness) @('-Action', 'Provision', '-Force', '-ContentDatabaseName', 'bad name;drop')

        $run.ExitCode | Should -Not -Be 0
    }

    It 'removes the lab at the end with -Cleanup' {
        $harness = New-Harness

        $run = Invoke-Steps $harness @('-Force', '-Cleanup')

        @($run.Call | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('settings', 'fixture', 'inventory', 'verify', 'remove')
    }

    It 'passes -Confirm:$false on with -Force, and does not without it' {
        $forced = Invoke-Steps (New-Harness) @('-Force', '-Cleanup')
        $asked = Invoke-Steps (New-Harness) @('-Cleanup')

        ($forced.Call | Where-Object { $_ -like 'fixture *' }) | Should -Match 'confirm=None'
        ($forced.Call | Where-Object { $_ -like 'remove *' }) | Should -Match 'confirm=None'
        ($asked.Call | Where-Object { $_ -like 'fixture *' }) | Should -Match 'confirm=High'
        ($asked.Call | Where-Object { $_ -like 'remove *' }) | Should -Match 'confirm=High'
    }

    It 'forwards -WhatIf to every function that can change something, and does not write the settings during a preview' {
        $harness = New-Harness

        $run = Invoke-Steps $harness @('-WhatIf', '-Force', '-Cleanup')

        $run.ExitCode | Should -Be 0
        ($run.Call | Where-Object { $_ -like 'settings *' }) | Should -Match 'whatif=True whatifbound=True'
        ($run.Call | Where-Object { $_ -like 'fixture *' }) | Should -Match 'whatif=True .* whatifbound=True'
        ($run.Call | Where-Object { $_ -like 'remove *' }) | Should -Match 'whatif=True .* whatifbound=True'
        Test-Path -LiteralPath (Join-Path $harness.Work 'inventory-settings.lab.psd1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $harness.Work 'lab-manifest.json') | Should -BeFalse
    }

    It 'does not pass -WhatIf on when there is none' {
        $run = Invoke-Steps (New-Harness) @('-Force', '-Cleanup')

        ($run.Call | Where-Object { $_ -like 'settings *' }) | Should -Match 'whatif=False whatifbound=False'
        ($run.Call | Where-Object { $_ -like 'fixture *' }) | Should -Match 'whatif=False .* whatifbound=False'
        ($run.Call | Where-Object { $_ -like 'remove *' }) | Should -Match 'whatif=False .* whatifbound=False'
    }

    It 'skips the inventory and the verification in a dry run, so that it completes in a fresh work folder, and reaches the removal preview' {
        $run = Invoke-Steps (New-Harness) @('-WhatIf', '-Cleanup')

        $run.ExitCode | Should -Be 0
        @($run.Call | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('settings', 'fixture', 'remove')
    }

    It 'still verifies when Verify is asked for explicitly, with -WhatIf, because it only reads' {
        $run = Invoke-Steps (New-Harness) @('-Action', 'Verify', '-WhatIf')

        @($run.Call | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('verify')
    }

    It 'prints the settings file and the report folder that the inventory uses, before it starts' {
        $harness = New-Harness

        $run = Invoke-Steps $harness @('-Force')

        $settings = Join-Path -Path $harness.Work -ChildPath 'inventory-settings.lab.psd1'
        $reports = Join-Path -Path $harness.Work -ChildPath 'Reports'
        $run.Output | Should -Match ([regex]::Escape(('Settings file: {0}' -f $settings)))
        $run.Output | Should -Match ([regex]::Escape(('Report folder: {0}' -f $reports)))
        $run.Output.IndexOf('Settings file: ') | Should -BeGreaterThan $run.Output.IndexOf('== Inventory ==')
    }

    It 'does not print the inventory settings when the inventory does not run' {
        $run = Invoke-Steps (New-Harness) @('-Action', 'Verify')

        $run.Output | Should -Not -Match 'Settings file: '
    }

    It 'passes the scenarios to the provisioning and to the verification' {
        $run = Invoke-Steps (New-Harness) @('-Force', '-Scenario', 'subsites,infopath')

        ($run.Call | Where-Object { $_ -like 'fixture *' }) | Should -Match 'scenario=subsites,infopath'
        ($run.Call | Where-Object { $_ -like 'verify *' }) | Should -Match 'scenario=subsites,infopath'
    }

    It 'verifies every scenario when none is asked for' {
        $run = Invoke-Steps (New-Harness) @('-Action', 'Verify')

        ($run.Call | Where-Object { $_ -like 'verify *' }) | Should -Be 'verify scenario='
    }

    It 'removes the lab even when the inventory fails, and keeps the failure of the inventory' {
        $run = Invoke-Steps (New-Harness) @('-Force', '-Cleanup') -Fail 'inventory'

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -Match 'The inventory failed'
        @($run.Call | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('settings', 'fixture', 'inventory', 'remove')
    }

    It 'removes the lab even when the provisioning fails half way' {
        $run = Invoke-Steps (New-Harness) @('-Force', '-Cleanup') -Fail 'fixture'

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -Match 'The fixture failed'
        @($run.Call | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('settings', 'fixture', 'remove')
    }

    It 'does not let a failed removal hide the failure that stopped the run, and says it as a warning' {
        $run = Invoke-Steps (New-Harness) @('-Force', '-Cleanup') -Fail 'inventory,remove'

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -Match 'The inventory failed'
        $run.Output | Should -Match 'The lab could not be removed: The removal failed'
    }

    It 'fails when the removal fails and nothing else did' {
        $run = Invoke-Steps (New-Harness) @('-Action', 'Remove', '-Force') -Fail 'remove'

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -Match 'The removal failed'
    }

    It 'removes the lab and exits with 1 when a check fails, with -Cleanup' {
        $run = Invoke-Steps (New-Harness) @('-Force', '-Cleanup') -Fail 'verify'

        $run.ExitCode | Should -Be 1
        @($run.Call | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('settings', 'fixture', 'inventory', 'verify', 'remove')
    }

    It 'uses the manifest of the work folder to remove, and says which web application it must be for' {
        $harness = New-Harness
        $null = New-Item -Path $harness.Work -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $harness.Work 'lab-manifest.json') -Value '{}'

        $run = Invoke-Steps $harness @('-Action', 'Remove', '-Force')

        ($run.Call | Where-Object { $_ -like 'remove *' }) | Should -Be 'remove set=Manifest whatif=False confirm=None url=https://lab prefix= whatifbound=False'
    }

    It 'gives the prefix to the removal with a manifest only when it was given' {
        $harness = New-Harness
        $null = New-Item -Path $harness.Work -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $harness.Work 'lab-manifest.json') -Value '{}'

        $run = Invoke-Steps $harness @('-Action', 'Remove', '-Force', '-Prefix', 'lab42')

        ($run.Call | Where-Object { $_ -like 'remove *' }) | Should -Be 'remove set=Manifest whatif=False confirm=None url=https://lab prefix=lab42 whatifbound=False'
    }

    It 'forwards -WhatIf and -Confirm to the removal by manifest' {
        $previewHarness = New-Harness
        $askedHarness = New-Harness
        foreach ($harness in @($previewHarness, $askedHarness)) {
            $null = New-Item -Path $harness.Work -ItemType Directory -Force
            Set-Content -LiteralPath (Join-Path $harness.Work 'lab-manifest.json') -Value '{}'
        }

        $preview = Invoke-Steps $previewHarness @('-Action', 'Remove', '-WhatIf')
        $asked = Invoke-Steps $askedHarness @('-Action', 'Remove')

        ($preview.Call | Where-Object { $_ -like 'remove *' }) | Should -Be 'remove set=Manifest whatif=True confirm=High url=https://lab prefix= whatifbound=True'
        ($asked.Call | Where-Object { $_ -like 'remove *' }) | Should -Be 'remove set=Manifest whatif=False confirm=High url=https://lab prefix= whatifbound=False'
    }

    It 'finds the lab by prefix when there is no manifest' {
        $run = Invoke-Steps (New-Harness) @('-Action', 'Remove', '-Force')

        ($run.Call | Where-Object { $_ -like 'remove *' }) | Should -Be 'remove set=Prefix whatif=False confirm=None url=https://lab prefix=spslab whatifbound=False'
    }
}
