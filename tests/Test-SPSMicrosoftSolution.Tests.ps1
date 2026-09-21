# Behavior tests for Test-SPSMicrosoftSolution (pure solution-name classification, no farm).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:Module = Get-Module -Name SPSSiteInventory.Common
}

Describe 'Test-SPSMicrosoftSolution' {
    It 'recognizes a Microsoft solution name' {
        (& $script:Module { Test-SPSMicrosoftSolution -Name 'microsoft.sharepoint.translation.wsp' }) | Should -BeTrue
    }

    It 'recognizes each shipped Microsoft / OOTB marker family' {
        $names = @(
            'microsoft.office.server.wsp'
            'sharepoint server standard.wsp'
            'osrc.wsp'
            'search-adminwebparts.wsp'
            'spscontentdeployment.wsp'
            'languagepack-fr-fr.wsp'
            'sts.wsp'
        )
        foreach ($n in $names) {
            (& $script:Module { param($x) Test-SPSMicrosoftSolution -Name $x } $n) | Should -BeTrue -Because "$n should be recognized as Microsoft / OOTB"
        }
    }

    It 'is case-insensitive' {
        (& $script:Module { Test-SPSMicrosoftSolution -Name 'MICROSOFT.Office.Server.wsp' }) | Should -BeTrue
    }

    It 'treats an in-house solution name as non-Microsoft (custom)' {
        (& $script:Module { Test-SPSMicrosoftSolution -Name 'contoso.intranet.wsp' }) | Should -BeFalse
        (& $script:Module { Test-SPSMicrosoftSolution -Name 'mercure3.wsp' }) | Should -BeFalse
    }

    It 'honours an extra Microsoft prefix' {
        (& $script:Module { Test-SPSMicrosoftSolution -Name 'vendorx.addon.wsp' }) | Should -BeFalse
        (& $script:Module { Test-SPSMicrosoftSolution -Name 'vendorx.addon.wsp' -ExtraMicrosoftPrefix @('vendorx.') }) | Should -BeTrue
    }

    It 'treats an empty name as non-Microsoft (conservative)' {
        (& $script:Module { Test-SPSMicrosoftSolution -Name '' }) | Should -BeFalse
        (& $script:Module { Test-SPSMicrosoftSolution -Name $null }) | Should -BeFalse
    }
}
