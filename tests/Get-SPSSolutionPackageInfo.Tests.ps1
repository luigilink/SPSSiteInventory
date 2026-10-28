# Behavior tests for Get-SPSSolutionPackageInfo (inspects WSP files and expanded packages, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spsinfo-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force

    # The expanded package that the real cabinets and the mocked expansions stand for.
    $script:Folder = Join-Path -Path $script:Dir -ChildPath 'Contoso.Intranet'
    New-TestPackageFolder -Path $script:Folder

    # The stub of the expansion runs in the scope of the module: it reads the folder to return from a global variable.
    function Set-StubFolder {
        param ([System.String] $Path)
        $global:SPSStubFolder = $Path
    }

    $script:NewFolder = {
        param ([System.String] $Name = '')
        if (-not $Name) {
            $Name = 'pkg-' + [guid]::NewGuid().ToString('N')
        }
        $path = Join-Path -Path $script:Dir -ChildPath $Name
        New-TestPackageFolder -Path $path
        return $path
    }
}

AfterAll {
    Remove-Variable -Name SPSStubFolder -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-SPSSolutionPackageInfo' {
    Context 'an expanded package' {
        BeforeAll {
            $script:Info = @(Get-SPSSolutionPackageInfo -Path $script:Folder)
        }

        It 'returns one record for the package' {
            $script:Info | Should -HaveCount 1
            $script:Info[0].PackageName | Should -Be 'Contoso.Intranet'
            $script:Info[0].Source | Should -Be 'Folder'
            $script:Info[0].Status | Should -Be 'Inspected'
            $script:Info[0].Detail | Should -BeNullOrEmpty
        }

        It 'reads what the manifest says' {
            $info = $script:Info[0]

            $info.SolutionId | Should -Be '6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'
            $info.DeploymentServerType | Should -Be 'WebFrontEnd'
            $info.ContainsGlobalAssembly | Should -BeTrue
            $info.ContainsWebApplicationAssembly | Should -BeTrue
            $info.ContainsCasPolicy | Should -BeTrue
            $info.SafeControlCount | Should -Be 2
            $info.TemplateFileCount | Should -Be 2
        }

        It 'classifies the package on its assemblies' {
            $info = $script:Info[0]

            $info.IsCustom | Should -BeTrue
            $info.IsCustomSource | Should -Be 'Assembly'
            $info.IsFullTrustCode | Should -BeTrue
            $info.AssemblyCount | Should -Be 3
            $info.CustomAssemblyCount | Should -Be 2
            $info.UnsignedAssemblyCount | Should -Be 0
            $info.LegacyFrameworkAssemblyCount | Should -Be 1
            $info.TargetFrameworks | Should -Contain '.NETFramework,Version=v3.5'
        }

        It 'reports the features even though the package is not deployed anywhere' {
            $info = $script:Info[0]

            $info.FeatureCount | Should -Be 2
            $info.FeatureIds | Should -Be @('a1b2c3d4-0000-4000-8000-000000000001', 'a1b2c3d4-0000-4000-8000-000000000002')
            $info.FeatureScopes | Should -Be @('Site', 'Web')
            $info.FeatureReceiverCount | Should -Be 1
            $info.ElementSummary | Should -Be 'ContentType=1; Field=2; Module=1; Receiver=1'
        }

        It 'leaves the fields about the farm empty when no farm map is given' {
            $info = $script:Info[0]

            $info.InFarm | Should -BeNullOrEmpty
            $info.FarmMatch | Should -BeNullOrEmpty
            $info.Difference | Should -HaveCount 0
        }
    }

    Context 'the classification as custom or Microsoft' {
        It 'judges on the assemblies, not on the name of the package' {
            $path = & $script:NewFolder 'microsoft.sharepoint.fake'

            $info = @(Get-SPSSolutionPackageInfo -Path $path)[0]

            $info.IsCustom | Should -BeTrue
            $info.IsCustomSource | Should -Be 'Assembly'
        }

        It 'does not call a package custom when all its assemblies are signed by Microsoft' {
            $path = & $script:NewFolder
            [System.IO.File]::Delete((Join-Path $path 'Contoso.Fixture.Custom.dll'))
            [System.IO.File]::Delete((Join-Path $path 'Contoso.Fixture.Legacy.dll'))
            $manifest = Join-Path -Path $path -ChildPath 'manifest.xml'
            $text = [System.IO.File]::ReadAllText($manifest)
            $text = $text -replace '(?s)<Assembly Location="Contoso.Fixture.Custom.dll".*?</Assembly>', '' -replace '<Assembly Location="Contoso.Fixture.Legacy.dll"[^>]*/>', ''
            Write-TestFile -Path $manifest -Text $text

            $info = @(Get-SPSSolutionPackageInfo -Path $path)[0]

            $info.AssemblyCount | Should -Be 1
            $info.IsCustom | Should -BeFalse
            $info.IsFullTrustCode | Should -BeFalse
            $info.IsCustomSource | Should -Be 'Assembly'
        }

        It 'takes a token that is added as Microsoft' {
            $info = @(Get-SPSSolutionPackageInfo -Path $script:Folder -KnownMicrosoftPublicKeyToken '30ad4fe6b2a6aeed')[0]

            $info.IsCustom | Should -BeFalse
            $info.CustomAssemblyCount | Should -Be 0
        }

        It 'falls back to the name of the package when it has no assembly' {
            $custom = Join-Path -Path $script:Dir -ChildPath 'contoso.declarative'
            Write-TestFile -Path (Join-Path $custom 'manifest.xml') -Text '<Solution xmlns="http://schemas.microsoft.com/sharepoint/" SolutionId="{11111111-1111-1111-1111-111111111111}" />'
            $microsoft = Join-Path -Path $script:Dir -ChildPath 'microsoft.sharepoint.declarative'
            Write-TestFile -Path (Join-Path $microsoft 'manifest.xml') -Text '<Solution xmlns="http://schemas.microsoft.com/sharepoint/" />'

            $first = @(Get-SPSSolutionPackageInfo -Path $custom)[0]
            $second = @(Get-SPSSolutionPackageInfo -Path $microsoft)[0]

            $first.IsCustom | Should -BeTrue
            $first.IsCustomSource | Should -Be 'Name'
            $first.IsFullTrustCode | Should -BeFalse
            $second.IsCustom | Should -BeFalse
            $second.IsCustomSource | Should -Be 'Name'
        }
    }

    Context 'a package with something missing' {
        It 'returns Partial, with the reason, and still reads the rest' {
            $path = & $script:NewFolder
            Remove-Item -LiteralPath (Join-Path (Join-Path $path 'FeatureFields') 'Feature.xml')

            $info = @(Get-SPSSolutionPackageInfo -Path $path)[0]

            $info.Status | Should -Be 'Partial'
            $info.Detail | Should -Match 'is not in the package'
            $info.AssemblyCount | Should -Be 3
            $info.FeatureCount | Should -Be 2
        }

        It 'returns Failed, with the reason, when there is no manifest' {
            $path = Join-Path -Path $script:Dir -ChildPath 'no-manifest'
            $null = New-Item -Path $path -ItemType Directory -Force
            Write-TestFile -Path (Join-Path $path 'a.wsp') -Text 'not a cabinet'

            $info = @(Get-SPSSolutionPackageInfo -Path $path)

            $info | Should -HaveCount 1
            $info[0].Status | Should -Be 'Failed'
            $info[0].Detail | Should -Match 'cabinet'
            $info[0].IsCustom | Should -BeNullOrEmpty
            $info[0].FeatureCount | Should -Be 0
        }

        It 'returns Failed for a path that does not exist, and goes on with the others' {
            $info = @(Get-SPSSolutionPackageInfo -Path @((Join-Path $script:Dir 'nothing-here'), $script:Folder))

            $info | Should -HaveCount 2
            $info[0].Status | Should -Be 'Failed'
            $info[0].Detail | Should -Be 'The path does not exist.'
            $info[1].Status | Should -Be 'Inspected'
        }

        It 'returns Failed for a folder that has nothing to inspect' {
            $path = Join-Path -Path $script:Dir -ChildPath 'empty-folder'
            $null = New-Item -Path $path -ItemType Directory -Force

            $info = @(Get-SPSSolutionPackageInfo -Path $path)

            $info | Should -HaveCount 1
            $info[0].Status | Should -Be 'Failed'
            $info[0].Detail | Should -Match 'no manifest.xml and no .wsp or .cab file'
        }
    }

    Context 'WSP files, with the expansion stubbed' {
        BeforeAll {
            $script:Search = Join-Path -Path $script:Dir -ChildPath 'search'
            foreach ($relative in @('b.wsp', 'a.WSP', 'old.cab', 'readme.txt', 'sub\c.wsp', 'sub\deeper\d.wsp')) {
                Write-TestFile -Path (Join-Path $script:Search $relative) -Text 'a cabinet, for the stub'
            }
            $script:Expanded = $script:Folder
        }

        BeforeEach {
            Set-StubFolder $script:Expanded
            Mock -ModuleName SPSSiteInventory.Common Expand-SPSSolutionPackage -MockWith {
                $null = New-Item -Path $WorkFolder -ItemType Directory -Force
                [PSCustomObject]@{ Path = $global:SPSStubFolder; FileCount = 9; DeclaredBytes = 1 }
            }
        }

        It 'finds the .wsp and .cab files of a folder, sorted, without the subfolders' {
            $info = @(Get-SPSSolutionPackageInfo -Path $script:Search -TemporaryFolder $script:Dir)

            @($info | ForEach-Object { $_.PackageName }) | Should -Be @('a.WSP', 'b.wsp', 'old.cab')
            @($info | Where-Object { $_.Source -ne 'Cabinet' }) | Should -HaveCount 0
        }

        It 'finds the files of the subfolders with -Recurse' {
            $info = @(Get-SPSSolutionPackageInfo -Path $script:Search -Recurse -TemporaryFolder $script:Dir)

            @($info | ForEach-Object { $_.PackageName }) | Should -Be @('a.WSP', 'b.wsp', 'old.cab', 'c.wsp', 'd.wsp')
        }

        It 'reads the size and the SHA-256 of the file, and the content of the expansion' {
            $path = Join-Path -Path $script:Search -ChildPath 'b.wsp'

            $info = @(Get-SPSSolutionPackageInfo -Path $path -TemporaryFolder $script:Dir)[0]

            $info.PackageName | Should -Be 'b.wsp'
            $info.PackageSizeBytes | Should -Be (Get-Item -LiteralPath $path).Length
            $info.Sha256 | Should -Be (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            $info.Status | Should -Be 'Inspected'
            $info.FeatureCount | Should -Be 2
        }

        It 'accepts the files from the pipeline' {
            $info = @(Get-ChildItem -LiteralPath $script:Search -Filter '*.wsp' | Get-SPSSolutionPackageInfo -TemporaryFolder $script:Dir)

            @($info | ForEach-Object { $_.PackageName }) | Should -Be @('a.WSP', 'b.wsp')
        }

        It 'accepts a wildcard' {
            $info = @(Get-SPSSolutionPackageInfo -Path (Join-Path $script:Search '*.wsp') -TemporaryFolder $script:Dir)

            @($info | ForEach-Object { $_.PackageName }) | Should -Be @('a.WSP', 'b.wsp')
        }

        It 'removes the temporary folder after each package' {
            $work = Join-Path -Path $script:Dir -ChildPath 'work-root'

            $null = Get-SPSSolutionPackageInfo -Path $script:Search -TemporaryFolder $work

            @(Get-ChildItem -LiteralPath $work -Force -ErrorAction SilentlyContinue) | Should -HaveCount 0
        }

        It 'removes the temporary folder when the inspection fails, and goes on with the next package' {
            $work = Join-Path -Path $script:Dir -ChildPath 'work-fail'
            Mock -ModuleName SPSSiteInventory.Common Expand-SPSSolutionPackage -MockWith {
                $null = New-Item -Path $WorkFolder -ItemType Directory -Force
                if ($Path -like '*a.WSP') {
                    throw 'The package lists a file name that is not safe to extract.'
                }
                [PSCustomObject]@{ Path = $global:SPSStubFolder; FileCount = 9; DeclaredBytes = 1 }
            }

            $info = @(Get-SPSSolutionPackageInfo -Path $script:Search -TemporaryFolder $work)

            $info[0].Status | Should -Be 'Failed'
            $info[0].Detail | Should -Be 'The package lists a file name that is not safe to extract.'
            $info[1].Status | Should -Be 'Inspected'
            @(Get-ChildItem -LiteralPath $work -Force -ErrorAction SilentlyContinue) | Should -HaveCount 0
        }

        It 'does not remove the folder of an expanded package' {
            $null = Get-SPSSolutionPackageInfo -Path $script:Folder

            Test-Path -LiteralPath (Join-Path $script:Folder 'manifest.xml') | Should -BeTrue
            Should -Invoke -CommandName Expand-SPSSolutionPackage -ModuleName SPSSiteInventory.Common -Times 0 -Exactly
        }
    }

    Context 'the comparison with the farm' {
        BeforeAll {
            $script:Farm = @(
                [PSCustomObject]@{ SolutionName = 'contoso.intranet.wsp'; SolutionId = '6F1A8B40-3C2D-4E5F-9A7B-1C2D3E4F5A6B'; Deployed = $true; DeploymentState = 'GlobalDeployed'; IsCustom = $true; ContainsGlobalAssembly = $true; ContainsCasPolicy = $true; FeatureCount = 0 }
                [PSCustomObject]@{ SolutionName = 'other.wsp'; SolutionId = '99999999-9999-9999-9999-999999999999'; Deployed = $false; DeploymentState = 'NotDeployed'; IsCustom = $true; ContainsGlobalAssembly = $false; ContainsCasPolicy = $false; FeatureCount = 1 }
            )
        }

        It 'matches the farm solution by solution id and lists the differences' {
            $info = @(Get-SPSSolutionPackageInfo -Path $script:Folder -FarmSolutionMap $script:Farm)[0]

            $info.InFarm | Should -BeTrue
            $info.FarmMatch | Should -Be 'SolutionId'
            $info.FarmSolutionName | Should -Be 'contoso.intranet.wsp'
            $info.FarmDeployed | Should -BeTrue
            $info.FarmDeploymentState | Should -Be 'GlobalDeployed'
            $info.FarmFeatureCount | Should -Be 0
            $info.Difference | Should -HaveCount 1
            $info.Difference[0] | Should -Be 'The farm lists 0 feature(s), the package ships 2.'
        }

        It 'lists a difference of classification, of the global assembly and of the policy' {
            $farm = @([PSCustomObject]@{ SolutionName = 'contoso.intranet.wsp'; SolutionId = '6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'; Deployed = $true; DeploymentState = 'GlobalDeployed'; IsCustom = $false; ContainsGlobalAssembly = $false; ContainsCasPolicy = $false; FeatureCount = 2 })

            $info = @(Get-SPSSolutionPackageInfo -Path $script:Folder -FarmSolutionMap $farm)[0]

            $info.Difference | Should -HaveCount 3
            ($info.Difference -join ' ') | Should -Match 'global assembly'
            ($info.Difference -join ' ') | Should -Match 'code access security'
            ($info.Difference -join ' ') | Should -Match 'custom'
        }

        It 'reports no difference when the farm and the package agree' {
            $farm = @([PSCustomObject]@{ SolutionName = 'x.wsp'; SolutionId = '6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'; Deployed = $true; DeploymentState = 'GlobalDeployed'; IsCustom = $true; ContainsGlobalAssembly = $true; ContainsCasPolicy = $true; FeatureCount = 2 })

            $info = @(Get-SPSSolutionPackageInfo -Path $script:Folder -FarmSolutionMap $farm)[0]

            $info.InFarm | Should -BeTrue
            $info.Difference | Should -HaveCount 0
        }

        It 'falls back to the file name when the solution id is not in the farm' {
            $path = Join-Path -Path $script:Dir -ChildPath 'byname'
            Write-TestFile -Path (Join-Path $path 'Contoso.Intranet.wsp') -Text 'a cabinet, for the stub'
            Set-StubFolder $script:Folder
            Mock -ModuleName SPSSiteInventory.Common Expand-SPSSolutionPackage -MockWith {
                $null = New-Item -Path $WorkFolder -ItemType Directory -Force
                [PSCustomObject]@{ Path = $global:SPSStubFolder; FileCount = 9; DeclaredBytes = 1 }
            }
            $farm = @([PSCustomObject]@{ SolutionName = 'contoso.intranet.WSP'; SolutionId = '12345678-1234-1234-1234-123456789012'; Deployed = $false; DeploymentState = 'NotDeployed'; IsCustom = $true; ContainsGlobalAssembly = $true; ContainsCasPolicy = $true; FeatureCount = 2 })

            $info = @(Get-SPSSolutionPackageInfo -Path (Join-Path $path 'Contoso.Intranet.wsp') -FarmSolutionMap $farm -TemporaryFolder $script:Dir)[0]

            $info.InFarm | Should -BeTrue
            $info.FarmMatch | Should -Be 'Name'
            $info.FarmDeployed | Should -BeFalse
            $info.Difference | Should -HaveCount 0
        }

        It 'says that the package is not in the farm' {
            $farm = @([PSCustomObject]@{ SolutionName = 'another.wsp'; SolutionId = '12345678-1234-1234-1234-123456789012'; Deployed = $true; DeploymentState = 'GlobalDeployed'; IsCustom = $true; ContainsGlobalAssembly = $false; ContainsCasPolicy = $false; FeatureCount = 0 })

            $info = @(Get-SPSSolutionPackageInfo -Path $script:Folder -FarmSolutionMap $farm)[0]

            $info.InFarm | Should -BeFalse
            $info.FarmMatch | Should -BeNullOrEmpty
            $info.FarmFeatureCount | Should -BeNullOrEmpty
        }

        It 'accepts an empty farm map' {
            $info = @(Get-SPSSolutionPackageInfo -Path $script:Folder -FarmSolutionMap @())[0]

            $info.InFarm | Should -BeNullOrEmpty
        }
    }

    Context 'a real cabinet' {
        It 'inspects a WSP that a real tool built, and leaves nothing behind' {
            $source = & $script:NewFolder
            $wsp = Join-Path -Path $script:Dir -ChildPath 'Contoso.Intranet.wsp'
            if (-not (New-TestCabinet -SourceFolder $source -Path $wsp)) {
                Set-ItResult -Skipped -Because 'no tool to build a cabinet (makecab or gcab) is available'
                return
            }
            $work = Join-Path -Path $script:Dir -ChildPath 'work-real'

            $info = @(Get-SPSSolutionPackageInfo -Path $wsp -TemporaryFolder $work)

            $info | Should -HaveCount 1
            $info[0].Status | Should -Be 'Inspected'
            $info[0].Source | Should -Be 'Cabinet'
            $info[0].SolutionId | Should -Be '6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'
            $info[0].AssemblyCount | Should -Be 3
            $info[0].CustomAssemblyCount | Should -Be 2
            $info[0].LegacyFrameworkAssemblyCount | Should -Be 1
            $info[0].FeatureCount | Should -Be 2
            $info[0].FeatureIds | Should -Be @('a1b2c3d4-0000-4000-8000-000000000001', 'a1b2c3d4-0000-4000-8000-000000000002')
            $info[0].FileCount | Should -Be 9
            $info[0].Sha256 | Should -Be (Get-FileHash -LiteralPath $wsp -Algorithm SHA256).Hash.ToLowerInvariant()
            @(Get-ChildItem -LiteralPath $work -Force -ErrorAction SilentlyContinue) | Should -HaveCount 0
        }

        It 'refuses a WSP that lists a name that goes up, and writes nothing' {
            $wsp = Join-Path -Path $script:Dir -ChildPath 'hostile.wsp'
            [System.IO.File]::WriteAllBytes($wsp, (New-TestCabinetBytes -File @(
                        @{ Name = 'manifest.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Solution />') }
                        @{ Name = '..\..\evil.txt'; Content = [System.Byte[]](1) }
                    )))
            $work = Join-Path -Path $script:Dir -ChildPath 'work-hostile'

            $info = @(Get-SPSSolutionPackageInfo -Path $wsp -TemporaryFolder $work)

            $info[0].Status | Should -Be 'Failed'
            $info[0].Detail | Should -Match 'not safe to extract'
            Test-Path -LiteralPath $work | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:Dir 'evil.txt') | Should -BeFalse
        }
    }
}
