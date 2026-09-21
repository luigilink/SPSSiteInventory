# Behavior tests for Group-SPSMigrationWave (pure wave assignment, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:DefaultWaves = @(
        @{ Wave = 1; Name = 'Quick wins'; Categories = @(1) }
        @{ Wave = 2; Name = 'Light remediation'; Categories = @(2) }
        @{ Wave = 3; Name = 'Rebuild'; Categories = @(3) }
        @{ Wave = 4; Name = 'Projects / blockers'; Categories = @(4) }
    )

    $script:Sites = @(
        [PSCustomObject]@{ Url = 'https://s/1'; CategoryName = 'Simple'; Category = 1; Score = 0 }
        [PSCustomObject]@{ Url = 'https://s/2'; CategoryName = 'Moderate'; Category = 2; Score = 2 }
        [PSCustomObject]@{ Url = 'https://s/3'; CategoryName = 'Complex'; Category = 3; Score = 7 }
        [PSCustomObject]@{ Url = 'https://s/4'; CategoryName = 'Blocking'; Category = 4; Score = 9 }
    )
}

Describe 'Group-SPSMigrationWave' {
    It 'assigns one wave per category with the default 1:1 mapping' {
        $result = Group-SPSMigrationWave -InputObject $script:Sites -MigrationWaves $script:DefaultWaves

        ($result | Where-Object { $_.Category -eq 1 }).Wave | Should -Be 1
        ($result | Where-Object { $_.Category -eq 1 }).WaveName | Should -Be 'Quick wins'
        ($result | Where-Object { $_.Category -eq 4 }).Wave | Should -Be 4
        ($result | Where-Object { $_.Category -eq 4 }).WaveName | Should -Be 'Projects / blockers'
    }

    It 'supports grouping several categories into a single wave' {
        $grouped = @(
            @{ Wave = 1; Name = 'Migrate now'; Categories = @(1, 2, 3) }
            @{ Wave = 2; Name = 'Projects'; Categories = @(4) }
        )

        $result = Group-SPSMigrationWave -InputObject $script:Sites -MigrationWaves $grouped

        @($result | Where-Object { $_.Wave -eq 1 }).Count | Should -Be 3
        ($result | Where-Object { $_.Category -eq 2 }).WaveName | Should -Be 'Migrate now'
        ($result | Where-Object { $_.Category -eq 4 }).Wave | Should -Be 2
    }

    It 'buckets an unmapped category as wave 0 / Unassigned' {
        $partial = @(
            @{ Wave = 1; Name = 'Quick wins'; Categories = @(1) }
        )

        $result = Group-SPSMigrationWave -InputObject $script:Sites -MigrationWaves $partial

        $blocking = $result | Where-Object { $_.Category -eq 4 }
        $blocking.Wave | Should -Be 0
        $blocking.WaveName | Should -Be 'Unassigned'
    }

    It 'inserts Wave and WaveName right after CategoryName, preserving other columns' {
        $result = Group-SPSMigrationWave -InputObject $script:Sites -MigrationWaves $script:DefaultWaves

        $names = @($result[0].PSObject.Properties.Name)
        $names | Should -Contain 'Wave'
        $names | Should -Contain 'WaveName'
        $catIndex = [array]::IndexOf($names, 'CategoryName')
        $names[$catIndex + 1] | Should -Be 'Wave'
        $names[$catIndex + 2] | Should -Be 'WaveName'
        # Untouched columns survive.
        $result[0].Url | Should -Be 'https://s/1'
    }

    It 'reassigns cleanly when re-run on already-waved records' {
        $firstPass = Group-SPSMigrationWave -InputObject $script:Sites -MigrationWaves $script:DefaultWaves

        # A different mapping: everything non-blocking into wave 1, blockers into wave 2.
        $grouped = @(
            @{ Wave = 1; Name = 'Migrate now'; Categories = @(1, 2, 3) }
            @{ Wave = 2; Name = 'Projects'; Categories = @(4) }
        )
        $secondPass = Group-SPSMigrationWave -InputObject $firstPass -MigrationWaves $grouped

        ($secondPass | Where-Object { $_.Category -eq 2 }).Wave | Should -Be 1
        ($secondPass | Where-Object { $_.Category -eq 2 }).WaveName | Should -Be 'Migrate now'
        ($secondPass | Where-Object { $_.Category -eq 4 }).Wave | Should -Be 2
        # No duplicate Wave column introduced by the second pass.
        @($secondPass[0].PSObject.Properties.Name | Where-Object { $_ -eq 'Wave' }).Count | Should -Be 1
    }

    It 'handles an empty inventory without error' {
        $result = Group-SPSMigrationWave -InputObject @() -MigrationWaves $script:DefaultWaves

        @($result).Count | Should -Be 0
    }
}
