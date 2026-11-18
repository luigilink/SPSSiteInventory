# Complete-SPSScanPhase ends a phase of the scan: it records the phase for the manifest, logs how long it took and restarts the stopwatch. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
}

Describe 'Complete-SPSScanPhase' {
    It 'records the phase with its seconds, logs it once at the information level with what it handled, and restarts the stopwatch' {
        InModuleScope SPSSiteInventory.Common {
            Mock Add-SPSInventoryEvent { }
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Start-Sleep -Milliseconds 400
            $timing = [System.Collections.Generic.List[object]]::new()

            Complete-SPSScanPhase -Name 'Enumerating the site collections' -Stopwatch $watch -Timing $timing -Detail '34 site collection(s)'

            $timing | Should -HaveCount 1
            $timing[0].Name | Should -BeExactly 'Enumerating the site collections'
            $timing[0].Seconds | Should -BeGreaterOrEqual 0.3
            $timing[0].Seconds | Should -BeLessThan 60
            [System.Math]::Round($timing[0].Seconds, 1) | Should -Be $timing[0].Seconds
            Should -Invoke Add-SPSInventoryEvent -Times 1 -Exactly -ParameterFilter { $Level -eq 'Information' -and $Message -match '^Enumerating the site collections: done in \d+(\.\d)? s \(34 site collection\(s\)\)\.$' }
            $watch.IsRunning | Should -BeTrue
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 0.2
        }
    }

    It 'leaves out the parentheses when the phase has no detail' {
        InModuleScope SPSSiteInventory.Common {
            Mock Add-SPSInventoryEvent { }
            $timing = [System.Collections.Generic.List[object]]::new()

            Complete-SPSScanPhase -Name 'Loading the settings and the SharePoint commands' -Stopwatch ([System.Diagnostics.Stopwatch]::StartNew()) -Timing $timing

            Should -Invoke Add-SPSInventoryEvent -Times 1 -Exactly -ParameterFilter { $Message -match '^Loading the settings and the SharePoint commands: done in \d+(\.\d)? s\.$' }
        }
    }

    It 'adds the phases to the list one after the other, from the same stopwatch' {
        InModuleScope SPSSiteInventory.Common {
            Mock Add-SPSInventoryEvent { }
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $timing = [System.Collections.Generic.List[object]]::new()

            Complete-SPSScanPhase -Name 'First' -Stopwatch $watch -Timing $timing
            Complete-SPSScanPhase -Name 'Second' -Stopwatch $watch -Timing $timing -Detail '2 thing(s)'

            @($timing | ForEach-Object { $_.Name }) | Should -Be @('First', 'Second')
            Should -Invoke Add-SPSInventoryEvent -Times 2 -Exactly
        }
    }

    It 'logs nothing to the output of the caller, so that a function can return the result of its work' {
        InModuleScope SPSSiteInventory.Common {
            Mock Add-SPSInventoryEvent { 'a line of the log' }
            # Out-Host is what keeps the line out of the output: the test fails when it is missing, and shows nothing when it is there.
            Mock Out-Host { }

            $output = Complete-SPSScanPhase -Name 'Phase' -Stopwatch ([System.Diagnostics.Stopwatch]::StartNew()) -Timing ([System.Collections.Generic.List[object]]::new())

            $output | Should -BeNullOrEmpty
        }
    }
}
