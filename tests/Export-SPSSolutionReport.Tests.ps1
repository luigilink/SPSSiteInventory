# Behavior tests for Export-SPSSolutionReport (filesystem I/O, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:Map = @(
        [PSCustomObject]@{
            SolutionName                   = 'contoso.portal.wsp'
            SolutionId                     = '11111111-1111-1111-1111-111111111111'
            Deployed                       = $true
            DeploymentState                = 'GlobalDeployed'
            IsCustom                       = $true
            ContainsGlobalAssembly         = $true
            ContainsCasPolicy              = $false
            ContainsWebApplicationResource = $true
            IsFullTrustCode                = $true
            DeployedWebApplicationCount    = 2
            DeployedServerCount            = 3
            FeatureCount                   = 2
            FeatureScopes                  = @('Site', 'Web')
            FeatureIds                     = @('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002')
        },
        [PSCustomObject]@{
            SolutionName                   = 'microsoft.sharepoint.wsp'
            SolutionId                     = '22222222-2222-2222-2222-222222222222'
            Deployed                       = $true
            DeploymentState                = 'GlobalDeployed'
            IsCustom                       = $false
            ContainsGlobalAssembly         = $false
            ContainsCasPolicy              = $false
            ContainsWebApplicationResource = $false
            IsFullTrustCode                = $false
            DeployedWebApplicationCount    = 0
            DeployedServerCount            = 1
            FeatureCount                   = 0
            FeatureScopes                  = @()
            FeatureIds                     = @()
        }
    )
}

Describe 'Export-SPSSolutionReport' {
    BeforeEach {
        $script:OutDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spssol-' + [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        if (Test-Path -Path $script:OutDir) {
            Remove-Item -Path $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes a CSV and a JSON file, creating the folder' {
        $result = Export-SPSSolutionReport -InputObject $script:Map -OutputFolder $script:OutDir -BaseName 'SPSSiteInventory-PROD'

        Test-Path -Path $result.CsvPath | Should -BeTrue
        Test-Path -Path $result.JsonPath | Should -BeTrue
        $result.CsvPath | Should -Match 'SPSSiteInventory-PROD-solutions-\d{8}-\d{4}\.csv$'
        $result.JsonPath | Should -Match 'SPSSiteInventory-PROD-solutions-\d{8}-\d{4}\.json$'
    }

    It 'flattens array-valued columns in the CSV' {
        $result = Export-SPSSolutionReport -InputObject $script:Map -OutputFolder $script:OutDir
        $rows = Import-Csv -Path $result.CsvPath

        $custom = $rows | Where-Object { $_.SolutionName -eq 'contoso.portal.wsp' }
        $custom.IsFullTrustCode | Should -Be 'True'
        $custom.FeatureScopes | Should -Be 'Site; Web'
        $custom.FeatureIds | Should -Match 'aaaaaaaa-0000-0000-0000-000000000001; aaaaaaaa-0000-0000-0000-000000000002'
        # No unexpanded object placeholder.
        $custom.FeatureIds | Should -Not -Match 'System.Object'
    }

    It 'keeps the arrays intact in the JSON' {
        $result = Export-SPSSolutionReport -InputObject $script:Map -OutputFolder $script:OutDir
        $json = Get-Content -Path $result.JsonPath -Raw | ConvertFrom-Json

        $custom = $json | Where-Object { $_.SolutionName -eq 'contoso.portal.wsp' }
        @($custom.FeatureIds).Count | Should -Be 2
        $custom.ContainsGlobalAssembly | Should -BeTrue
    }

    It 'handles an empty map without error' {
        $result = Export-SPSSolutionReport -InputObject @() -OutputFolder $script:OutDir

        Test-Path -Path $result.CsvPath | Should -BeTrue
        Test-Path -Path $result.JsonPath | Should -BeTrue
    }
}
