# Format-SPSScanTiming writes the last line of the log of a scan. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Format-Timing {
        param ([object[]]$Phase, [double]$Seconds)
        & $script:Module { param ($Rows, $Total) Format-SPSScanTiming -Phase $Rows -Seconds $Total } $Phase $Seconds
    }
}

Describe 'Format-SPSScanTiming' {
    It 'gives the total and then each phase, in the order that they ran' {
        $phase = @(
            [PSCustomObject]@{ Name = 'Loading the settings and the SharePoint commands'; Seconds = 12.4 }
            [PSCustomObject]@{ Name = 'Enumerating the site collections'; Seconds = 41.2 }
            [PSCustomObject]@{ Name = 'Collecting the customization signals'; Seconds = 1081.7 }
        )

        Format-Timing -Phase $phase -Seconds 1144.3 | Should -BeExactly 'Scan finished in 19 min 04 s. By phase: Loading the settings and the SharePoint commands 12 s; Enumerating the site collections 41 s; Collecting the customization signals 18 min 02 s.'
    }

    It 'gives only the total when no phase was recorded' {
        Format-Timing -Phase @() -Seconds 5 | Should -BeExactly 'Scan finished in 5 s.'
    }

    It 'reads one phase as a list of one' {
        Format-Timing -Phase @([PSCustomObject]@{ Name = 'Writing the reports'; Seconds = 3.2 }) -Seconds 3.2 | Should -BeExactly 'Scan finished in 3.2 s. By phase: Writing the reports 3.2 s.'
    }
}
