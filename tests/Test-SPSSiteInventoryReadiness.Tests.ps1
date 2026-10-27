BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ScriptPath = Join-Path $repoRoot 'src/Test-SPSSiteInventoryReadiness.ps1'
    $script:HostPath = (Get-Process -Id $PID).Path

    $script:ReportsFolder = Join-Path -Path $TestDrive -ChildPath 'Reports'
    New-Item -Path $script:ReportsFolder -ItemType Directory -Force | Out-Null
    $script:ValidSettings = Join-Path -Path $TestDrive -ChildPath 'inventory-settings.psd1'
    Set-Content -Path $script:ValidSettings -Encoding UTF8 -Value @"
@{
    EnvName      = 'LAB'
    OutputFolder = '$($script:ReportsFolder)'
    Scoring      = @{
        Weights         = @{ WorkflowCount = 1.0 }
        Thresholds      = @{ Moderate = 2; Complex = 5 }
        BlockingSignals = @()
    }
}
"@
    $script:MissingSettings = Join-Path -Path $TestDrive -ChildPath 'missing.psd1'

    # A child process of the same PowerShell edition, to test the real exit code of the script.
    function Invoke-ReadinessScript {
        param ([System.String[]] $Argument)

        $output = & $script:HostPath -NoProfile -NonInteractive -File $script:ScriptPath @Argument | Out-String
        return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

Describe 'Test-SPSSiteInventoryReadiness.ps1' {
    It 'exits with 1 and shows the error when the settings file is missing' {
        $run = Invoke-ReadinessScript -Argument @('-ConfigPath', $script:MissingSettings, '-SkipSharePoint')

        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[ERR \]\s+Settings file - Not found'
        $run.Output | Should -Match 'Summary : \d+ OK, \d+ warning\(s\), [1-9]\d* error\(s\)'
        $run.Output | Should -Match 'Not ready'
    }

    It 'prints the readiness report and exits with 1 only when it shows an error' {
        $run = Invoke-ReadinessScript -Argument @('-ConfigPath', $script:ValidSettings, '-SkipSharePoint')

        $run.Output | Should -Match 'SPSSiteInventory - Readiness Check'
        $run.Output | Should -Match '== Settings =='
        $run.Output | Should -Match '\[ OK \]\s+Settings content'
        $run.Output | Should -Match '\[SKIP\]\s+SharePoint checks - Skipped on request \(-SkipSharePoint\)'
        $hasError = $run.Output -match '\[ERR \]'
        $run.ExitCode | Should -Be $(if ($hasError) { 1 } else { 0 })
        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            $run.Output | Should -Match '\[ OK \]\s+Windows PowerShell 5\.1'
        }
        else {
            $run.Output | Should -Match '\[ERR \]\s+Windows PowerShell 5\.1'
        }
    }

    It 'exits with 1, and does not show a report that says Ready, when the checks could not run' {
        $global:LASTEXITCODE = 0

        $output = @(& $script:ScriptPath -ConfigPath '' -SkipSharePoint -PassThru 6>&1 2>$null)

        $LASTEXITCODE | Should -Be 1
        @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and [System.String]$_.MessageData.Message -match 'Ready' }) | Should -HaveCount 0
        @($output | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] }) | Should -HaveCount 0
    }

    It 'exits with 1, in a fresh process, when a check fails with an error that is not terminating' {
        # A stub module makes the collector write an error and return nothing: only an error preference of Stop turns that into a failure.
        $folder = Join-Path -Path $TestDrive -ChildPath 'stub'
        $module = Join-Path -Path $folder -ChildPath 'Modules\SPSSiteInventory.Common'
        $null = New-Item -Path $module -ItemType Directory -Force
        Copy-Item -LiteralPath $script:ScriptPath -Destination $folder
        Set-Content -Path (Join-Path $module 'SPSSiteInventory.Common.psd1') -Value "@{ RootModule = 'SPSSiteInventory.Common.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = @('Get-SPSReadinessCheck', 'Write-SPSReadinessReport') }"
        Set-Content -Path (Join-Path $module 'SPSSiteInventory.Common.psm1') -Value @'
function Get-SPSReadinessCheck { [CmdletBinding()] param ($ConfigPath, $ExampleConfigPath, [switch] $SkipSharePoint) Write-Error 'The checks failed.' }
function Write-SPSReadinessReport { param ($Check) Write-Output 'REPORT RENDERED'; [PSCustomObject]@{ IsReady = $true } }
'@

        $output = & $script:HostPath -NoProfile -NonInteractive -File (Join-Path $folder 'Test-SPSSiteInventoryReadiness.ps1') -ConfigPath 'x' | Out-String

        $LASTEXITCODE | Should -Be 1
        $output | Should -Not -Match 'REPORT RENDERED'
    }

    It 'sets the exit code on the success path too, so that an earlier failure of the caller is not read as its own' {
        $global:LASTEXITCODE = 5

        $summary = @(& $script:ScriptPath -ConfigPath $script:ValidSettings -SkipSharePoint -PassThru 6>$null)

        $LASTEXITCODE | Should -Be $(if ($summary[0].IsReady) { 0 } else { 1 })
        $LASTEXITCODE | Should -Not -Be 5
    }

    It 'sets the exit code to 0 when it is ready, in the source' {
        $text = Get-Content -LiteralPath $script:ScriptPath -Raw

        $text | Should -Match '(?s)if \(\$summary\.IsReady\) \{\s+exit 0\s+\}\s+exit 1'
    }

    It 'returns the summary only with -PassThru' {
        $withoutPassThru = @(& $script:ScriptPath -ConfigPath $script:MissingSettings -SkipSharePoint 6>$null)
        $withPassThru = @(& $script:ScriptPath -ConfigPath $script:MissingSettings -SkipSharePoint -PassThru 6>$null)

        $withoutPassThru | Should -BeNullOrEmpty
        $withPassThru.Count | Should -Be 1
        $withPassThru[0].IsReady | Should -BeFalse
        $withPassThru[0].ErrorCount | Should -BeGreaterThan 0
        @($withPassThru[0].Checks | Where-Object { $_.Name -eq 'Settings file' }).Status | Should -Be 'Error'
    }
}
