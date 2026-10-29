# Behavior tests for Export-SPSSolutionPackageReport (filesystem I/O, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    $script:Work = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spspkgexp-' + [guid]::NewGuid().ToString('N'))
    $script:Source = Join-Path -Path $script:Work -ChildPath 'Contoso.Intranet'
    New-TestPackageFolder -Path $script:Source
    $script:Package = @(Get-SPSSolutionPackageInfo -Path $script:Source -KnownMicrosoftPublicKeyToken $script:GenuineToken)
}

AfterAll {
    if (Test-Path -LiteralPath $script:Work) {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Export-SPSSolutionPackageReport' {
    BeforeEach {
        $script:OutDir = Join-Path -Path $script:Work -ChildPath ('out-' + [guid]::NewGuid().ToString('N'))
    }

    It 'writes two CSV files and a JSON file, creating the folder' {
        $result = Export-SPSSolutionPackageReport -InputObject $script:Package -OutputFolder $script:OutDir -BaseName 'SPSSiteInventory-PROD'

        Test-Path -LiteralPath $result.PackageCsvPath | Should -BeTrue
        Test-Path -LiteralPath $result.AssemblyCsvPath | Should -BeTrue
        Test-Path -LiteralPath $result.JsonPath | Should -BeTrue
        $result.PackageCsvPath | Should -Match 'SPSSiteInventory-PROD-solution-packages-\d{8}-\d{4}\.csv$'
        $result.AssemblyCsvPath | Should -Match 'SPSSiteInventory-PROD-solution-assemblies-\d{8}-\d{4}\.csv$'
        $result.JsonPath | Should -Match 'SPSSiteInventory-PROD-solution-packages-\d{8}-\d{4}\.json$'
    }

    It 'writes one row per package, with the arrays flattened' {
        $result = Export-SPSSolutionPackageReport -InputObject $script:Package -OutputFolder $script:OutDir

        $row = @(Import-Csv -LiteralPath $result.PackageCsvPath)

        $row | Should -HaveCount 1
        $row[0].PackageName | Should -Be 'Contoso.Intranet'
        $row[0].Status | Should -Be 'Inspected'
        $row[0].SolutionId | Should -Be '6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'
        $row[0].IsCustom | Should -Be 'True'
        $row[0].FeatureCount | Should -Be '2'
        $row[0].FeatureScopes | Should -Be 'Site; Web'
        $row[0].FeatureIds | Should -Be 'a1b2c3d4-0000-4000-8000-000000000001; a1b2c3d4-0000-4000-8000-000000000002'
        $row[0].ElementSummary | Should -Be 'ContentType=1; Field=2; Module=1; Receiver=1'
        $row[0].LegacyFrameworkAssemblyCount | Should -Be '1'
        $row[0].PSObject.Properties.Name | Should -Not -Contain 'Assemblies'
        $row[0].PSObject.Properties.Name | Should -Not -Contain 'Features'
    }

    It 'writes one row per assembly, tied to its package' {
        $result = Export-SPSSolutionPackageReport -InputObject $script:Package -OutputFolder $script:OutDir

        $row = @(Import-Csv -LiteralPath $result.AssemblyCsvPath)

        $row | Should -HaveCount 3
        @($row | ForEach-Object { $_.PackageName } | Select-Object -Unique) | Should -Be @('Contoso.Intranet')
        $custom = $row | Where-Object { $_.Location -eq 'Contoso.Fixture.Custom.dll' }
        $custom.PublicKeyToken | Should -Be '30ad4fe6b2a6aeed'
        $custom.IsCustom | Should -Be 'True'
        $custom.DeploymentTarget | Should -Be 'GlobalAssemblyCache'
        $custom.TargetFramework | Should -Be '.NETFramework,Version=v4.8'
        $genuine = $row | Where-Object { $_.Location -eq 'Fixture.Signed.dll' }
        $genuine.IsMicrosoft | Should -Be 'True'
        $genuine.HasMicrosoftToken | Should -Be 'True'
        $genuine.SignatureStatus | Should -Be 'Valid'
        $custom.SignatureStatus | Should -Be 'NotSigned'
        $custom.HasMicrosoftToken | Should -Be 'False'
    }

    It 'keeps the full structure in the JSON file' {
        $result = Export-SPSSolutionPackageReport -InputObject $script:Package -OutputFolder $script:OutDir

        $json = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json

        @($json) | Should -HaveCount 1
        @($json[0].Assemblies) | Should -HaveCount 3
        @($json[0].Features) | Should -HaveCount 2
        @($json[0].FeatureIds) | Should -HaveCount 2
        $json[0].IsCustom | Should -BeTrue
    }

    It 'accepts the records from the pipeline' {
        $result = $script:Package | Export-SPSSolutionPackageReport -OutputFolder $script:OutDir

        @(Import-Csv -LiteralPath $result.PackageCsvPath) | Should -HaveCount 1
    }

    It 'neutralizes a cell that a spreadsheet would read as a formula' {
        $hostile = $script:Package[0].PSObject.Copy()
        $hostile.PackageName = '=HYPERLINK("http://example.invalid","x")'
        $hostile.Assemblies = @($script:Package[0].Assemblies | ForEach-Object {
                $copy = $_.PSObject.Copy()
                $copy.Name = '@SUM(1+1)'
                $copy
            })

        $result = Export-SPSSolutionPackageReport -InputObject @($hostile) -OutputFolder $script:OutDir

        @(Import-Csv -LiteralPath $result.PackageCsvPath)[0].PackageName | Should -Be '''=HYPERLINK("http://example.invalid","x")'
        @(Import-Csv -LiteralPath $result.AssemblyCsvPath)[0].Name | Should -Be '''@SUM(1+1)'
        (Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json)[0].PackageName | Should -Be '=HYPERLINK("http://example.invalid","x")'
    }

    It 'writes the row of a package that failed, with the reason' {
        $failed = @(Get-SPSSolutionPackageInfo -Path (Join-Path $script:Work 'nothing-here'))

        $result = Export-SPSSolutionPackageReport -InputObject $failed -OutputFolder $script:OutDir

        $row = @(Import-Csv -LiteralPath $result.PackageCsvPath)
        $row[0].Status | Should -Be 'Failed'
        $row[0].Detail | Should -Be 'The path does not exist.'
    }

    It 'handles an empty list without error' {
        $result = Export-SPSSolutionPackageReport -InputObject @() -OutputFolder $script:OutDir

        Test-Path -LiteralPath $result.PackageCsvPath | Should -BeTrue
        Test-Path -LiteralPath $result.JsonPath | Should -BeTrue
    }
}
