# Behavior tests for ConvertTo-SPSSizeText (pure formatting, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # ConvertTo-SPSSizeText is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common
    function Get-SizeText {
        param ([double] $SizeGB)
        & $script:Module { param ($Size) ConvertTo-SPSSizeText -SizeGB $Size } $SizeGB
    }
}

Describe 'ConvertTo-SPSSizeText' {
    It 'rounds to two decimals and drops the trailing zeros' {
        Get-SizeText -SizeGB 13.75 | Should -Be '13.75'
        Get-SizeText -SizeGB 12.5 | Should -Be '12.5'
        Get-SizeText -SizeGB 100 | Should -Be '100'
        Get-SizeText -SizeGB 0.0587 | Should -Be '0.06'
    }

    It 'says that a size that is not zero but rounds to zero is under 0.01' {
        Get-SizeText -SizeGB 0.0004 | Should -Be '< 0.01'
        Get-SizeText -SizeGB 0.0049 | Should -Be '< 0.01'
    }

    It 'shows 0 for an empty farm' {
        Get-SizeText -SizeGB 0 | Should -Be '0'
    }

    It 'does not depend on the culture' {
        $culture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new('fr-FR')
            Get-SizeText -SizeGB 12.25 | Should -Be '12.25'
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
        }
    }
}
