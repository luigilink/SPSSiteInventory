# The settings loader validates Scoring.Caps before the scan starts. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-SettingsFile {
        param ([string]$Name, [string]$Caps)
        $path = Join-Path $TestDrive $Name
        @"
@{
    EnvName = 'TEST'
    Scoring = @{
        Weights = @{ EventReceivers = 1.5; Workflow2010Count = 3.0 }
        $Caps
        Thresholds = @{ Moderate = 1.0; Complex = 6.0 }
        BlockingSignals = @()
    }
}
"@ | Set-Content -Path $path -Encoding UTF8
        $path
    }
}

Describe 'Get-SPSInventorySetting and Scoring.Caps' {
    It 'loads a file with caps, and gives them as they are written' {
        $path = New-SettingsFile -Name 'caps-valid.psd1' -Caps 'Caps = @{ EventReceivers = 4; Workflow2010Count = 7.5 }'

        $settings = Get-SPSInventorySetting -Path $path

        $settings.Scoring.Caps.EventReceivers | Should -Be 4
        $settings.Scoring.Caps.Workflow2010Count | Should -Be 7.5
    }

    It 'loads a file without caps, with an empty Caps, and with a null Caps' {
        foreach ($caps in '', 'Caps = @{}', 'Caps = $null') {
            $path = New-SettingsFile -Name 'caps-none.psd1' -Caps $caps

            { Get-SPSInventorySetting -Path $path } | Should -Not -Throw
        }
    }

    It 'rejects a cap that is not a number greater than 0, naming the file and the cap: <Caps>' -ForEach @(
        @{ Caps = 'Caps = @{ EventReceivers = 0 }' }
        @{ Caps = 'Caps = @{ EventReceivers = -4 }' }
        @{ Caps = "Caps = @{ EventReceivers = '4' }" }
        @{ Caps = 'Caps = @{ EventReceivers = $true }' }
    ) {
        $path = New-SettingsFile -Name 'caps-bad-value.psd1' -Caps $Caps

        { Get-SPSInventorySetting -Path $path } | Should -Throw -ExpectedMessage '*caps-bad-value.psd1*Scoring.Caps.EventReceivers must be a number greater than 0*'
    }

    It 'rejects a cap on a name that has no weight, naming the file and the name' {
        $path = New-SettingsFile -Name 'caps-bad-name.psd1' -Caps 'Caps = @{ EventReceiver = 4 }'

        { Get-SPSInventorySetting -Path $path } | Should -Throw -ExpectedMessage '*caps-bad-name.psd1*Scoring.Caps.EventReceiver is not a signal of Scoring.Weights*'
    }

    It 'rejects a Caps that is not a hashtable, naming the file' {
        $path = New-SettingsFile -Name 'caps-bad-type.psd1' -Caps "Caps = @('EventReceivers')"

        { Get-SPSInventorySetting -Path $path } | Should -Throw -ExpectedMessage "*caps-bad-type.psd1*Scoring.Caps must be a hashtable*"
    }

    It 'does not look at the caps of a Scoring section that is not a hashtable' {
        $path = Join-Path $TestDrive 'scoring-string.psd1'
        "@{ Scoring = 'none' }" | Set-Content -Path $path -Encoding UTF8

        { Get-SPSInventorySetting -Path $path } | Should -Not -Throw
    }
}
