# Behavior tests for Get-SPSTargetProfile (pure, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-TargetProfile {
        param ([object]$Mode, [switch]$NoMode)
        if ($NoMode) {
            & $script:Module { Get-SPSTargetProfile }
        }
        else {
            & $script:Module { param ($Value) Get-SPSTargetProfile -TargetMode $Value } $Mode
        }
    }
}

Describe 'Get-SPSTargetProfile' {
    It 'is the SharePointOnline mode when the mode is not given' {
        $profile = Get-TargetProfile -NoMode

        $profile.TargetMode | Should -Be 'SharePointOnline'
        $profile.CategoryName[1] | Should -Be 'Simple'
        $profile.CategoryName[2] | Should -Be 'Moderate'
        $profile.CategoryName[3] | Should -Be 'Complex'
        $profile.CategoryName[4] | Should -Be 'Blocking'
    }

    It 'names the categories of the on-premises mode after the modernization it plans' {
        $profile = Get-TargetProfile -Mode 'SharePointOnPrem'

        $profile.TargetMode | Should -Be 'SharePointOnPrem'
        $profile.CategoryName[1] | Should -Be 'Modern-ready'
        $profile.CategoryName[2] | Should -Be 'Light remediation'
        $profile.CategoryName[3] | Should -Be 'Rebuild (SPFx)'
        $profile.CategoryName[4] | Should -Be 'Blocked'
    }

    It 'keeps the four categories numbered 1 to 4 in both modes' {
        foreach ($mode in 'SharePointOnline', 'SharePointOnPrem') {
            $profile = Get-TargetProfile -Mode $mode

            @($profile.CategoryName.Keys | Sort-Object) | Should -Be @(1, 2, 3, 4)
            @($profile.CategorySlug.Keys | Sort-Object) | Should -Be @(1, 2, 3, 4)
        }
    }

    It 'gives the name of a mode in its canonical case, whatever the case of the value' {
        foreach ($value in 'sharepointonprem', 'SHAREPOINTONPREM', 'SharePointOnPrem') {
            (Get-TargetProfile -Mode $value).TargetMode | Should -BeExactly 'SharePointOnPrem'
        }
        (Get-TargetProfile -Mode 'SHAREPOINTONLINE').TargetMode | Should -BeExactly 'SharePointOnline'
    }

    It 'refuses a value that is not one of the two modes instead of running as the default' -ForEach @(
        @{ Value = 'OnPrem' }
        @{ Value = 'SharePointOnPrem ' }
        @{ Value = ' SharePointOnline' }
        @{ Value = 'SharePoint Online' }
        @{ Value = '' }
        @{ Value = 5 }
        @{ Value = $true }
        @{ Value = $null }
        @{ Value = @('SharePointOnPrem') }
        @{ Value = @{ Mode = 'SharePointOnPrem' } }
    ) {
        { Get-TargetProfile -Mode $Value } | Should -Throw "TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'."
    }

    It 'gives every category a page slug made of lowercase letters, digits and hyphens, distinct in each mode' {
        foreach ($mode in 'SharePointOnline', 'SharePointOnPrem') {
            $profile = Get-TargetProfile -Mode $mode
            $slugs = @(1..4 | ForEach-Object { $profile.CategorySlug[$_] })

            foreach ($slug in $slugs) {
                $slug | Should -Match '^[a-z0-9]+(-[a-z0-9]+)*$'
            }
            @($slugs | Select-Object -Unique) | Should -HaveCount 4
        }
    }

    It 'keeps the page slugs of the default mode as they always were, so that the names of the pages do not change' {
        $profile = Get-TargetProfile -Mode 'SharePointOnline'

        @(1..4 | ForEach-Object { $profile.CategorySlug[$_] }) | Should -Be @('simple', 'moderate', 'complex', 'blocking')
    }

    It 'turns the names of the on-premises categories into slugs without parentheses or spaces' {
        $profile = Get-TargetProfile -Mode 'SharePointOnPrem'

        @(1..4 | ForEach-Object { $profile.CategorySlug[$_] }) | Should -Be @('modern-ready', 'light-remediation', 'rebuild-spfx', 'blocked')
    }

    It 'plans one default wave per category, in both modes, and every category is in exactly one wave' {
        foreach ($mode in 'SharePointOnline', 'SharePointOnPrem') {
            $waves = @((Get-TargetProfile -Mode $mode).MigrationWave)

            $waves | Should -HaveCount 4
            @($waves | ForEach-Object { $_.Wave }) | Should -Be @(1, 2, 3, 4)
            @($waves | ForEach-Object { $_.Categories } | Sort-Object) | Should -Be @(1, 2, 3, 4)
            foreach ($wave in $waves) {
                $wave.Name | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'keeps the default waves of the SharePointOnline mode as the orchestrator always planned them' {
        $waves = @((Get-TargetProfile -Mode 'SharePointOnline').MigrationWave)

        @($waves | ForEach-Object { $_.Name }) | Should -Be @('Quick wins', 'Light remediation', 'Rebuild', 'Projects / blockers')
    }

    It 'words the waves of the on-premises mode as modernization, not as a migration' {
        $waves = @((Get-TargetProfile -Mode 'SharePointOnPrem').MigrationWave)

        @($waves | ForEach-Object { $_.Name }) | Should -Be @('Ready', 'Light remediation', 'Rebuild (SPFx)', 'Blocked')
    }

    It 'is made only of ASCII, so that a slug and a name survive any encoding of the report files' {
        foreach ($mode in 'SharePointOnline', 'SharePointOnPrem') {
            $profile = Get-TargetProfile -Mode $mode
            $text = (@(1..4 | ForEach-Object { $profile.CategoryName[$_]; $profile.CategorySlug[$_] }) + $profile.DisplayName) -join ''

            $text | Should -Match '^[\x20-\x7E]+$'
        }
    }
}
