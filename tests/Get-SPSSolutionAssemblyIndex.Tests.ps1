# Behavior tests for Get-SPSSolutionAssemblyIndex (the assemblies of the inspected packages, by name).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function New-Pkg {
        param ([string]$Name, [string]$Farm = '', [object[]]$Assembly = @())
        [PSCustomObject]@{ PackageName = $Name; FarmSolutionName = $Farm; Assemblies = $Assembly }
    }

    function New-Asm {
        param ([string]$Name, [string]$Token = '30ad4fe6b2a6aeed', [string]$Version = '1.0.0.0', $IsSatellite = $false, $IsManaged = $true)
        [PSCustomObject]@{ Name = $Name; PublicKeyToken = $Token; Version = $Version; IsSatellite = $IsSatellite; IsManaged = $IsManaged }
    }

    function Get-Index {
        param ($Package)
        & $script:Module { param ($Value) Get-SPSSolutionAssemblyIndex -SolutionPackages $Value } $Package
    }
}

Describe 'Get-SPSSolutionAssemblyIndex' {
    It 'keys the assemblies of the packages by their name, in lower case' {
        $index = Get-Index @((New-Pkg -Name 'Contoso.wsp' -Assembly @((New-Asm 'Contoso.Intranet'), (New-Asm 'Contoso.Web.Parts'))))

        @($index.Keys | Sort-Object) | Should -BeExactly @('contoso.intranet', 'contoso.web.parts')
    }

    It 'keeps the package, the farm solution, the public key token in lower case and the version of each assembly' {
        $index = Get-Index @((New-Pkg -Name 'Contoso.wsp' -Farm 'contoso.wsp' -Assembly @((New-Asm 'Contoso.Intranet' -Token '30AD4FE6B2A6AEED' -Version '2.1.0.0'))))

        $entry = @($index['contoso.intranet'])
        $entry | Should -HaveCount 1
        $entry[0].PackageName | Should -Be 'Contoso.wsp'
        $entry[0].FarmSolutionName | Should -Be 'contoso.wsp'
        $entry[0].PublicKeyToken | Should -BeExactly '30ad4fe6b2a6aeed'
        $entry[0].Version | Should -Be '2.1.0.0'
    }

    It 'has an entry for each package that ships an assembly of that name' {
        $index = Get-Index @(
            (New-Pkg -Name 'One.wsp' -Assembly @((New-Asm 'Contoso.Shared')))
            (New-Pkg -Name 'Two.wsp' -Assembly @((New-Asm 'Contoso.Shared'), (New-Asm 'Contoso.Two')))
        )

        @($index['contoso.shared'].PackageName | Sort-Object) | Should -Be @('One.wsp', 'Two.wsp')
        @($index['contoso.two']) | Should -HaveCount 1
    }

    It 'leaves out a satellite assembly, a file that is not an assembly and an assembly without a name' {
        $index = Get-Index @((New-Pkg -Name 'Contoso.wsp' -Assembly @(
                    (New-Asm 'Contoso.Intranet')
                    (New-Asm 'Contoso.Intranet.resources' -IsSatellite $true)
                    (New-Asm 'Contoso.Native' -IsManaged $false)
                    (New-Asm '')
                    (New-Asm '   ')
                )))

        @($index.Keys) | Should -BeExactly @('contoso.intranet')
    }

    It 'is empty, and not null, when there is no package, a package without assemblies or a null' -ForEach @(
        @{ Case = 'no package'; Package = @() }
        @{ Case = 'a null'; Package = $null }
        @{ Case = 'a package without assemblies'; Package = @([PSCustomObject]@{ PackageName = 'Declarative.wsp'; FarmSolutionName = ''; Assemblies = @() }) }
        @{ Case = 'a null package'; Package = @($null) }
    ) {
        $index = Get-Index $Package

        $index -is [hashtable] | Should -BeTrue -Because $Case
        $index.Count | Should -Be 0 -Because $Case
    }

    It 'reads the records that Get-SPSSolutionPackageInfo returns' {
        $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spsasmidx-' + [guid]::NewGuid().ToString('N'))
        try {
            $folder = Join-Path -Path $dir -ChildPath 'Contoso.Intranet'
            New-TestPackageFolder -Path $folder
            $package = @(Get-SPSSolutionPackageInfo -Path $folder -KnownMicrosoftPublicKeyToken $script:GenuineToken)

            $index = Get-Index $package

            @($index.Keys | Sort-Object) | Should -Be @('contoso.fixture.custom', 'contoso.fixture.legacy', 'fixture.genuine')
            @($index['contoso.fixture.custom'])[0].PackageName | Should -Be 'Contoso.Intranet'
            @($index['contoso.fixture.custom'])[0].PublicKeyToken | Should -Be '30ad4fe6b2a6aeed'
            @($index['contoso.fixture.custom'])[0].Version | Should -Be '1.2.3.4'
            @($index['fixture.genuine'])[0].PublicKeyToken | Should -Be $script:GenuineToken
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
