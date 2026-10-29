# The TargetMode setting: absent means SharePointOnline, a wrong value stops the run before the farm is read,
# and the two example files, one for each mode, are valid settings files of their mode.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:OnlineExample = Join-Path $repoRoot 'src/config/inventory-settings.example.psd1'
    $script:OnPremExample = Join-Path $repoRoot 'src/config/inventory-settings.onprem.example.psd1'

    function Write-Settings {
        param ([string]$Name, [string]$ModeLine)
        $path = Join-Path $TestDrive $Name
        @"
@{
    EnvName = 'TEST'
    $ModeLine
    Scoring = @{ Weights = @{}; Thresholds = @{ Moderate = 1; Complex = 6 }; BlockingSignals = @() }
}
"@ | Set-Content -Path $path -Encoding UTF8
        return $path
    }
}

Describe 'Get-SPSInventorySetting and the TargetMode setting' {
    It 'loads a settings file that has no TargetMode, as every file of an earlier version' {
        $path = Write-Settings -Name 'none.psd1' -ModeLine ''

        $settings = Get-SPSInventorySetting -Path $path

        $settings.ContainsKey('TargetMode') | Should -BeFalse
    }

    It 'loads each of the two modes' -ForEach @(
        @{ Mode = 'SharePointOnline' }
        @{ Mode = 'SharePointOnPrem' }
        @{ Mode = 'sharepointonprem' }
    ) {
        $path = Write-Settings -Name ('mode-{0}.psd1' -f $Mode) -ModeLine ("TargetMode = '{0}'" -f $Mode)

        (Get-SPSInventorySetting -Path $path).TargetMode | Should -Be $Mode
    }

    It 'stops on a misspelled mode, and names the file and the two modes' -ForEach @(
        @{ Line = "TargetMode = 'OnPrem'" }
        @{ Line = "TargetMode = ''" }
        @{ Line = 'TargetMode = $null' }
        @{ Line = 'TargetMode = 1' }
        @{ Line = 'TargetMode = $true' }
        @{ Line = "TargetMode = @('SharePointOnPrem')" }
    ) {
        $path = Write-Settings -Name 'bad.psd1' -ModeLine $Line

        $message = $null
        try { $null = Get-SPSInventorySetting -Path $path } catch { $message = $_.Exception.Message }

        $message | Should -Match 'bad\.psd1'
        $message | Should -Match "TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'"
    }
}

Describe 'The example settings of the two modes' {
    BeforeAll {
        $script:Online = Get-SPSInventorySetting -Path $script:OnlineExample
        $script:OnPrem = Get-SPSInventorySetting -Path $script:OnPremExample
    }

    It 'ship one file for each mode, with the same sections' {
        $script:OnPrem.TargetMode | Should -Be 'SharePointOnPrem'
        @($script:Online.Keys | Sort-Object) | Should -Be @(($script:OnPrem.Keys | Where-Object { $_ -ne 'TargetMode' }) + @() | Sort-Object)
    }

    It 'leave the default example without a TargetMode, so that it stays the file of every earlier version' {
        $script:Online.ContainsKey('TargetMode') | Should -BeFalse
    }

    It 'weigh the same signals in both files, but for the two that stop blocking in the on-premises mode' {
        $onlyOnPrem = @($script:OnPrem.Scoring.Weights.Keys | Where-Object { -not $script:Online.Scoring.Weights.ContainsKey($_) } | Sort-Object)
        $onlyOnline = @($script:Online.Scoring.Weights.Keys | Where-Object { -not $script:OnPrem.Scoring.Weights.ContainsKey($_) } | Sort-Object)

        $onlyOnPrem | Should -Be @('UsesCustomFarmFeature', 'UsesFullTrustCode')
        $onlyOnline | Should -BeNullOrEmpty
    }

    It 'only block the site collections that nothing modern can replace, and not the full-trust code that SPFx replaces' {
        @($script:OnPrem.Scoring.BlockingSignals) | Should -Be @('InfoPathFormCount')
        @($script:OnPrem.Scoring.BlockingSignals) | Should -Not -Contain 'UsesFullTrustCode'
        @($script:OnPrem.Scoring.BlockingSignals) | Should -Not -Contain 'UsesCustomFarmFeature'
    }

    It 'keep every blocking signal of the on-premises file among the weights, or in the signals that the toolkit collects' {
        foreach ($name in $script:OnPrem.Scoring.BlockingSignals) {
            $script:OnPrem.Scoring.Weights.ContainsKey($name) | Should -BeTrue
        }
    }

    It 'plan the waves of each mode with the names of that mode' {
        @($script:Online.MigrationWaves | ForEach-Object { $_.Name }) | Should -Be @('Quick wins', 'Light remediation', 'Rebuild', 'Projects / blockers')
        @($script:OnPrem.MigrationWaves | ForEach-Object { $_.Name }) | Should -Be @('Ready', 'Light remediation', 'Rebuild (SPFx)', 'Blocked')
    }

    It 'use the waves that the profile of each mode plans by default, so that a file without waves and a file with the example agree' {
        $profileOnPrem = & (Get-Module SPSSiteInventory.Common) { Get-SPSTargetProfile -TargetMode 'SharePointOnPrem' }
        $profileOnline = & (Get-Module SPSSiteInventory.Common) { Get-SPSTargetProfile }

        @($script:OnPrem.MigrationWaves | ForEach-Object { '{0}|{1}|{2}' -f $_.Wave, $_.Name, ($_.Categories -join ',') }) |
            Should -Be @($profileOnPrem.MigrationWave | ForEach-Object { '{0}|{1}|{2}' -f $_.Wave, $_.Name, ($_.Categories -join ',') })
        @($script:Online.MigrationWaves | ForEach-Object { '{0}|{1}|{2}' -f $_.Wave, $_.Name, ($_.Categories -join ',') }) |
            Should -Be @($profileOnline.MigrationWave | ForEach-Object { '{0}|{1}|{2}' -f $_.Wave, $_.Name, ($_.Categories -join ',') })
    }

    It 'are ASCII files with a byte order mark and CRLF line ends, as the other PowerShell data files' {
        foreach ($path in $script:OnlineExample, $script:OnPremExample) {
            $bytes = [System.IO.File]::ReadAllBytes($path)

            $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
            $text | Should -Match '^[\x00-\x7F]*$'
            ($text -split "`n" | Where-Object { $_ -ne '' -and $_ -notmatch "`r$" }) | Should -BeNullOrEmpty
        }
    }
}
