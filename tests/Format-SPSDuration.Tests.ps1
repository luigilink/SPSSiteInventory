# Format-SPSDuration writes the seconds of a phase or of a site collection as a short text for the log. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Format-Duration {
        param ([double]$Seconds)
        & $script:Module { param ($Value) Format-SPSDuration -Seconds $Value } $Seconds
    }
}

Describe 'Format-SPSDuration' {
    It 'keeps one decimal under 10 seconds, and none when there is none' -ForEach @(
        @{ Seconds = 0; Text = '0 s' }
        @{ Seconds = 0.04; Text = '0 s' }
        @{ Seconds = 0.4; Text = '0.4 s' }
        @{ Seconds = 3; Text = '3 s' }
        @{ Seconds = 3.44; Text = '3.4 s' }
        @{ Seconds = 3.45; Text = '3.5 s' }
        @{ Seconds = 9.94; Text = '9.9 s' }
    ) {
        Format-Duration -Seconds $Seconds | Should -BeExactly $Text
    }

    It 'gives whole seconds from 10 seconds to a minute, and does not write 9.96 as 10.0' -ForEach @(
        @{ Seconds = 9.96; Text = '10 s' }
        @{ Seconds = 10; Text = '10 s' }
        @{ Seconds = 38.4; Text = '38 s' }
        @{ Seconds = 59.4; Text = '59 s' }
    ) {
        Format-Duration -Seconds $Seconds | Should -BeExactly $Text
    }

    It 'gives minutes and seconds under an hour, and rounds the seconds before it cuts the text' -ForEach @(
        @{ Seconds = 59.6; Text = '1 min 00 s' }
        @{ Seconds = 60; Text = '1 min 00 s' }
        @{ Seconds = 125; Text = '2 min 05 s' }
        @{ Seconds = 1144.3; Text = '19 min 04 s' }
        @{ Seconds = 3599.4; Text = '59 min 59 s' }
    ) {
        Format-Duration -Seconds $Seconds | Should -BeExactly $Text
    }

    It 'gives hours, minutes and seconds from an hour on, and does not cap the hours at a day' -ForEach @(
        @{ Seconds = 3599.6; Text = '1 h 00 min 00 s' }
        @{ Seconds = 3600; Text = '1 h 00 min 00 s' }
        @{ Seconds = 3792; Text = '1 h 03 min 12 s' }
        @{ Seconds = 90061; Text = '25 h 01 min 01 s' }
    ) {
        Format-Duration -Seconds $Seconds | Should -BeExactly $Text
    }

    It 'writes the same text whatever the culture of the server' {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')

            Format-Duration -Seconds 3.4 | Should -BeExactly '3.4 s'
            Format-Duration -Seconds 125 | Should -BeExactly '2 min 05 s'
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }
    }

    It 'rejects a negative number of seconds' {
        { Format-Duration -Seconds -1 } | Should -Throw
    }
}
