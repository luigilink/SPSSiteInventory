# Get-SPSScoringCap reads and validates the optional Caps of the Scoring section, and Format-SPSScoringCap says them for the log. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-Cap {
        param ([AllowNull()][System.Collections.IDictionary]$Scoring)
        & $script:Module { param ($Section) Get-SPSScoringCap -Scoring $Section } $Scoring
    }

    function Get-Scoring {
        param ([object]$Caps)
        @{ Weights = @{ EventReceivers = 1.5; Workflow2010Count = 3.0; CustomMasterPage = 2.0; Muted = 0 }; Caps = $Caps }
    }
}

Describe 'Get-SPSScoringCap' {
    It 'gives no cap when there is no Caps key, when it is null, when it is empty, or when there is no Scoring section' {
        $withoutKey = Get-Cap -Scoring @{ Weights = @{ EventReceivers = 1.5 } }
        $withNull = Get-Cap -Scoring (Get-Scoring -Caps $null)
        $withEmpty = Get-Cap -Scoring (Get-Scoring -Caps @{})
        $withoutScoring = Get-Cap -Scoring $null

        foreach ($cap in $withoutKey, $withNull, $withEmpty, $withoutScoring) {
            , $cap | Should -BeOfType [hashtable]
            $cap.Count | Should -Be 0
        }
    }

    It 'gives the caps as numbers whatever the numeric type of the settings file, for names that are not case-sensitive' {
        $cap = Get-Cap -Scoring (Get-Scoring -Caps @{ EventReceivers = 4; Workflow2010Count = [single]7.5; CustomMasterPage = [long]3; Muted = [decimal]2.25 })

        $cap.Count | Should -Be 4
        $cap['EventReceivers'] | Should -Be 4
        $cap['EventReceivers'] | Should -BeOfType [double]
        $cap['Workflow2010Count'] | Should -Be 7.5
        $cap['CustomMasterPage'] | Should -Be 3
        $cap['Muted'] | Should -Be 2.25
        $cap['eventreceivers'] | Should -Be 4
    }

    It 'rejects a cap that is not a number greater than 0, and names it: <Name>' -ForEach @(
        @{ Name = 'zero'; Value = 0 }
        @{ Name = 'negative'; Value = -1 }
        @{ Name = 'a string'; Value = '5' }
        @{ Name = 'a boolean'; Value = $true }
        @{ Name = 'null'; Value = $null }
        @{ Name = 'not a number'; Value = [double]::NaN }
        @{ Name = 'infinite'; Value = [double]::PositiveInfinity }
        @{ Name = 'a list'; Value = @(4) }
    ) {
        { Get-Cap -Scoring (Get-Scoring -Caps @{ EventReceivers = $Value }) } | Should -Throw -ExpectedMessage '*Scoring.Caps.EventReceivers must be a number greater than 0*'
    }

    It 'rejects a Caps that is not a hashtable: <Name>' -ForEach @(
        @{ Name = 'a string'; Value = 'EventReceivers' }
        @{ Name = 'a list'; Value = @('EventReceivers') }
        @{ Name = 'a number'; Value = 5 }
    ) {
        { Get-Cap -Scoring (Get-Scoring -Caps $Value) } | Should -Throw -ExpectedMessage '*Scoring.Caps must be a hashtable*'
    }

    It 'rejects a cap on a name that has no weight, which is most likely a misspelled signal' {
        { Get-Cap -Scoring (Get-Scoring -Caps @{ EventReceiver = 4 }) } | Should -Throw -ExpectedMessage '*Scoring.Caps.EventReceiver is not a signal of Scoring.Weights*'
        { Get-Cap -Scoring @{ Caps = @{ EventReceivers = 4 } } } | Should -Throw -ExpectedMessage '*Scoring.Caps.EventReceivers is not a signal of Scoring.Weights*'
        { Get-Cap -Scoring @{ Weights = 'EventReceivers'; Caps = @{ EventReceivers = 4 } } } | Should -Throw -ExpectedMessage '*Scoring.Caps.EventReceivers is not a signal of Scoring.Weights*'
    }

    It 'checks the value of a cap before the name, so that the message says what is wrong first' {
        { Get-Cap -Scoring (Get-Scoring -Caps @{ EventReceiver = 0 }) } | Should -Throw -ExpectedMessage '*Scoring.Caps.EventReceiver must be a number greater than 0*'
    }

    It 'reports the first invalid cap by name, whatever the order of the hashtable' {
        # Many names, because the order of a hashtable changes from one process to the next: with a few, a missing sort would pass in some of them.
        $weights = @{}
        $caps = @{}
        foreach ($name in [char[]](90..65) | ForEach-Object { 'Signal' + $_ }) {
            $weights[$name] = 1
            $caps[$name] = 0
        }

        { Get-Cap -Scoring @{ Weights = $weights; Caps = $caps } } | Should -Throw -ExpectedMessage '*Scoring.Caps.SignalA must be a number greater than 0*'
    }

    It 'does not change the section that it reads' {
        $scoring = Get-Scoring -Caps @{ EventReceivers = 4 }

        $null = Get-Cap -Scoring $scoring

        $scoring.Caps.Count | Should -Be 1
        $scoring.Caps['EventReceivers'] | Should -Be 4
        $scoring.Caps['EventReceivers'] | Should -BeOfType [int]
    }
}

Describe 'Format-SPSScoringCap' {
    BeforeAll {
        function Format-Cap {
            param ([System.Collections.IDictionary]$Cap)
            & $script:Module { param ($Value) Format-SPSScoringCap -Cap $Value } $Cap
        }
    }

    It 'gives an empty string when there is no cap' {
        Format-Cap -Cap @{} | Should -BeExactly ''
    }

    It 'says each cap, in alphabetical order whatever the order of the hashtable, with at most two decimals' {
        # Many names, because the order of a hashtable changes from one process to the next: with a few, a missing sort would pass in some of them.
        $cap = @{}
        $expected = [System.Collections.Generic.List[string]]::new()
        foreach ($letter in 65..90) {
            $shown = [string]($letter - 64)
            $cap['Signal' + [char]$letter] = [double]($letter - 64)
            if ($letter -eq 65) {
                $cap['SignalA'] = 7.5
                $shown = '7.5'
            }
            if ($letter -eq 66) {
                $cap['SignalB'] = 0.125
                $shown = '0.13'
            }
            $expected.Add(('Signal{0} at most {1}' -f [char]$letter, $shown))
        }

        Format-Cap -Cap $cap | Should -BeExactly ($expected.ToArray() -join ', ')
    }

    It 'writes the numbers the same way in <Culture>' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
    ) {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
            $text = Format-Cap -Cap @{ EventReceivers = 4.5; Workflow2010Count = 1200.25 }
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }

        $text | Should -BeExactly 'EventReceivers at most 4.5, Workflow2010Count at most 1200.25'
    }
}
