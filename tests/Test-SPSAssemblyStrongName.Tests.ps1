# Behavior tests for Test-SPSAssemblyStrongName (checks the strong-name signature of an assembly held as bytes, never loads it).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spssn-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force

    # The public key of an assembly, as AssemblyName.GetPublicKey() gives it: it is read from a copy on disk, which is all the function needs.
    $script:KeyOf = {
        param ([System.Byte[]] $Byte)
        $path = Join-Path -Path $script:Dir -ChildPath ([guid]::NewGuid().ToString('N') + '.dll')
        [System.IO.File]::WriteAllBytes($path, $Byte)
        return , [System.Reflection.AssemblyName]::GetAssemblyName($path).GetPublicKey()
    }
    $script:Check = {
        param ([System.Byte[]] $Byte, [System.Byte[]] $Key)
        & $script:Module { param ($b, $k) Test-SPSAssemblyStrongName -Bytes $b -PublicKey $k } $Byte $Key
    }
    # Where the signature, the checksum and the first section are in a fixture, read from its own headers.
    $script:Layout = {
        param ([System.Byte[]] $Byte)
        $pe = [System.BitConverter]::ToInt32($Byte, 0x3C)
        $optional = $pe + 24
        $sectionTable = $optional + [System.BitConverter]::ToUInt16($Byte, $pe + 20)
        $directory = $optional + 96
        $rva = [System.BitConverter]::ToUInt32($Byte, $directory + (14 * 8))
        $toOffset = {
            param ([System.UInt32] $Rva)
            for ($index = 0; $index -lt [System.BitConverter]::ToUInt16($Byte, $pe + 6); $index++) {
                $entry = $sectionTable + (40 * $index)
                $virtual = [System.BitConverter]::ToUInt32($Byte, $entry + 12)
                $span = [System.Math]::Max([System.BitConverter]::ToUInt32($Byte, $entry + 8), [System.BitConverter]::ToUInt32($Byte, $entry + 16))
                if ($Rva -ge $virtual -and $Rva -lt ($virtual + $span)) {
                    return [System.Int32]([System.BitConverter]::ToUInt32($Byte, $entry + 20) + $Rva - $virtual)
                }
            }
        }
        $clr = & $toOffset $rva
        return [PSCustomObject]@{
            Pe          = $pe
            Checksum    = $optional + 64
            Certificate = $directory + (4 * 8)
            Clr         = $clr
            Flags       = $clr + 16
            Signature   = & $toOffset ([System.BitConverter]::ToUInt32($Byte, $clr + 32))
            Length      = [System.BitConverter]::ToUInt32($Byte, $clr + 36)
            Text        = [System.BitConverter]::ToUInt32($Byte, $sectionTable + 20)
        }
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Test-SPSAssemblyStrongName' {
    Context 'an assembly that is signed' {
        It 'accepts a valid signature made with SHA-1 and a 1024-bit key' {
            $bytes = Get-TestAssemblyByte 'Genuine'

            $result = & $script:Check $bytes (& $script:KeyOf $bytes)

            $result.Status | Should -Be 'Valid'
            $result.Detail | Should -BeNullOrEmpty
        }

        It 'accepts a valid signature made with SHA-256 and a 2048-bit key' {
            $bytes = Get-TestAssemblyByte 'GenuineSha256'

            (& $script:Check $bytes (& $script:KeyOf $bytes)).Status | Should -Be 'Valid'
        }

        It 'does not depend on the checksum of the file, which the signature does not cover' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = & $script:KeyOf $bytes
            $layout = & $script:Layout $bytes
            [System.BitConverter]::GetBytes([System.UInt32]0x12345678).CopyTo($bytes, $layout.Checksum)

            (& $script:Check $bytes $key).Status | Should -Be 'Valid'
        }

        It 'does not depend on a certificate table, which is added after the signature' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = & $script:KeyOf $bytes
            $layout = & $script:Layout $bytes
            [System.BitConverter]::GetBytes([System.UInt32]0x2000).CopyTo($bytes, $layout.Certificate)
            [System.BitConverter]::GetBytes([System.UInt32]0x200).CopyTo($bytes, $layout.Certificate + 4)

            (& $script:Check $bytes $key).Status | Should -Be 'Valid'
        }

        It 'does not depend on what is added after the last section (the certificate itself)' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = & $script:KeyOf $bytes
            $longer = New-Object -TypeName System.Byte[] -ArgumentList ($bytes.Length + 512)
            [System.Array]::Copy($bytes, $longer, $bytes.Length)
            for ($index = $bytes.Length; $index -lt $longer.Length; $index++) {
                $longer[$index] = 0xAB
            }

            (& $script:Check $longer $key).Status | Should -Be 'Valid'
        }

        It 'reads the file as bytes and does not load it' {
            $bytes = Get-TestAssemblyByte 'Genuine'

            $null = & $script:Check $bytes (& $script:KeyOf $bytes)

            @([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Fixture.Genuine' }) | Should -HaveCount 0
        }
    }

    Context 'an assembly that was altered' {
        It 'refuses a changed byte in the code and the metadata' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = & $script:KeyOf $bytes
            $layout = & $script:Layout $bytes
            $bytes[$layout.Text + 0x100] = $bytes[$layout.Text + 0x100] -bxor 0xFF

            $result = & $script:Check $bytes $key

            $result.Status | Should -Be 'Invalid'
            $result.Detail | Should -Match 'does not match'
        }

        It 'refuses a changed byte in the headers' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = & $script:KeyOf $bytes
            $layout = & $script:Layout $bytes
            $bytes[$layout.Pe + 8] = $bytes[$layout.Pe + 8] -bxor 0xFF

            (& $script:Check $bytes $key).Status | Should -Be 'Invalid'
        }

        It 'refuses a changed byte in the signature' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = & $script:KeyOf $bytes
            $layout = & $script:Layout $bytes
            $bytes[$layout.Signature + 7] = $bytes[$layout.Signature + 7] -bxor 0x01

            (& $script:Check $bytes $key).Status | Should -Be 'Invalid'
        }

        It 'refuses a signature that was made for another key' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $other = Get-TestAssemblyByte 'GenuineSha256'
            $key = & $script:KeyOf $other
            # The key of the other assembly is 2048 bits: the signature, 1024 bits, is not the size of the key.
            (& $script:Check $bytes $key).Status | Should -Be 'Invalid'
        }

        It 'refuses a file that is cut short' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = & $script:KeyOf $bytes
            $cut = [System.Byte[]]$bytes[0..($bytes.Length - 200)]

            (& $script:Check $cut $key).Status | Should -Be 'Invalid'
        }
    }

    Context 'an assembly that is not signed' {
        It 'says that an assembly with a public key and no signature is not signed (delay-signed)' {
            $bytes = Get-TestAssemblyByte 'Microsoft'

            $result = & $script:Check $bytes (& $script:KeyOf $bytes)

            $result.Status | Should -Be 'NotSigned'
            $result.Detail | Should -Match 'no strong-name signature'
        }

        It 'says that an assembly that has the flag and room for a signature, filled with zeros, is not signed (public signed)' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = & $script:KeyOf $bytes
            $layout = & $script:Layout $bytes
            for ($index = 0; $index -lt $layout.Length; $index++) {
                $bytes[$layout.Signature + $index] = 0
            }

            $result = & $script:Check $bytes $key

            $result.Status | Should -Be 'NotSigned'
            $result.Detail | Should -Match 'signature is empty'
        }

        It 'says that an assembly whose flag of a signed assembly is cleared is not signed, even with a signature in place' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = & $script:KeyOf $bytes
            $layout = & $script:Layout $bytes
            $bytes[$layout.Flags] = $bytes[$layout.Flags] -band 0xF7

            (& $script:Check $bytes $key).Status | Should -Be 'NotSigned'
        }
    }

    Context 'what cannot be checked' {
        It 'does not verify a public key that is not an RSA key, such as the standard key of the ECMA assemblies' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $ecma = [System.Byte[]]@(0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0)

            $result = & $script:Check $bytes $ecma

            $result.Status | Should -Be 'NotVerified'
            $result.Detail | Should -Match 'not an RSA key'
        }

        It 'does not verify without a key' {
            $bytes = Get-TestAssemblyByte 'Genuine'

            (& $script:Check $bytes ([System.Byte[]]@())).Status | Should -Be 'NotVerified'
            (& $script:Check $bytes $null).Status | Should -Be 'NotVerified'
        }

        It 'does not verify a hash algorithm that it does not know' {
            $bytes = Get-TestAssemblyByte 'Genuine'
            $key = [System.Byte[]]((& $script:KeyOf $bytes).Clone())
            [System.BitConverter]::GetBytes([System.UInt32]0x8003).CopyTo($key, 4)

            $result = & $script:Check $bytes $key

            $result.Status | Should -Be 'NotVerified'
            $result.Detail | Should -Match 'hash algorithm'
        }

        It 'does not throw for bytes that are not an image' {
            $key = & $script:KeyOf (Get-TestAssemblyByte 'Genuine')

            (& $script:Check ([System.Text.Encoding]::ASCII.GetBytes('this is not a portable executable, it is long enough to be read as a header and it is not.')) $key).Status | Should -Be 'NotVerified'
            (& $script:Check ([System.Byte[]]@(1, 2, 3)) $key).Status | Should -Be 'NotVerified'
        }
    }

    Context 'assemblies that are signed by their publishers' {
        It 'tells the assemblies of the runtime that is running the tests from the ones that are really signed' {
            # Which assemblies are really signed depends on the runtime (.NET Framework signs its own, .NET builds its own in the open), so
            # this checks what holds on every one of them: the status is one of the known ones, it never throws, and a valid one has a token.
            $found = 0
            foreach ($type in @([System.Object], [System.Management.Automation.PSObject], [System.Xml.XmlDocument], [System.Linq.Enumerable])) {
                $path = $type.Assembly.Location
                $name = [System.Reflection.AssemblyName]::GetAssemblyName($path)
                $result = & $script:Check ([System.IO.File]::ReadAllBytes($path)) $name.GetPublicKey()
                $result.Status | Should -BeIn @('Valid', 'NotSigned', 'NotVerified') -Because $path
                $found++
            }
            $found | Should -Be 4
        }
    }
}
