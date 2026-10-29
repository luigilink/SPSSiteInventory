# The wiki documents the on-premises preset: these tests keep the documented values true.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:OnPrem = Get-SPSInventorySetting -Path (Join-Path $repoRoot 'src/config/inventory-settings.onprem.example.psd1')
    $script:Wiki = Get-Content -Path (Join-Path $repoRoot 'wiki/Configuration.md') -Raw
    $script:Section = ($script:Wiki -split '(?m)^## ')[1..99] | Where-Object { $_ -like 'TargetMode section*' }
    $script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture
}

Describe 'The wiki page on the target mode' {
    It 'has a TargetMode section, and a row for the setting in the table of the top-level settings' {
        $script:Section | Should -Not -BeNullOrEmpty
        $script:Wiki | Should -Match '\| `TargetMode` \| string \|'
    }

    It 'names the two modes and the file of each' {
        $script:Section | Should -Match '`SharePointOnline`'
        $script:Section | Should -Match '`SharePointOnPrem`'
        $script:Section | Should -Match 'inventory-settings\.example\.psd1'
        $script:Section | Should -Match 'inventory-settings\.onprem\.example\.psd1'
    }

    It 'documents the names of the four categories of each mode, as the profile gives them' {
        $module = Get-Module SPSSiteInventory.Common
        foreach ($mode in 'SharePointOnline', 'SharePointOnPrem') {
            $profile = & $module { param ($m) Get-SPSTargetProfile -TargetMode $m } $mode
            foreach ($category in 1..4) {
                $script:Section | Should -Match ([regex]::Escape($profile.CategoryName[$category])) -Because "the $mode name of the category $category"
            }
        }
    }

    It 'documents the weights of the preset that it quotes, as the example file has them' {
        foreach ($signal in 'UsesFullTrustCode', 'UsesCustomFarmFeature', 'CustomMasterPage', 'SandboxSolutions') {
            $weight = $script:OnPrem.Scoring.Weights[$signal].ToString('0.0', $script:Invariant)

            $script:Section | Should -Match ('`{0} = {1}`' -f $signal, [regex]::Escape($weight)) -Because "the wiki quotes $signal"
        }
    }

    It 'says that the preset blocks on InfoPath only, as the example file does' {
        @($script:OnPrem.Scoring.BlockingSignals) | Should -Be @('InfoPathFormCount')
        $script:Section | Should -Match 'blocks on\s+`InfoPathFormCount` only'
    }

    It 'says that a site collection with 100 subsites is Modern-ready in the preset, which is true' {
        $result = Measure-SPSSiteComplexity -Signals @{ SubsiteCount = 100; MaxSubsiteDepth = 6 } -Scoring $script:OnPrem.Scoring -TargetMode 'SharePointOnPrem'

        $result.CategoryName | Should -Be 'Modern-ready'
        $script:Section | Should -Match '100 subsites'
    }

    It 'documents the weights of the modern-readiness signals that it quotes, as the example file has them' {
        foreach ($signal in 'AlternateCssUrlCount', 'XsltListViewCount', 'ScriptWebPartCount', 'ClassicExperienceOptOutCount', 'ClassicExperienceListCount') {
            $weight = $script:OnPrem.Scoring.Weights[$signal].ToString('0.0', $script:Invariant)

            $script:Section | Should -Match ('`{0} = {1}`' -f $signal, [regex]::Escape($weight)) -Because "the wiki quotes $signal"
        }
    }

    It 'says that the alerts and the HTML section of the modern-readiness signals are not there yet, so that the page does not promise them' {
        $script:Section | Should -Match 'no section for them yet'
        $script:Section | Should -Match 'raise no alert yet'
        $script:Section | Should -Match 'still those of a migration to SharePoint Online'
    }

    It 'dates the end of support that it cites, 14 July 2026, in the past tense, since that date has passed' {
        ([regex]::Matches($script:Section, '14 July 2026')).Count | Should -BeGreaterOrEqual 2
        $script:Section | Should -Not -Match 'supported until 14 July 2026'
        $script:Section | Should -Match 'support ended on 14 July 2026'
    }
}
