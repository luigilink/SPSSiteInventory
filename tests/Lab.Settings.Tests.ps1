BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    Import-Module -Name (Join-Path $repoRoot 'tools/lab/SPSInventoryLab.psm1') -Force
    $script:ExamplePath = Join-Path $repoRoot 'src/config/inventory-settings.example.psd1'
    $script:Example = Get-SPSInventorySetting -Path $script:ExamplePath

    function New-LabSettings {
        param
        (
            [System.String] $Name = 'lab.psd1',
            [System.String] $Example = $script:ExamplePath,
            [System.String] $ReportFolder = (Join-Path -Path $TestDrive -ChildPath 'Reports')
        )

        $out = Join-Path -Path $TestDrive -ChildPath $Name
        $null = New-SPSLabSettings -ExamplePath $Example -OutputPath $out -WebApplicationUrl 'https://lab.contoso.local' -ReportFolder $ReportFolder
        return $out
    }
}

Describe 'New-SPSLabSettings' {
    It 'writes settings that the toolkit loads, for the lab web application and report folder' {
        $path = New-LabSettings

        $settings = Get-SPSInventorySetting -Path $path

        $settings.EnvName | Should -Be 'LAB'
        @($settings.WebApplicationUrl) | Should -Be @('https://lab.contoso.local')
        $settings.OutputFolder | Should -Be (Join-Path -Path $TestDrive -ChildPath 'Reports')
    }

    It 'lowers the large-content thresholds to the lab values' {
        $settings = Get-SPSInventorySetting -Path (New-LabSettings)

        foreach ($threshold in (Get-SPSLabThreshold).GetEnumerator()) {
            $settings.LargeContentThresholds[$threshold.Key] | Should -Be $threshold.Value -Because $threshold.Key
        }
        $settings.LargeContentThresholds.LargeSiteSizeGB | Should -Be $script:Example.LargeContentThresholds.LargeSiteSizeGB
        $settings.LargeContentThresholds.MaxItemsForVersionScanPerLibrary | Should -Be $script:Example.LargeContentThresholds.MaxItemsForVersionScanPerLibrary
    }

    It 'changes the thresholds only, not the weights that share their names' {
        $settings = Get-SPSInventorySetting -Path (New-LabSettings)

        $settings.Scoring.Weights.CheckedOutFileCount | Should -Be $script:Example.Scoring.Weights.CheckedOutFileCount
        $settings.Scoring.Weights.FileVersionCount | Should -Be $script:Example.Scoring.Weights.FileVersionCount
    }

    It 'keeps the rest of the example, so that the lab exercises its real scoring' {
        $settings = Get-SPSInventorySetting -Path (New-LabSettings)

        (ConvertTo-Json -InputObject $settings.Scoring -Depth 6) | Should -Be (ConvertTo-Json -InputObject $script:Example.Scoring -Depth 6)
        (ConvertTo-Json -InputObject $settings.TemplateParity -Depth 6) | Should -Be (ConvertTo-Json -InputObject $script:Example.TemplateParity -Depth 6)
        (ConvertTo-Json -InputObject $settings.MigrationWaves -Depth 6) | Should -Be (ConvertTo-Json -InputObject $script:Example.MigrationWaves -Depth 6)
    }

    It 'writes a header that says what the file is, with a byte order mark' {
        $path = New-LabSettings
        $bytes = [System.IO.File]::ReadAllBytes($path)

        ($bytes[0], $bytes[1], $bytes[2]) | Should -Be @(0xEF, 0xBB, 0xBF)
        [System.IO.File]::ReadAllText($path) | Should -Match 'SPSSiteInventory lab settings, generated from the example'
    }

    It 'keeps quotes and dollar signs of the paths literal' {
        $folder = Join-Path -Path $TestDrive -ChildPath "O'Brien `$1 `${x}"
        $path = New-LabSettings -Name 'quotes.psd1' -ReportFolder $folder

        (Get-SPSInventorySetting -Path $path).OutputFolder | Should -Be $folder
    }

    It 'creates the folder of the settings file' {
        $out = Join-Path -Path $TestDrive -ChildPath 'new\folder\lab.psd1'

        $null = New-SPSLabSettings -ExamplePath $script:ExamplePath -OutputPath $out -WebApplicationUrl 'https://lab' -ReportFolder 'C:\Reports'

        Test-Path -LiteralPath $out | Should -BeTrue
    }

    It 'writes nothing with -WhatIf' {
        $out = Join-Path -Path $TestDrive -ChildPath 'whatif.psd1'

        $null = New-SPSLabSettings -ExamplePath $script:ExamplePath -OutputPath $out -WebApplicationUrl 'https://lab' -ReportFolder 'C:\Reports' -WhatIf

        Test-Path -LiteralPath $out | Should -BeFalse
    }

    It 'fails, naming the setting, when the example no longer has one that the lab changes' {
        foreach ($setting in @('EnvName', 'WebApplicationUrl', 'OutputFolder')) {
            $text = [System.IO.File]::ReadAllText($script:ExamplePath)
            $broken = Join-Path -Path $TestDrive -ChildPath "no-$setting.psd1"
            [System.IO.File]::WriteAllText($broken, ($text -replace "(?m)^(\s*)$setting(\s*=)", '$1Renamed$2'))

            { New-LabSettings -Name "out-$setting.psd1" -Example $broken } | Should -Throw "*'$setting' setting*"
        }
    }

    It 'fails, naming the threshold, when the example no longer has one that the lab lowers' {
        $text = [System.IO.File]::ReadAllText($script:ExamplePath)
        $broken = Join-Path -Path $TestDrive -ChildPath 'no-threshold.psd1'
        [System.IO.File]::WriteAllText($broken, ($text -replace '(?m)^(\s*)FileVersionCount(\s*=\s*50)', '$1RenamedCount$2'))

        { New-LabSettings -Name 'out-threshold.psd1' -Example $broken } | Should -Throw "*LargeContentThresholds.FileVersionCount*"
    }

    It 'fails when the LargeContentThresholds section is gone' {
        $text = [System.IO.File]::ReadAllText($script:ExamplePath)
        $broken = Join-Path -Path $TestDrive -ChildPath 'no-section.psd1'
        [System.IO.File]::WriteAllText($broken, ($text -replace 'LargeContentThresholds(\s*=)', 'Renamed$1'))

        { New-LabSettings -Name 'out-section.psd1' -Example $broken } | Should -Throw "*LargeContentThresholds*"
    }

    It 'fails when the example does not exist' {
        { New-LabSettings -Example (Join-Path -Path $TestDrive -ChildPath 'nope.psd1') } | Should -Throw '*does not exist*'
    }
}
