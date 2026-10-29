# Behavior tests for Expand-SPSSolutionPackage and Read-SPSPackageXml (a package is checked before it is expanded, and its XML is read safely).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spsexp-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force

    $script:Expand = {
        param ([System.String] $Path, [System.String] $Work, [System.Collections.IDictionary] $Option = @{})
        & $script:Module { param ($p, $w, $o) Expand-SPSSolutionPackage -Path $p -WorkFolder $w @o } $Path $Work $Option
    }
    $script:Save = {
        param ([System.Byte[]] $Byte)
        $path = Join-Path -Path $script:Dir -ChildPath ([guid]::NewGuid().ToString('N') + '.wsp')
        [System.IO.File]::WriteAllBytes($path, $Byte)
        return $path
    }
    $script:NewWork = {
        return (Join-Path -Path $script:Dir -ChildPath ('work-' + [guid]::NewGuid().ToString('N')))
    }
}

AfterAll {
    Remove-Variable -Name SPSReplacementCabinet -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Expand-SPSSolutionPackage' {
    It 'refuses a package that lists a name that goes up out of the folder, and writes nothing' {
        $path = & $script:Save (New-TestCabinetBytes -File @(
                @{ Name = 'manifest.xml'; Content = [System.Byte[]](1) }
                @{ Name = '..\..\evil.txt'; Content = [System.Byte[]](2) }
            ))
        $work = & $script:NewWork

        { & $script:Expand $path $work } | Should -Throw "*not safe to extract: '..\..\evil.txt'*"

        Test-Path -LiteralPath $work | Should -BeFalse
    }

    It 'refuses a package that lists a rooted name' {
        $path = & $script:Save (New-TestCabinetBytes -File @(@{ Name = 'C:\Windows\evil.txt'; Content = [System.Byte[]](2) }))

        { & $script:Expand $path (& $script:NewWork) } | Should -Throw '*not safe to extract*'
    }

    It 'refuses a package that lists more files than the limit' {
        $path = & $script:Save (New-TestCabinetBytes -File @(
                @{ Name = 'a.xml'; Content = [System.Byte[]](1) }
                @{ Name = 'b.xml'; Content = [System.Byte[]](1) }
                @{ Name = 'c.xml'; Content = [System.Byte[]](1) }
            ))

        { & $script:Expand $path (& $script:NewWork) @{ MaximumFileCount = 2 } } | Should -Throw '*lists 3 files, more than the limit of 2*'
    }

    It 'refuses a package whose declared size is above the limit' {
        $path = & $script:Save (New-TestCabinetBytes -File @(@{ Name = 'big.bin'; Content = [System.Byte[]](1); Size = 600MB }))

        { & $script:Expand $path (& $script:NewWork) @{ MaximumMegabyte = 512 } } | Should -Throw '*expands to 600 MB, more than the limit of 512 MB*'
    }

    Context 'the original package can change at any time' {
        # The package is a file that is not trusted, often on a share: it can be replaced between the moment it is looked at and the moment it
        # is copied. The test stands for that with a copy that holds another cabinet than the original.
        It 'checks the copy that it expands, not the original: a cabinet that is swapped for a hostile one is refused, and nothing is expanded' {
            $path = & $script:Save (New-TestCabinetBytes -File @(@{ Name = 'manifest.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Solution />') }))
            $global:SPSReplacementCabinet = New-TestCabinetBytes -File @(
                @{ Name = 'manifest.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Solution />') }
                @{ Name = '..\..\evil.txt'; Content = [System.Byte[]](2) }
            )
            Mock -ModuleName SPSSiteInventory.Common Copy-Item -MockWith { [System.IO.File]::WriteAllBytes($Destination, $global:SPSReplacementCabinet) }
            $work = & $script:NewWork

            { & $script:Expand $path $work } | Should -Throw "*not safe to extract: '..\..\evil.txt'*"

            @(Get-ChildItem -LiteralPath (Join-Path $work 'expanded') -Recurse -Force -File -ErrorAction SilentlyContinue) | Should -HaveCount 0
        }

        It 'applies the limit of the number of files to the copy' {
            $path = & $script:Save (New-TestCabinetBytes -File @(@{ Name = 'a.xml'; Content = [System.Byte[]](1) }))
            $global:SPSReplacementCabinet = New-TestCabinetBytes -File @(
                @{ Name = 'a.xml'; Content = [System.Byte[]](1) }
                @{ Name = 'b.xml'; Content = [System.Byte[]](1) }
                @{ Name = 'c.xml'; Content = [System.Byte[]](1) }
            )
            Mock -ModuleName SPSSiteInventory.Common Copy-Item -MockWith { [System.IO.File]::WriteAllBytes($Destination, $global:SPSReplacementCabinet) }

            { & $script:Expand $path (& $script:NewWork) @{ MaximumFileCount = 2 } } | Should -Throw '*lists 3 files, more than the limit of 2*'
        }

        It 'applies the limit of the declared size to the copy' {
            $path = & $script:Save (New-TestCabinetBytes -File @(@{ Name = 'a.bin'; Content = [System.Byte[]](1) }))
            $global:SPSReplacementCabinet = New-TestCabinetBytes -File @(@{ Name = 'big.bin'; Content = [System.Byte[]](1); Size = 600MB })
            Mock -ModuleName SPSSiteInventory.Common Copy-Item -MockWith { [System.IO.File]::WriteAllBytes($Destination, $global:SPSReplacementCabinet) }

            { & $script:Expand $path (& $script:NewWork) @{ MaximumMegabyte = 512 } } | Should -Throw '*expands to 600 MB, more than the limit of 512 MB*'
        }

        It 'reports the size and the SHA-256 of the copy that was read, which is the package that was read' {
            $original = New-TestCabinetBytes -File @(@{ Name = 'manifest.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Solution />') })
            $path = & $script:Save $original
            $global:SPSReplacementCabinet = New-TestCabinetBytes -File @(
                @{ Name = 'manifest.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Solution />') }
                @{ Name = 'other.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Other />') }
            )
            Mock -ModuleName SPSSiteInventory.Common Copy-Item -MockWith { [System.IO.File]::WriteAllBytes($Destination, $global:SPSReplacementCabinet) }

            try {
                $result = & $script:Expand $path (& $script:NewWork)
            }
            catch {
                if ($_.Exception.Message -match 'needs expand.exe') {
                    Set-ItResult -Skipped -Because 'no tool to expand a cabinet is available'
                    return
                }
                throw
            }

            $result.SizeBytes | Should -Be $global:SPSReplacementCabinet.Length
            $result.SizeBytes | Should -Not -Be $original.Length
            $copyHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($global:SPSReplacementCabinet)).Replace('-', '').ToLowerInvariant()
            $result.Sha256 | Should -Be $copyHash
            $result.FileCount | Should -Be 2
        }

        It 'reports the size and the SHA-256 of the package when it does not change' {
            $bytes = New-TestCabinetBytes -File @(@{ Name = 'manifest.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Solution />') })
            $path = & $script:Save $bytes

            try {
                $result = & $script:Expand $path (& $script:NewWork)
            }
            catch {
                if ($_.Exception.Message -match 'needs expand.exe') {
                    Set-ItResult -Skipped -Because 'no tool to expand a cabinet is available'
                    return
                }
                throw
            }

            $result.SizeBytes | Should -Be (Get-Item -LiteralPath $path).Length
            $result.Sha256 | Should -Be (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    It 'refuses a file that is not a cabinet' {
        $path = & $script:Save ([System.Text.Encoding]::ASCII.GetBytes('PK this is a zip archive, not a cabinet, and it is long enough to have a header'))

        { & $script:Expand $path (& $script:NewWork) } | Should -Throw '*not a cabinet*'
    }

    It 'expands a cabinet that a real tool built, with its folders, and nothing outside' {
        $source = Join-Path -Path $script:Dir -ChildPath 'source'
        New-TestPackageFolder -Path $source
        $path = Join-Path -Path $script:Dir -ChildPath 'real.wsp'
        if (-not (New-TestCabinet -SourceFolder $source -Path $path)) {
            Set-ItResult -Skipped -Because 'no tool to build a cabinet (makecab or gcab) is available'
            return
        }
        $work = & $script:NewWork

        $result = & $script:Expand $path $work

        $result.Path | Should -Be (Join-Path -Path $work -ChildPath 'expanded')
        $result.FileCount | Should -Be 9
        foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -File)) {
            $relative = $file.FullName.Substring($source.Length + 1)
            $expanded = Join-Path -Path $result.Path -ChildPath $relative
            Test-Path -LiteralPath $expanded -PathType Leaf | Should -BeTrue -Because $relative
            (Get-Item -LiteralPath $expanded).Length | Should -Be $file.Length -Because $relative
        }
        @(Get-ChildItem -LiteralPath $work -Recurse -File | Where-Object { $_.Name -ne 'package.cab' }) | Should -HaveCount 9
    }

    It 'expands a cabinet without compression' {
        $path = & $script:Save (New-TestCabinetBytes -File @(
                @{ Name = 'manifest.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Solution />') }
                @{ Name = 'FeatureA\Feature.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Feature />') }
            ))
        $work = & $script:NewWork

        try {
            $result = & $script:Expand $path $work
        }
        catch {
            if ($_.Exception.Message -match 'needs expand.exe') {
                Set-ItResult -Skipped -Because 'no tool to expand a cabinet is available'
                return
            }
            throw
        }

        $result.FileCount | Should -Be 2
        [System.IO.File]::ReadAllText((Join-Path -Path $result.Path -ChildPath 'manifest.xml')) | Should -Be '<Solution />'
        [System.IO.File]::ReadAllText((Join-Path -Path (Join-Path -Path $result.Path -ChildPath 'FeatureA') -ChildPath 'Feature.xml')) | Should -Be '<Feature />'
    }
}

