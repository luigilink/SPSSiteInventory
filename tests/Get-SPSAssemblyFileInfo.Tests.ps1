# Behavior tests for Get-SPSAssemblyFileInfo (reads an assembly file as bytes, never loads it).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spsasm-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force

    $script:Info = {
        param ([System.String] $Path, [System.Int32] $MaximumMegabyte = 256)
        & $script:Module { param ($p, $m) Get-SPSAssemblyFileInfo -Path $p -MaximumMegabyte $m } $Path $MaximumMegabyte
    }
    $script:Save = {
        param ([System.String] $Name, [System.Byte[]] $Byte)
        $path = Join-Path -Path $script:Dir -ChildPath $Name
        [System.IO.File]::WriteAllBytes($path, $Byte)
        return $path
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-SPSAssemblyFileInfo' {
    It 'reads the strong name, the runtime and the target framework of an assembly signed with a custom key' {
        $info = & $script:Info (& $script:Save 'custom.dll' (Get-TestAssemblyByte 'Custom'))

        $info.IsManaged | Should -BeTrue
        $info.Name | Should -Be 'Contoso.Fixture.Custom'
        $info.Version | Should -Be '1.2.3.4'
        $info.Culture | Should -BeNullOrEmpty
        $info.PublicKeyToken | Should -Be '30ad4fe6b2a6aeed'
        $info.IsSigned | Should -BeTrue
        $info.RuntimeVersion | Should -Be 'v4.0.30319'
        $info.TargetFramework | Should -Be '.NETFramework,Version=v4.8'
        $info.Architecture | Should -Be 'AnyCPU'
        $info.Detail | Should -BeNullOrEmpty
    }

    It 'reads the runtime of an assembly built for .NET 3.5' {
        $info = & $script:Info (& $script:Save 'legacy.dll' (Get-TestAssemblyByte 'Legacy'))

        $info.RuntimeVersion | Should -Be 'v2.0.50727'
        $info.TargetFramework | Should -Be '.NETFramework,Version=v3.5'
        $info.PublicKeyToken | Should -Be '30ad4fe6b2a6aeed'
    }

    It 'reads an assembly that is not signed as having no token' {
        $info = & $script:Info (& $script:Save 'unsigned.dll' (Get-TestAssemblyByte 'Unsigned'))

        $info.Name | Should -Be 'Contoso.Fixture.Unsigned'
        $info.PublicKeyToken | Should -BeNullOrEmpty
        $info.IsSigned | Should -BeFalse
        $info.TargetFramework | Should -Be '.NETFramework,Version=v4.5.2'
    }

    It 'reads the token that Microsoft signs with' {
        $info = & $script:Info (& $script:Save 'microsoft.dll' (Get-TestAssemblyByte 'Microsoft'))

        $info.Name | Should -Be 'Fixture.Signed'
        $info.PublicKeyToken | Should -Be '31bf3856ad364e35'
    }

    It 'reads the culture of a satellite assembly' {
        $info = & $script:Info (& $script:Save 'satellite.dll' (Get-TestAssemblyByte 'Satellite'))

        $info.Culture | Should -Be 'fr-FR'
        $info.TargetFramework | Should -BeNullOrEmpty
    }

    It 'reads an assembly of the runtime that is running the tests' {
        $path = [System.Management.Automation.PSObject].Assembly.Location

        $info = & $script:Info $path

        $info.IsManaged | Should -BeTrue
        $info.Name | Should -Be 'System.Management.Automation'
        $info.PublicKeyToken | Should -Be '31bf3856ad364e35'
        $info.RuntimeVersion | Should -Match '^v4\.0\.'
    }

    It 'does not load the assembly in the session' {
        $before = @([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Contoso.Fixture.Custom' })

        $null = & $script:Info (& $script:Save 'custom2.dll' (Get-TestAssemblyByte 'Custom'))

        $before | Should -HaveCount 0
        @([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Contoso.Fixture.Custom' }) | Should -HaveCount 0
    }

    It 'says that a file that is not an executable image is not an assembly, without throwing' {
        $info = & $script:Info (& $script:Save 'text.dll' ([System.Text.Encoding]::ASCII.GetBytes('This is a text file with a dll extension and enough bytes to have a header.')))

        $info.IsManaged | Should -BeFalse
        $info.Detail | Should -Match 'not a Windows executable'
    }

    It 'says that a native DLL has no .NET header' {
        $bytes = New-Object -TypeName System.Byte[] -ArgumentList 400
        $bytes[0] = 0x4D
        $bytes[1] = 0x5A
        [System.BitConverter]::GetBytes([System.Int32]64).CopyTo($bytes, 0x3C)
        $bytes[64] = 0x50
        $bytes[65] = 0x45
        [System.BitConverter]::GetBytes([System.UInt16]0x14C).CopyTo($bytes, 68)
        [System.BitConverter]::GetBytes([System.UInt16]224).CopyTo($bytes, 84)
        [System.BitConverter]::GetBytes([System.UInt16]0x10B).CopyTo($bytes, 88)
        [System.BitConverter]::GetBytes([System.UInt32]16).CopyTo($bytes, 180)

        $info = & $script:Info (& $script:Save 'native.dll' $bytes)

        $info.IsManaged | Should -BeFalse
        $info.Detail | Should -Match 'native DLL'
    }

    It 'does not throw for a truncated assembly' {
        $bytes = Get-TestAssemblyByte 'Custom'
        $cut = [System.Byte[]]$bytes[0..150]

        $info = & $script:Info (& $script:Save 'cut.dll' $cut)

        $info.IsManaged | Should -BeFalse
        $info.Detail | Should -Not -BeNullOrEmpty
    }

    It 'does not read a file that is above the size limit' {
        $path = & $script:Save 'big.dll' (New-Object -TypeName System.Byte[] -ArgumentList (2MB))

        $info = & $script:Info $path 1

        $info.IsManaged | Should -BeFalse
        $info.Detail | Should -Match 'larger than 1 MB'
    }
}
