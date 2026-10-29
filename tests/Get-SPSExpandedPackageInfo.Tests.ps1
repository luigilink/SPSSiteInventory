# Behavior tests for Get-SPSExpandedPackageInfo (reads the manifest, the features and the assemblies of an expanded WSP, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spspkg-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force
    # The built-in tokens, and the one of the throwaway key that signs the 'Genuine' fixture (a test cannot sign with a Microsoft key).
    $script:Token = @('71e9bce111e9429c', '31bf3856ad364e35', 'b77a5c561934e089', 'b03f5f7f11d50a3a', $script:GenuineToken)

    $script:Read = {
        param ([System.String] $Root, [System.String[]] $Token = $script:Token)
        & $script:Module { param ($r, $t) Get-SPSExpandedPackageInfo -Root $r -MicrosoftPublicKeyToken $t } $Root $Token
    }
    $script:NewPackage = {
        $path = Join-Path -Path $script:Dir -ChildPath ('p-' + [guid]::NewGuid().ToString('N'))
        New-TestPackageFolder -Path $path
        return $path
    }
}

AfterAll {
    Remove-TestLink
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-SPSExpandedPackageInfo' {
    Context 'a complete package' {
        BeforeAll {
            $script:Info = & $script:Read (& $script:NewPackage)
        }

        It 'reads the solution manifest' {
            $script:Info.SolutionId | Should -Be '6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'
            $script:Info.SharePointProductVersion | Should -Be '15.0'
            $script:Info.DeploymentServerType | Should -Be 'WebFrontEnd'
            $script:Info.ResetWebServer | Should -BeTrue
            $script:Info.TemplateFileCount | Should -Be 2
            $script:Info.RootFileCount | Should -Be 0
            $script:Info.DwpFileCount | Should -Be 0
            $script:Info.SiteDefinitionCount | Should -Be 0
            $script:Info.Problems | Should -HaveCount 0
        }

        It 'reads where the assemblies are deployed, the safe controls and the code access security policy' {
            $script:Info.ContainsGlobalAssembly | Should -BeTrue
            $script:Info.ContainsWebApplicationAssembly | Should -BeTrue
            $script:Info.ContainsWebApplicationResource | Should -BeTrue
            $script:Info.ContainsCasPolicy | Should -BeTrue
            $script:Info.SafeControlCount | Should -Be 2
        }

        It 'reads every assembly of the manifest with its strong name and its classification' {
            $assembly = @($script:Info.Assemblies)

            $assembly | Should -HaveCount 3
            $custom = $assembly | Where-Object { $_.Location -eq 'Contoso.Fixture.Custom.dll' }
            $custom.Status | Should -Be 'Read'
            $custom.DeploymentTarget | Should -Be 'GlobalAssemblyCache'
            $custom.Name | Should -Be 'Contoso.Fixture.Custom'
            $custom.PublicKeyToken | Should -Be '30ad4fe6b2a6aeed'
            $custom.IsMicrosoft | Should -BeFalse
            $custom.IsCustom | Should -BeTrue
            $custom.SafeControlCount | Should -Be 2
            $custom.BuiltForLegacyFramework | Should -BeFalse
            $legacy = $assembly | Where-Object { $_.Location -eq 'Contoso.Fixture.Legacy.dll' }
            $legacy.DeploymentTarget | Should -Be 'WebApplication'
            $legacy.BuiltForLegacyFramework | Should -BeTrue
            $microsoft = $assembly | Where-Object { $_.Location -eq 'Fixture.Signed.dll' }
            $microsoft.IsMicrosoft | Should -BeTrue
            $microsoft.IsCustom | Should -BeFalse
        }

        It 'reads the features from their own files, with the id in the same form as the farm' {
            $feature = @($script:Info.Features)

            $script:Info.FeatureCount | Should -Be 2
            $script:Info.FeatureIds | Should -Be @('a1b2c3d4-0000-4000-8000-000000000001', 'a1b2c3d4-0000-4000-8000-000000000002')
            $script:Info.FeatureScopes | Should -Be @('Site', 'Web')
            $feature[0].Title | Should -Be 'Contoso web parts'
            $feature[0].ReceiverClass | Should -Be 'Contoso.Receivers.WebPartsReceiver'
            $feature[0].Receiver | Should -Be @('Contoso.Fixture.Custom, Version=1.2.3.4, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed')
            $feature[1].ReceiverAssembly | Should -BeNullOrEmpty
            $script:Info.FeatureReceiverCount | Should -Be 1
        }

        It 'counts the elements that the features provision' {
            $script:Info.ElementSummary | Should -Be 'ContentType=1; Field=2; Module=1; Receiver=1'
        }

        It 'lists the target frameworks and the files of the package' {
            $script:Info.TargetFrameworks | Should -Be @('.NETFramework,Version=v3.5', '.NETFramework,Version=v4.5', '.NETFramework,Version=v4.8')
            $script:Info.FileCount | Should -Be 9
            $script:Info.ExpandedSizeBytes | Should -BeGreaterThan 6000
        }
    }

    Context 'the classification of an assembly' {
        It 'treats a token that is added to the list as Microsoft when the signature is valid' {
            $info = & $script:Read (& $script:NewPackage) @($script:GenuineToken.ToUpperInvariant())

            $genuine = @($info.Assemblies) | Where-Object { $_.Location -eq 'Fixture.Signed.dll' }
            $genuine.SignatureStatus | Should -Be 'Valid'
            $genuine.IsMicrosoft | Should -BeTrue
            $genuine.IsCustom | Should -BeFalse
        }

        It 'does not take a token for a proof: a key that is added to the list does not make an unsigned assembly Microsoft' {
            $info = & $script:Read (& $script:NewPackage) ($script:Token + '30AD4FE6B2A6AEED')

            $custom = @($info.Assemblies) | Where-Object { $_.Location -eq 'Contoso.Fixture.Custom.dll' }
            $custom.HasMicrosoftToken | Should -BeTrue
            $custom.SignatureStatus | Should -Be 'NotSigned'
            $custom.IsMicrosoft | Should -BeFalse
            $custom.IsCustom | Should -BeTrue
        }

        It 'counts as custom an assembly that has the public key of a Microsoft key and is not signed with it, and says so' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllBytes((Join-Path $path 'Fixture.Signed.dll'), (Get-TestAssemblyByte 'Microsoft'))

            $info = & $script:Read $path

            $spoof = @($info.Assemblies) | Where-Object { $_.Location -eq 'Fixture.Signed.dll' }
            $spoof.PublicKeyToken | Should -Be '31bf3856ad364e35'
            $spoof.HasMicrosoftToken | Should -BeTrue
            $spoof.SignatureStatus | Should -Be 'NotSigned'
            $spoof.IsMicrosoft | Should -BeFalse
            $spoof.IsCustom | Should -BeTrue
            $info.Problems | Should -HaveCount 1
            $info.Problems[0] | Should -Match "Assembly 'Fixture.Signed.dll' has the public key token of a Microsoft key \(31bf3856ad364e35\) but is not signed with it \(NotSigned\), so it counts as custom"
        }

        It 'counts as custom an assembly that was altered after it was signed, and says so' {
            $path = & $script:NewPackage
            $bytes = Get-TestAssemblyByte 'Genuine'
            $bytes[$bytes.Length - 40] = $bytes[$bytes.Length - 40] -bxor 0xFF
            [System.IO.File]::WriteAllBytes((Join-Path $path 'Fixture.Signed.dll'), $bytes)

            $info = & $script:Read $path

            $altered = @($info.Assemblies) | Where-Object { $_.Location -eq 'Fixture.Signed.dll' }
            $altered.SignatureStatus | Should -Be 'Invalid'
            $altered.IsMicrosoft | Should -BeFalse
            $altered.IsCustom | Should -BeTrue
            $info.Problems | Should -HaveCount 1
            $info.Problems[0] | Should -Match '\(Invalid\)'
        }

        It 'accepts a signature that uses SHA-256 and a longer key' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllBytes((Join-Path $path 'Fixture.Signed.dll'), (Get-TestAssemblyByte 'GenuineSha256'))

            $info = & $script:Read $path @($script:GenuineSha256Token)

            $signed = @($info.Assemblies) | Where-Object { $_.Location -eq 'Fixture.Signed.dll' }
            $signed.SignatureStatus | Should -Be 'Valid'
            $signed.IsMicrosoft | Should -BeTrue
        }

        It 'does not report a satellite assembly that has a Microsoft token and no signature' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllBytes((Join-Path $path 'Contoso.Fixture.Custom.resources.dll'), (Get-TestAssemblyByte 'Satellite'))

            $info = & $script:Read $path ($script:Token + '30ad4fe6b2a6aeed')

            $satellite = @($info.Assemblies) | Where-Object { $_.Location -eq 'Contoso.Fixture.Custom.resources.dll' }
            $satellite.IsSatellite | Should -BeTrue
            $satellite.IsCustom | Should -BeFalse
            @($info.Problems | Where-Object { $_ -like "*resources.dll*" }) | Should -HaveCount 0
        }

        It 'treats an assembly that is not signed as custom' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllBytes((Join-Path $path 'Contoso.Fixture.Unsigned.dll'), (Get-TestAssemblyByte 'Unsigned'))

            $info = & $script:Read $path

            $unsigned = @($info.Assemblies) | Where-Object { $_.Location -eq 'Contoso.Fixture.Unsigned.dll' }
            $unsigned.DeploymentTarget | Should -Be 'Other'
            $unsigned.IsSigned | Should -BeFalse
            $unsigned.IsCustom | Should -BeTrue
        }

        It 'does not count a satellite assembly' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllBytes((Join-Path $path 'Contoso.Fixture.Custom.resources.dll'), (Get-TestAssemblyByte 'Satellite'))

            $info = & $script:Read $path

            $satellite = @($info.Assemblies) | Where-Object { $_.Location -eq 'Contoso.Fixture.Custom.resources.dll' }
            $satellite.IsSatellite | Should -BeTrue
            $satellite.IsCustom | Should -BeFalse
        }

        It 'lists the DLLs that are in a folder of the package and not in the manifest, with the path of the package' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllBytes((Join-Path (Join-Path $path 'TEMPLATE') 'tool.dll'), (Get-TestAssemblyByte 'Unsigned'))

            $info = & $script:Read $path

            @($info.Assemblies | Where-Object { $_.Location -eq 'TEMPLATE\tool.dll' -and $_.DeploymentTarget -eq 'Other' }) | Should -HaveCount 1
        }

        It 'reports a genuine native DLL as such, without a problem' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllBytes((Join-Path $path 'native.dll'), (New-TestNativeDll))

            $info = & $script:Read $path

            $native = @($info.Assemblies) | Where-Object { $_.Location -eq 'native.dll' }
            $native.Status | Should -Be 'NotManaged'
            $native.IsManaged | Should -BeFalse
            $native.IsCustom | Should -BeTrue
            $info.Problems | Should -HaveCount 0
        }

        It 'reports a DLL that is not a valid image as not assessed, and counts it as custom' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllText((Join-Path $path 'broken.dll'), 'MZ this is not an assembly but has the extension of one, to be read as bytes')

            $info = & $script:Read $path

            $broken = @($info.Assemblies) | Where-Object { $_.Location -eq 'broken.dll' }
            $broken.Status | Should -Be 'Failed'
            $broken.IsCustom | Should -BeTrue
            $info.Problems | Should -HaveCount 1
            $info.Problems[0] | Should -Match "Assembly 'broken.dll':"
        }

        It 'reports a DLL that is above the size limit as not assessed, and counts it as custom' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllBytes((Join-Path $path 'big.dll'), (New-Object -TypeName System.Byte[] -ArgumentList (2MB)))

            $info = & $script:Module { param ($r, $t) Get-SPSExpandedPackageInfo -Root $r -MicrosoftPublicKeyToken $t -MaximumMegabyte 1 } $path $script:Token

            $big = @($info.Assemblies) | Where-Object { $_.Location -eq 'big.dll' }
            $big.Status | Should -Be 'Skipped'
            $big.IsCustom | Should -BeTrue
            $info.Problems | Should -HaveCount 1
            $info.Problems[0] | Should -Match "Assembly 'big.dll': The file is larger than 1 MB and was not read"
        }

        It 'reports an assembly whose name cannot be read as partial, and counts it as custom' {
            $path = & $script:NewPackage
            [System.IO.File]::WriteAllBytes((Join-Path $path 'damaged.dll'), (Get-TestDamagedMetadataByte))

            $info = & $script:Read $path

            $damaged = @($info.Assemblies) | Where-Object { $_.Location -eq 'damaged.dll' }
            $damaged.Status | Should -Be 'Partial'
            $damaged.IsManaged | Should -BeTrue
            $damaged.IsCustom | Should -BeTrue
            $info.Problems | Should -HaveCount 1
            $info.Problems[0] | Should -Match "Assembly 'damaged.dll': The assembly name could not be read"
        }

        It 'lists a hidden DLL, which is still a DLL of the package' {
            $path = & $script:NewPackage
            $hidden = Join-Path -Path (Join-Path $path 'TEMPLATE') -ChildPath '.hidden.dll'
            [System.IO.File]::WriteAllBytes($hidden, (Get-TestAssemblyByte 'Unsigned'))
            [System.IO.File]::SetAttributes($hidden, ([System.IO.File]::GetAttributes($hidden) -bor [System.IO.FileAttributes]::Hidden))

            $info = & $script:Read $path

            $found = @($info.Assemblies) | Where-Object { $_.Location -eq 'TEMPLATE\.hidden.dll' }
            @($found) | Should -HaveCount 1
            $found.Name | Should -Be 'Contoso.Fixture.Unsigned'
            $found.IsCustom | Should -BeTrue
            $info.FileCount | Should -Be 10
        }
    }

    Context 'a package with something missing or wrong' {
        It 'reports a feature manifest that is not in the package, and still reads the rest' {
            $path = & $script:NewPackage
            Remove-Item -LiteralPath (Join-Path (Join-Path $path 'FeatureFields') 'Feature.xml')

            $info = & $script:Read $path

            $info.Problems | Should -HaveCount 1
            $info.Problems[0] | Should -Match "Feature manifest 'FeatureFields.Feature.xml' is not in the package"
            $info.FeatureCount | Should -Be 2
            @($info.Features | Where-Object { $_.Status -eq 'Missing' }) | Should -HaveCount 1
            $info.FeatureIds | Should -Be @('a1b2c3d4-0000-4000-8000-000000000001')
        }

        It 'reports an assembly of the manifest that is not in the package' {
            $path = & $script:NewPackage
            Remove-Item -LiteralPath (Join-Path $path 'Contoso.Fixture.Legacy.dll')

            $info = & $script:Read $path

            $missing = @($info.Assemblies) | Where-Object { $_.Location -eq 'Contoso.Fixture.Legacy.dll' }
            $missing.Status | Should -Be 'Missing'
            $missing.IsCustom | Should -BeFalse
            $info.Problems | Should -HaveCount 1
        }

        It 'reports a feature manifest that is not valid XML' {
            $path = & $script:NewPackage
            Write-TestFile -Path (Join-Path (Join-Path $path 'FeatureFields') 'Feature.xml') -Text '<Feature Id="x"'

            $info = & $script:Read $path

            $info.Problems[0] | Should -Match "could not be read"
            @($info.Features | Where-Object { $_.Status -eq 'Unreadable' }) | Should -HaveCount 1
        }

        It 'reports an element manifest that is not in the package' {
            $path = & $script:NewPackage
            Remove-Item -LiteralPath (Join-Path (Join-Path $path 'FeatureFields') 'Elements.xml')

            $info = & $script:Read $path

            $info.Problems | Should -HaveCount 1
            $info.Problems[0] | Should -Match "Element manifest 'Elements.xml' of the feature"
        }

        It 'does not follow a location that leaves the package' {
            $path = & $script:NewPackage
            $outside = Join-Path -Path $script:Dir -ChildPath 'outside.dll'
            [System.IO.File]::WriteAllBytes($outside, (Get-TestAssemblyByte 'Unsigned'))
            $manifest = Join-Path -Path $path -ChildPath 'manifest.xml'
            $text = [System.IO.File]::ReadAllText($manifest).Replace('Location="Fixture.Signed.dll"', 'Location="..\outside.dll"').Replace('FeatureFields\Feature.xml', '..\..\outside.xml')
            Write-TestFile -Path $manifest -Text $text

            $info = & $script:Read $path

            ($info.Assemblies | Where-Object { $_.Location -eq '..\outside.dll' }).Status | Should -Be 'Outside'
            @($info.Assemblies | Where-Object { $_.Name -eq 'Contoso.Fixture.Unsigned' }) | Should -HaveCount 0
            @($info.Features | Where-Object { $_.Status -eq 'Missing' }) | Should -HaveCount 1
            $info.Problems | Should -HaveCount 2
        }

        It 'does not follow a folder that is a link to somewhere else, and reads nothing through it' {
            $path = & $script:NewPackage
            $outside = Join-Path -Path $script:Dir -ChildPath ('outside-' + [guid]::NewGuid().ToString('N'))
            Write-TestFile -Path (Join-Path $outside 'Feature.xml') -Text '<Feature xmlns="http://schemas.microsoft.com/sharepoint/" Id="{FFFFFFFF-0000-4000-8000-000000000001}" Title="Outside" Scope="Site" />'
            [System.IO.File]::WriteAllBytes((Join-Path $outside 'Outside.Fixture.dll'), (Get-TestAssemblyByte 'Unsigned'))
            Remove-Item -LiteralPath (Join-Path $path 'FeatureFields') -Recurse -Force
            if (-not (New-TestLink -Path (Join-Path $path 'FeatureFields') -Target $outside)) {
                Set-ItResult -Skipped -Because 'a link cannot be created here'
                return
            }

            $info = & $script:Read $path

            $info.FeatureIds | Should -Not -Contain 'ffffffff-0000-4000-8000-000000000001'
            @($info.Features | Where-Object { $_.Status -eq 'Missing' }) | Should -HaveCount 1
            @($info.Assemblies | Where-Object { $_.Name -eq 'Outside.Fixture' -or $_.Location -like '*Outside.Fixture.dll' }) | Should -HaveCount 0
            ($info.Problems -join ' | ') | Should -Match "Feature manifest 'FeatureFields.Feature.xml' goes through a link, which is not followed"
            ($info.Problems -join ' | ') | Should -Match 'The package has 1 link\(s\)'
        }

        It 'does not read a feature manifest that is a link to a file outside of the package' {
            $path = & $script:NewPackage
            $outside = Join-Path -Path $script:Dir -ChildPath ('outside-' + [guid]::NewGuid().ToString('N') + '.xml')
            Write-TestFile -Path $outside -Text '<Feature xmlns="http://schemas.microsoft.com/sharepoint/" Id="{FFFFFFFF-0000-4000-8000-000000000002}" Title="Outside" Scope="Site" />'
            Remove-Item -LiteralPath (Join-Path (Join-Path $path 'FeatureFields') 'Feature.xml')
            if (-not (New-TestLink -Path (Join-Path (Join-Path $path 'FeatureFields') 'Feature.xml') -Target $outside)) {
                Set-ItResult -Skipped -Because 'a link to a file cannot be created here'
                return
            }

            $info = & $script:Read $path

            $info.FeatureIds | Should -Not -Contain 'ffffffff-0000-4000-8000-000000000002'
            ($info.Problems -join ' | ') | Should -Match "Feature manifest 'FeatureFields.Feature.xml' goes through a link"
        }

        It 'does not load a DLL that is a link to a file outside of the package' {
            $path = & $script:NewPackage
            $outside = Join-Path -Path $script:Dir -ChildPath ('outside-' + [guid]::NewGuid().ToString('N') + '.dll')
            [System.IO.File]::WriteAllBytes($outside, (Get-TestAssemblyByte 'Unsigned'))
            if (-not (New-TestLink -Path (Join-Path (Join-Path $path 'TEMPLATE') 'linked.dll') -Target $outside)) {
                Set-ItResult -Skipped -Because 'a link to a file cannot be created here'
                return
            }

            $info = & $script:Read $path

            @($info.Assemblies | Where-Object { $_.Name -eq 'Contoso.Fixture.Unsigned' }) | Should -HaveCount 0
            @($info.Assemblies | Where-Object { $_.Location -like '*linked.dll' }) | Should -HaveCount 0
            $info.AssemblyCount | Should -Be $null
            ($info.Problems -join ' | ') | Should -Match 'The package has 1 link\(s\).*TEMPLATE.linked.dll'
        }

        It 'reports an assembly of the manifest that is a link, and does not count it as deployed' {
            $path = & $script:NewPackage
            $outside = Join-Path -Path $script:Dir -ChildPath ('outside-' + [guid]::NewGuid().ToString('N') + '.dll')
            [System.IO.File]::WriteAllBytes($outside, (Get-TestAssemblyByte 'Unsigned'))
            Remove-Item -LiteralPath (Join-Path $path 'Contoso.Fixture.Legacy.dll')
            if (-not (New-TestLink -Path (Join-Path $path 'Contoso.Fixture.Legacy.dll') -Target $outside)) {
                Set-ItResult -Skipped -Because 'a link to a file cannot be created here'
                return
            }

            $info = & $script:Read $path

            $linked = @($info.Assemblies) | Where-Object { $_.Location -eq 'Contoso.Fixture.Legacy.dll' }
            $linked.Status | Should -Be 'Link'
            $linked.IsCustom | Should -BeFalse
            $info.ContainsWebApplicationAssembly | Should -BeFalse
            ($info.Problems -join ' | ') | Should -Match "Assembly 'Contoso.Fixture.Legacy.dll': The location goes through a link"
        }

        It 'refuses a manifest.xml that is a link' {
            $path = & $script:NewPackage
            $outside = Join-Path -Path $script:Dir -ChildPath ('outside-' + [guid]::NewGuid().ToString('N') + '.xml')
            Write-TestFile -Path $outside -Text '<Solution xmlns="http://schemas.microsoft.com/sharepoint/" SolutionId="{99999999-9999-9999-9999-999999999999}" />'
            Remove-Item -LiteralPath (Join-Path $path 'manifest.xml')
            if (-not (New-TestLink -Path (Join-Path $path 'manifest.xml') -Target $outside)) {
                Set-ItResult -Skipped -Because 'a link to a file cannot be created here'
                return
            }

            { & $script:Read $path } | Should -Throw '*manifest.xml is a link*'
        }

        It 'does not loop on a link that points back into the package' {
            $path = & $script:NewPackage
            if (-not (New-TestLink -Path (Join-Path (Join-Path $path 'TEMPLATE') 'loop') -Target $path)) {
                Set-ItResult -Skipped -Because 'a link to a folder cannot be created here'
                return
            }

            $info = & $script:Read $path

            $info.FileCount | Should -Be 9
            ($info.Problems -join ' | ') | Should -Match 'The package has 1 link\(s\)'
        }

        It 'throws when there is no manifest.xml' {
            $path = & $script:NewPackage
            Remove-Item -LiteralPath (Join-Path $path 'manifest.xml')

            { & $script:Read $path } | Should -Throw '*no manifest.xml*'
        }

        It 'throws when the manifest is not a solution manifest' {
            $path = & $script:NewPackage
            Write-TestFile -Path (Join-Path $path 'manifest.xml') -Text '<Feature />'

            { & $script:Read $path } | Should -Throw "*not a solution manifest (its root element is 'Feature')*"
        }

        It 'throws when the manifest declares a DTD, instead of reading an external entity' {
            $path = & $script:NewPackage
            Write-TestFile -Path (Join-Path $path 'manifest.xml') -Text '<?xml version="1.0"?><!DOCTYPE Solution [<!ENTITY x SYSTEM "file:///etc/hostname">]><Solution SolutionId="&x;" />'

            { & $script:Read $path } | Should -Throw '*manifest.xml could not be read*'
        }

        It 'reads a package with no assembly and no feature' {
            $path = Join-Path -Path $script:Dir -ChildPath ('empty-' + [guid]::NewGuid().ToString('N'))
            Write-TestFile -Path (Join-Path $path 'manifest.xml') -Text '<Solution xmlns="http://schemas.microsoft.com/sharepoint/" />'

            $info = & $script:Read $path

            $info.Assemblies | Should -HaveCount 0
            $info.FeatureCount | Should -Be 0
            $info.ContainsGlobalAssembly | Should -BeFalse
            $info.SolutionId | Should -BeNullOrEmpty
            $info.Problems | Should -HaveCount 0
        }
    }
}