Describe 'Read-SPSPackageXml' {
    BeforeAll {
        $script:Read = {
            param ([System.String] $Path, [System.Int32] $MaximumMegabyte = 20)
            & $script:Module { param ($p, $m) Read-SPSPackageXml -Path $p -MaximumMegabyte $m } $Path $MaximumMegabyte
        }
    }

    It 'returns the document, not its nodes' {
        $path = Join-Path -Path $script:Dir -ChildPath 'ok.xml'
        Write-TestFile -Path $path -Text '<Solution xmlns="http://schemas.microsoft.com/sharepoint/" SolutionId="x"><Assemblies /></Solution>'

        $document = & $script:Read $path

        $document | Should -BeOfType ([System.Xml.XmlDocument])
        $document.DocumentElement.LocalName | Should -Be 'Solution'
    }

    It 'refuses a document type declaration, so that an external entity cannot pull a file in' {
        $secret = Join-Path -Path $script:Dir -ChildPath 'secret.txt'
        Write-TestFile -Path $secret -Text 'SECRET-VALUE'
        $uri = ([System.Uri]$secret).AbsoluteUri
        $path = Join-Path -Path $script:Dir -ChildPath 'xxe.xml'
        Write-TestFile -Path $path -Text ('<?xml version="1.0"?><!DOCTYPE Solution [<!ENTITY xxe SYSTEM "{0}">]><Solution SolutionId="&xxe;" />' -f $uri)

        { & $script:Read $path } | Should -Throw '*DTD*'
    }

    It 'refuses a document that expands entities without limit' {
        $path = Join-Path -Path $script:Dir -ChildPath 'bomb.xml'
        Write-TestFile -Path $path -Text '<?xml version="1.0"?><!DOCTYPE lolz [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">]><lolz>&lol2;</lolz>'

        { & $script:Read $path } | Should -Throw '*DTD*'
    }

    It 'refuses a file that is above the size limit' {
        $path = Join-Path -Path $script:Dir -ChildPath 'large.xml'
        Write-TestFile -Path $path -Text ('<a>' + (' ' * (2MB)) + '</a>')

        { & $script:Read $path 1 } | Should -Throw '*larger than 1 MB*'
    }

    It 'throws for a document that is not well formed' {
        $path = Join-Path -Path $script:Dir -ChildPath 'broken.xml'
        Write-TestFile -Path $path -Text '<Solution><Assemblies></Solution>'

        { & $script:Read $path } | Should -Throw
    }
}
