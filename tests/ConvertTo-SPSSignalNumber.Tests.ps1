# Behavior tests for ConvertTo-SPSSignalNumber (pure, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-SignalNumber {
        param ([object]$Value)
        & $script:Module { param ($Item) ConvertTo-SPSSignalNumber -Value $Item } $Value
    }

    function Invoke-InCulture {
        param ([string]$Culture, [scriptblock]$Script)
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
            & $Script
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }
    }
}

Describe 'ConvertTo-SPSSignalNumber' {
    It 'returns 0 for nothing, an empty text and a blank text' {
        Get-SignalNumber -Value $null | Should -Be 0
        Get-SignalNumber -Value '' | Should -Be 0
        Get-SignalNumber -Value '   ' | Should -Be 0
    }

    It 'returns 1 for true, 0 for false' {
        Get-SignalNumber -Value $true | Should -Be 1
        Get-SignalNumber -Value $false | Should -Be 0
    }

    It 'returns a number as it is' {
        Get-SignalNumber -Value 5 | Should -Be 5
        Get-SignalNumber -Value 25.5 | Should -Be 25.5
        Get-SignalNumber -Value ([decimal]12.25) | Should -Be 12.25
        Get-SignalNumber -Value ([int64]3000000000) | Should -Be 3000000000
        Get-SignalNumber -Value ([byte]7) | Should -Be 7
        Get-SignalNumber -Value (-2.5) | Should -Be -2.5
    }

    It 'reads a text that is a number, and counts any other text as 1' {
        Get-SignalNumber -Value '12' | Should -Be 12
        Get-SignalNumber -Value '12.25' | Should -Be 12.25
        Get-SignalNumber -Value 'Contoso' | Should -Be 1
    }

    It 'returns the same number in <Culture>, also for a number with decimals' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
        @{ Culture = 'es-ES' }
    ) {
        $result = Invoke-InCulture -Culture $Culture -Script {
            [PSCustomObject]@{
                Small = Get-SignalNumber -Value 0.0016
                Double = Get-SignalNumber -Value 400.75
                Decimal = Get-SignalNumber -Value ([decimal]12.25)
                Text = Get-SignalNumber -Value '12.25'
                Whole = Get-SignalNumber -Value 5
            }
        }

        $result.Small | Should -Be 0.0016
        $result.Double | Should -Be 400.75
        $result.Decimal | Should -Be 12.25
        $result.Text | Should -Be 12.25
        $result.Whole | Should -Be 5
    }
}
