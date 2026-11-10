# Tests for the solution package files of Export-SPSInventoryReport: the files, the manifest, what it returns and the HTML section.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    # Windows PowerShell 5.1 does not unroll a JSON array in a pipeline, so the rows are read with foreach.
    function Read-JsonRow {
        param ([string]$Path)
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($row in (Get-Content -Path $Path -Raw | ConvertFrom-Json)) { $rows.Add($row) }
        return $rows.ToArray()
    }

    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spsexportpkg-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force
    $script:Folder = Join-Path -Path $script:Dir -ChildPath 'Contoso.Intranet'
    New-TestPackageFolder -Path $script:Folder
    $script:Map = @(
        [PSCustomObject]@{ SolutionName = 'Contoso.Intranet'; SolutionId = '6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'; Deployed = $true; DeploymentState = 'GlobalDeployed'; IsCustom = $true; ContainsGlobalAssembly = $true; ContainsCasPolicy = $false; ContainsWebApplicationResource = $false; IsFullTrustCode = $true; FeatureCount = 1; FeatureScopes = @(); FeatureIds = @() }
        [PSCustomObject]@{ SolutionName = 'Contoso.Other'; SolutionId = '99999999-0000-4000-8000-000000000009'; Deployed = $true; DeploymentState = 'GlobalDeployed'; IsCustom = $true; ContainsGlobalAssembly = $false; ContainsCasPolicy = $false; ContainsWebApplicationResource = $false; IsFullTrustCode = $false; FeatureCount = 0; FeatureScopes = @(); FeatureIds = @() }
    )
    # One package that was read, and one that was not (a path that does not exist).
    $script:Read = @(Get-SPSSolutionPackageInfo -Path $script:Folder -FarmSolutionMap $script:Map -KnownMicrosoftPublicKeyToken $script:GenuineToken)
    $script:Failed = @(Get-SPSSolutionPackageInfo -Path (Join-Path $script:Dir 'missing.wsp'))
    $script:Site = [PSCustomObject]@{
        InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/team'; Title = 'Team'; WebApp = 'Intranet'
        AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Export-SPSInventoryReport solution packages' {
    It 'writes the three package files in the output folder, with the base name, and returns their paths' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -SolutionPackages @($script:Read + $script:Failed) -OutputFolder (Join-Path $TestDrive 'a') -BaseName 'Pkg'

        foreach ($path in @($output.SolutionPackagesCsvPath, $output.SolutionAssembliesCsvPath, $output.SolutionPackagesJsonPath)) {
            $path | Should -Exist
            (Split-Path -Path $path -Parent) | Should -Be (Join-Path $TestDrive 'a')
        }
        (Split-Path -Path $output.SolutionPackagesCsvPath -Leaf) | Should -Match '^Pkg-solution-packages-\d{8}-\d{4}\.csv$'
        (Split-Path -Path $output.SolutionAssembliesCsvPath -Leaf) | Should -Match '^Pkg-solution-assemblies-\d{8}-\d{4}\.csv$'
        (Split-Path -Path $output.SolutionPackagesJsonPath -Leaf) | Should -Match '^Pkg-solution-packages-\d{8}-\d{4}\.json$'
    }

    It 'gives the package files the time stamp of the other files of the run, so that a change of minute cannot split them' {
        Mock -ModuleName SPSSiteInventory.Common Export-SPSSolutionPackageReport {
            [PSCustomObject]@{ PackageCsvPath = (Join-Path $OutputFolder 'p.csv'); AssemblyCsvPath = (Join-Path $OutputFolder 'a.csv'); JsonPath = (Join-Path $OutputFolder 'p.json') }
        }

        $output = Export-SPSInventoryReport -InputObject @($script:Site) -SolutionPackages @($script:Read) -OutputFolder (Join-Path $TestDrive 'stamp') -BaseName 'Stamp'
        $script:RunStamp = (Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json).Timestamp

        $script:RunStamp | Should -Match '^\d{8}-\d{4}$'
        Should -Invoke Export-SPSSolutionPackageReport -ModuleName SPSSiteInventory.Common -Times 1 -Exactly -ParameterFilter { $Timestamp -eq $script:RunStamp -and $BaseName -eq 'Stamp' }
    }

    It 'writes one row per package, and one per assembly of the packages' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -SolutionPackages @($script:Read + $script:Failed) -OutputFolder (Join-Path $TestDrive 'b') -BaseName 'Rows'

        $packageRow = @(Import-Csv -Path $output.SolutionPackagesCsvPath)
        $packageRow | Should -HaveCount 2
        @($packageRow | ForEach-Object { $_.PackageName }) | Should -Be @('Contoso.Intranet', 'missing.wsp')
        @(Import-Csv -Path $output.SolutionAssembliesCsvPath) | Should -HaveCount 3
        $json = @(Read-JsonRow -Path $output.SolutionPackagesJsonPath)
        $json | Should -HaveCount 2
        $json[0].Features | Should -Not -BeNullOrEmpty
    }

    It 'lists the files in the manifest, and counts the packages and the ones that are not read in full' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -SolutionPackages @($script:Read + $script:Failed) -OutputFolder (Join-Path $TestDrive 'c') -BaseName 'Manifest'

        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json

        $manifest.Files.SolutionPackagesCsv | Should -Be $output.SolutionPackagesCsvPath
        $manifest.Files.SolutionAssembliesCsv | Should -Be $output.SolutionAssembliesCsvPath
        $manifest.Files.SolutionPackagesJson | Should -Be $output.SolutionPackagesJsonPath
        $manifest.Summary.SolutionPackageCount | Should -Be 2
        $manifest.Summary.SolutionPackageIssueCount | Should -Be 1
        $manifest.ReportPackVersion | Should -Be '1.0'
    }

    It 'counts a package that is read in part among the ones that are not read in full' {
        $partial = $script:Read[0].PSObject.Copy()
        $partial.Status = 'Partial'

        $output = Export-SPSInventoryReport -InputObject @($script:Site) -SolutionPackages @($script:Read[0], $partial, $script:Failed[0]) -OutputFolder (Join-Path $TestDrive 'd') -BaseName 'Partial'

        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Summary.SolutionPackageCount | Should -Be 3
        $manifest.Summary.SolutionPackageIssueCount | Should -Be 2
    }

    It 'adds the Solution packages section to the HTML report, and names the farm solutions that no package matches' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -SolutionMap $script:Map -SolutionPackages @($script:Read + $script:Failed) -OutputFolder (Join-Path $TestDrive 'e') -BaseName 'Html'

        $html = Get-Content -Path $output.HtmlPath -Raw

        $html | Should -Match '<h2 id="solution-packages">Solution packages \(WSP files\)</h2>'
        $html | Should -Match '<a href="#solution-packages">Solution packages</a>'
        $html | Should -Match '<strong>2</strong> package\(s\) &middot; <strong>1</strong> custom &middot; <strong>1</strong> full-trust code &middot; <strong>1</strong> not read in full'
        $html | Should -Match '<strong>1</strong> farm solution\(s\) have no inspected package: Contoso\.Other\.'
    }

    It 'adds nothing, and leaves the manifest values null, when no package is given' -ForEach @(
        @{ Case = 'the parameter is left out'; Packages = $null }
        @{ Case = 'an empty list'; Packages = @() }
        @{ Case = 'a list that has only a null'; Packages = @($null) }
    ) {
        $folder = Join-Path $TestDrive ('none-' + [guid]::NewGuid().ToString('N'))
        $output = if ($null -eq $Packages) {
            Export-SPSInventoryReport -InputObject @($script:Site) -OutputFolder $folder -BaseName 'None'
        }
        else {
            Export-SPSInventoryReport -InputObject @($script:Site) -SolutionPackages $Packages -OutputFolder $folder -BaseName 'None'
        }

        $output.SolutionPackagesCsvPath | Should -BeNullOrEmpty -Because $Case
        $output.SolutionAssembliesCsvPath | Should -BeNullOrEmpty
        $output.SolutionPackagesJsonPath | Should -BeNullOrEmpty
        @(Get-ChildItem -Path $folder -Filter '*solution-*') | Should -HaveCount 0
        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Summary.SolutionPackageCount | Should -BeNullOrEmpty
        $manifest.Summary.SolutionPackageIssueCount | Should -BeNullOrEmpty
        $manifest.Files.SolutionPackagesCsv | Should -BeNullOrEmpty
        $manifest.Files.SolutionAssembliesCsv | Should -BeNullOrEmpty
        $manifest.Files.SolutionPackagesJson | Should -BeNullOrEmpty
        $manifest.Files.PSObject.Properties.Name | Should -Contain 'SolutionPackagesJson' -Because 'the manifest keeps the same keys'
        $manifest.Summary.PSObject.Properties.Name | Should -Contain 'SolutionPackageCount' -Because 'the manifest keeps the same keys'
        (Get-Content -Path $output.HtmlPath -Raw) | Should -Not -Match 'solution-packages'
    }

    It 'leaves the farm-solution report of the manifest as it is' {
        $solutionJson = Join-Path $TestDrive 'solutions.json'

        $output = Export-SPSInventoryReport -InputObject @($script:Site) -SolutionMap $script:Map -SolutionJsonPath $solutionJson -SolutionPackages @($script:Read) -OutputFolder (Join-Path $TestDrive 'f') -BaseName 'Both'

        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Files.SolutionsJson | Should -Be $solutionJson
        $html = Get-Content -Path $output.HtmlPath -Raw
        $html | Should -Match 'id="farm-solutions"'
        $html | Should -Match 'id="solution-packages"'
    }
}
