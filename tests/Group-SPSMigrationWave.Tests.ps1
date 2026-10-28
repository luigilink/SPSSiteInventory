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

    It 'keeps failed assessments in the Not assessed wave' {
        $failed = [PSCustomObject]@{
            Url = 'https://s/failed'; AssessmentStatus = 'Failed'
            Category = $null; CategoryName = 'Not assessed'
        }

        $result = Group-SPSMigrationWave -InputObject @($failed) -MigrationWaves $script:DefaultWaves

        $result.Wave | Should -Be 0
        $result.WaveName | Should -Be 'Not assessed'
    }

    It 'puts a Simple site whose assessment is partial in Wave 0 / Needs review, and leaves its category and score alone' {
        $partial = [PSCustomObject]@{
            Url = 'https://s/partial'; AssessmentStatus = 'Partial'; CategoryName = 'Simple'; Category = 1; Score = 0.5
        }

        $result = Group-SPSMigrationWave -InputObject @($partial) -MigrationWaves $script:DefaultWaves

        $result.Wave | Should -Be 0
        $result.WaveName | Should -Be 'Needs review'
        $result.Category | Should -Be 1
        $result.CategoryName | Should -Be 'Simple'
        $result.Score | Should -Be 0.5
        $result.AssessmentStatus | Should -Be 'Partial'
    }

    It 'keeps a Simple site that was read in full in the wave of its category' {
        foreach ($status in @('Complete', $null)) {
            $site = [PSCustomObject]@{ Url = 'https://s/full'; AssessmentStatus = $status; CategoryName = 'Simple'; Category = 1; Score = 0 }

            $result = Group-SPSMigrationWave -InputObject @($site) -MigrationWaves $script:DefaultWaves

            $result.Wave | Should -Be 1
            $result.WaveName | Should -Be 'Quick wins'
        }
    }

    It 'keeps a partial site of another category in the wave of its category' {
        $partials = foreach ($category in 2..4) {
            [PSCustomObject]@{ Url = "https://s/partial$category"; AssessmentStatus = 'Partial'; CategoryName = 'x'; Category = $category; Score = $category }
        }

        $result = Group-SPSMigrationWave -InputObject @($partials) -MigrationWaves $script:DefaultWaves

        @($result | ForEach-Object { $_.Wave }) | Should -Be @(2, 3, 4)
        @($result | ForEach-Object { $_.WaveName }) | Should -Be @('Light remediation', 'Rebuild', 'Projects / blockers')
    }

    It 'does not depend on how the waves are mapped: a partial Simple site is never in the wave of the Simple category' {
        $partialSimple = [PSCustomObject]@{ Url = 'https://s/ps'; AssessmentStatus = 'Partial'; CategoryName = 'Simple'; Category = 1; Score = 0 }
        $partialModerate = [PSCustomObject]@{ Url = 'https://s/pm'; AssessmentStatus = 'Partial'; CategoryName = 'Moderate'; Category = 2; Score = 2 }
        $grouped = @(
            @{ Wave = 1; Name = 'Migrate now'; Categories = @(1, 2, 3) }
            @{ Wave = 2; Name = 'Projects'; Categories = @(4) }
        )
        $withoutSimple = @(
            @{ Wave = 2; Name = 'Light remediation'; Categories = @(2) }
        )

        $inGroupedWave = Group-SPSMigrationWave -InputObject @($partialSimple, $partialModerate) -MigrationWaves $grouped
        $inGroupedWave[0].WaveName | Should -Be 'Needs review'
        $inGroupedWave[0].Wave | Should -Be 0
        $inGroupedWave[1].WaveName | Should -Be 'Migrate now'

        # Needs review is what it is called even when no wave takes the Simple category.
        $unmapped = Group-SPSMigrationWave -InputObject @($partialSimple) -MigrationWaves $withoutSimple
        $unmapped.WaveName | Should -Be 'Needs review'
    }

    It 'leaves a failed assessment in Not assessed, and reassigns a partial site when it is read in full on a later run' {
        $failed = [PSCustomObject]@{ Url = 'https://s/failed'; AssessmentStatus = 'Failed'; Category = 1; CategoryName = 'Simple' }
        $partial = [PSCustomObject]@{ Url = 'https://s/partial'; AssessmentStatus = 'Partial'; Category = 1; CategoryName = 'Simple' }

        $first = Group-SPSMigrationWave -InputObject @($failed, $partial) -MigrationWaves $script:DefaultWaves
        $first[0].WaveName | Should -Be 'Not assessed'
        $first[1].WaveName | Should -Be 'Needs review'

        $first[1].AssessmentStatus = 'Complete'
        $second = Group-SPSMigrationWave -InputObject @($first[1]) -MigrationWaves $script:DefaultWaves
        $second.WaveName | Should -Be 'Quick wins'
        @($second.PSObject.Properties.Name | Where-Object { $_ -eq 'Wave' }).Count | Should -Be 1
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
