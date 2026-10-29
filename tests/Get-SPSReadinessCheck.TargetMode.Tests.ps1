# The readiness check compares the settings with the example of their own mode: the blocking signals and the weights are
# not the same in the two modes, so a file of the on-premises mode is not told that it lacks the migration blockers.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:ModuleName = 'SPSSiteInventory.Common'
    $script:ReportsFolder = Join-Path -Path $TestDrive -ChildPath 'Reports'
    New-Item -Path $script:ReportsFolder -ItemType Directory -Force | Out-Null

    function Write-TestSettings {
        param ([string]$Name, [string]$Mode, [string]$Blocking, [string]$Weights)
        $modeLine = if ($Mode) { "TargetMode = '$Mode'" } else { '' }
        $path = Join-Path -Path $TestDrive -ChildPath $Name
        @"
@{
    EnvName           = 'LAB'
    $modeLine
    WebApplicationUrl = @()
    OutputFolder      = '$($script:ReportsFolder)'
    Scoring           = @{
        Weights         = @{ $Weights }
        Thresholds      = @{ Moderate = 2; Complex = 5 }
        BlockingSignals = @($Blocking)
    }
}
"@ | Set-Content -Path $path -Encoding UTF8
        return $path
    }

    function Get-TestResult {
        param ([object[]]$Check, [string]$Name)
        return @($Check | Where-Object { $_.Name -eq $Name })[0]
    }

    $script:OnlineExample = Write-TestSettings -Name 'online.example.psd1' -Blocking "'UsesFullTrustCode', 'InfoPathFormCount'" -Weights 'InfoPathFormCount = 3.0; UsesFullTrustCode = 1.0'
    $script:OnPremExample = Write-TestSettings -Name 'onprem.example.psd1' -Mode 'SharePointOnPrem' -Blocking "'InfoPathFormCount'" -Weights 'InfoPathFormCount = 3.0; UsesFullTrustCode = 4.0'
}

Describe 'Get-SPSReadinessCheck and the target mode' {
    BeforeEach {
        Mock -ModuleName $script:ModuleName Get-SPSHostEnvironment {
            [PSCustomObject]@{ Edition = 'Desktop'; Version = '5.1.14393.6343'; VersionMajor = 5; VersionMinor = 1; ComputerName = 'SP01'; UserName = 'CONTOSO\spfarm'; IsElevated = $true }
        }
    }

    It 'compares a file of the default mode with the example of the default mode, even when the on-premises example is given' {
        $path = Write-TestSettings -Name 'online-user.psd1' -Blocking "'InfoPathFormCount'" -Weights 'InfoPathFormCount = 3.0; UsesFullTrustCode = 1.0'

        $checks = @(Get-SPSReadinessCheck -ConfigPath $path -ExampleConfigPath $script:OnlineExample -OnPremExampleConfigPath $script:OnPremExample -SkipSharePoint)

        $result = Get-TestResult -Check $checks -Name 'Blocking signals'
        $result.Status | Should -Be 'Warning'
        $result.Detail | Should -Match 'UsesFullTrustCode'
    }

    It 'compares a file of the on-premises mode with the on-premises example, which does not ask for the migration blockers' {
        $path = Write-TestSettings -Name 'onprem-user.psd1' -Mode 'SharePointOnPrem' -Blocking "'InfoPathFormCount'" -Weights 'InfoPathFormCount = 3.0; UsesFullTrustCode = 4.0'

        $checks = @(Get-SPSReadinessCheck -ConfigPath $path -ExampleConfigPath $script:OnlineExample -OnPremExampleConfigPath $script:OnPremExample -SkipSharePoint)

        (Get-TestResult -Check $checks -Name 'Blocking signals').Status | Should -Be 'OK'
        (Get-TestResult -Check $checks -Name 'Signal weights').Status | Should -Be 'OK'
    }

    It 'warns a file of the on-premises mode about the blocking signals of the on-premises example that it does not have' {
        $path = Write-TestSettings -Name 'onprem-missing.psd1' -Mode 'SharePointOnPrem' -Blocking '' -Weights 'InfoPathFormCount = 3.0'

        $checks = @(Get-SPSReadinessCheck -ConfigPath $path -ExampleConfigPath $script:OnlineExample -OnPremExampleConfigPath $script:OnPremExample -SkipSharePoint)

        $blocking = Get-TestResult -Check $checks -Name 'Blocking signals'
        $blocking.Status | Should -Be 'Warning'
        $blocking.Detail | Should -Match 'InfoPathFormCount'
        $blocking.Detail | Should -Not -Match 'UsesFullTrustCode'
        (Get-TestResult -Check $checks -Name 'Signal weights').Detail | Should -Match 'UsesFullTrustCode'
    }

    It 'falls back on the default example when the file is of the on-premises mode and no on-premises example is given' {
        $path = Write-TestSettings -Name 'onprem-noexample.psd1' -Mode 'SharePointOnPrem' -Blocking "'InfoPathFormCount'" -Weights 'InfoPathFormCount = 3.0; UsesFullTrustCode = 4.0'

        $checks = @(Get-SPSReadinessCheck -ConfigPath $path -ExampleConfigPath $script:OnlineExample -SkipSharePoint)

        (Get-TestResult -Check $checks -Name 'Blocking signals').Detail | Should -Match 'UsesFullTrustCode'
    }

    It 'says that the on-premises example was not found, and not that the default one was, when it is missing' {
        $path = Write-TestSettings -Name 'onprem-missingexample.psd1' -Mode 'SharePointOnPrem' -Blocking "'InfoPathFormCount'" -Weights 'InfoPathFormCount = 3.0'
        $missing = Join-Path $TestDrive 'nowhere.onprem.example.psd1'

        $checks = @(Get-SPSReadinessCheck -ConfigPath $path -ExampleConfigPath $script:OnlineExample -OnPremExampleConfigPath $missing -SkipSharePoint)

        $result = Get-TestResult -Check $checks -Name 'Comparison with the example'
        $result.Status | Should -Be 'Skipped'
        $result.Detail | Should -Match ([regex]::Escape($missing))
    }

    It 'reports a misspelled mode as an error of the settings file and does not compare it' {
        $path = Write-TestSettings -Name 'bad-mode.psd1' -Mode 'OnPrem' -Blocking "'InfoPathFormCount'" -Weights 'InfoPathFormCount = 3.0'

        $checks = @(Get-SPSReadinessCheck -ConfigPath $path -ExampleConfigPath $script:OnlineExample -OnPremExampleConfigPath $script:OnPremExample -SkipSharePoint)

        $content = Get-TestResult -Check $checks -Name 'Settings content'
        $content.Status | Should -Be 'Error'
        $content.Detail | Should -Match "TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'"
        Get-TestResult -Check $checks -Name 'Blocking signals' | Should -BeNullOrEmpty
    }
}
