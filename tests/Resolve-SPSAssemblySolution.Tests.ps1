# Behavior tests for Resolve-SPSAssemblySolution (which inspected package, and which farm solution, ships an assembly).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function New-Pkg {
        param ([string]$Name, [string]$Farm = '', [object[]]$Assembly = @())
        [PSCustomObject]@{ PackageName = $Name; FarmSolutionName = $Farm; Assemblies = $Assembly }
    }

    function New-Asm {
        param ([string]$Name, [string]$Token = '30ad4fe6b2a6aeed', [string]$Version = '1.0.0.0')
        [PSCustomObject]@{ Name = $Name; PublicKeyToken = $Token; Version = $Version; IsSatellite = $false; IsManaged = $true }
    }

    function Resolve-Assembly {
        param ([object[]]$Package, [string]$Assembly)
        & $script:Module {
            param ($Value, $Name)
            $index = Get-SPSSolutionAssemblyIndex -SolutionPackages $Value
            Resolve-SPSAssemblySolution -AssemblyName $Name -Index $index
        } $Package $Assembly
    }

    $script:Registered = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed'
}

Describe 'Resolve-SPSAssemblySolution' {
    It 'names the package and the farm solution that ship the assembly, on its name and its key' {
        $result = Resolve-Assembly -Package @((New-Pkg -Name 'Contoso.Intranet.wsp' -Farm 'contoso.intranet.wsp' -Assembly @((New-Asm 'Contoso.Intranet')))) -Assembly $script:Registered

        $result.MatchedBy | Should -BeExactly 'AssemblyNameAndKey'
        $result.PackageName | Should -Be 'Contoso.Intranet.wsp'
        $result.FarmSolutionName | Should -Be 'contoso.intranet.wsp'
    }

    It 'compares the name and the token without looking at the case' {
        $result = Resolve-Assembly -Package @((New-Pkg -Name 'A.wsp' -Assembly @((New-Asm 'CONTOSO.intranet' -Token '30AD4FE6B2A6AEED')))) -Assembly 'contoso.INTRANET, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed'

        $result.MatchedBy | Should -BeExactly 'AssemblyNameAndKey'
    }

    It 'does not compare the version: a package often ships a newer one than the one registered' {
        $result = Resolve-Assembly -Package @((New-Pkg -Name 'A.wsp' -Assembly @((New-Asm 'Contoso.Intranet' -Version '3.0.0.0')))) -Assembly $script:Registered

        $result.MatchedBy | Should -BeExactly 'AssemblyNameAndKey'
    }

    It 'does not match an assembly of the same name that has another public key token' {
        $result = Resolve-Assembly -Package @((New-Pkg -Name 'A.wsp' -Assembly @((New-Asm 'Contoso.Intranet' -Token 'ffffffffffffffff')))) -Assembly $script:Registered

        $result | Should -BeNullOrEmpty
    }

    It 'matches on the name alone, and says so, when the registered assembly or the one of the package has no token' -ForEach @(
        @{ Case = 'registered without a token'; Registered = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null'; Token = '30ad4fe6b2a6aeed' }
        @{ Case = 'registered by its name only'; Registered = 'Contoso.Intranet'; Token = '30ad4fe6b2a6aeed' }
        @{ Case = 'a package assembly that has no token'; Registered = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed'; Token = '' }
    ) {
        $result = Resolve-Assembly -Package @((New-Pkg -Name 'A.wsp' -Farm 'a.wsp' -Assembly @((New-Asm 'Contoso.Intranet' -Token $Token)))) -Assembly $Registered

        $result.MatchedBy | Should -BeExactly 'AssemblyName' -Because $Case
        $result.PackageName | Should -Be 'A.wsp'
        $result.FarmSolutionName | Should -Be 'a.wsp'
    }

    It 'prefers the packages that match on the key to the ones that match on the name alone' {
        $result = Resolve-Assembly -Package @(
            (New-Pkg -Name 'Keyed.wsp' -Assembly @((New-Asm 'Contoso.Intranet')))
            (New-Pkg -Name 'Unsigned.wsp' -Assembly @((New-Asm 'Contoso.Intranet' -Token '')))
        ) -Assembly $script:Registered

        $result.MatchedBy | Should -BeExactly 'AssemblyNameAndKey'
        $result.PackageName | Should -Be 'Keyed.wsp'
    }

    It 'names every package that ships the assembly, sorted, and the farm solutions of those that are deployed' {
        $result = Resolve-Assembly -Package @(
            (New-Pkg -Name 'Two.wsp' -Farm 'two.wsp' -Assembly @((New-Asm 'Contoso.Intranet')))
            (New-Pkg -Name 'One.wsp' -Farm '' -Assembly @((New-Asm 'Contoso.Intranet')))
            (New-Pkg -Name 'Three.wsp' -Farm 'three.wsp' -Assembly @((New-Asm 'Contoso.Intranet')))
        ) -Assembly $script:Registered

        $result.PackageName | Should -Be 'One.wsp; Three.wsp; Two.wsp'
        $result.FarmSolutionName | Should -Be 'three.wsp; two.wsp'
    }

    It 'says the farm solution is empty when the package that ships the assembly is not in the farm' {
        $result = Resolve-Assembly -Package @((New-Pkg -Name 'Old.wsp' -Farm '' -Assembly @((New-Asm 'Contoso.Intranet')))) -Assembly $script:Registered

        $result.PackageName | Should -Be 'Old.wsp'
        $result.FarmSolutionName | Should -Be ''
    }

    It 'returns nothing when no package ships the assembly' {
        Resolve-Assembly -Package @((New-Pkg -Name 'A.wsp' -Assembly @((New-Asm 'Contoso.Other')))) -Assembly $script:Registered | Should -BeNullOrEmpty
    }

    It 'returns nothing when the index is empty, or the assembly has no name' -ForEach @(
        @{ Case = 'empty index'; Assembly = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed' }
        @{ Case = 'empty name'; Assembly = '' }
        @{ Case = 'blank name'; Assembly = '   ' }
        @{ Case = 'null name'; Assembly = $null }
    ) {
        $package = @([PSCustomObject]@{ PackageName = 'A.wsp'; FarmSolutionName = ''; Assemblies = @([PSCustomObject]@{ Name = 'Contoso.Intranet'; PublicKeyToken = '30ad4fe6b2a6aeed'; Version = '1.0.0.0'; IsSatellite = $false; IsManaged = $true }) })
        if ($Case -eq 'empty index') { $package = @() }

        Resolve-Assembly -Package $package -Assembly $Assembly | Should -BeNullOrEmpty -Because $Case
    }

    It 'finds the assembly in an index whose keys are compared with case, because it looks the name up in lower case' {
        $result = & $script:Module {
            param ($Name)
            $index = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
            $index['contoso.intranet'] = @([PSCustomObject]@{ PackageName = 'A.wsp'; FarmSolutionName = ''; PublicKeyToken = '30ad4fe6b2a6aeed'; Version = '1.0.0.0' })
            Resolve-SPSAssemblySolution -AssemblyName $Name -Index $index
        } 'Contoso.INTRANET, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed'

        $result.PackageName | Should -Be 'A.wsp'
    }

    It 'reads an index that is not a hashtable, as one, and finds nothing for an assembly that is not in it' -ForEach @(
        @{ Case = 'an ordered dictionary'; Kind = 'ordered' }
        @{ Case = 'a generic dictionary'; Kind = 'generic' }
    ) {
        $package = @((New-Pkg -Name 'Contoso.Intranet.wsp' -Farm 'contoso.intranet.wsp' -Assembly @((New-Asm 'Contoso.Intranet'))))

        $result = & $script:Module {
            param ($Package, $Kind, $Known, $Unknown)
            $source = Get-SPSSolutionAssemblyIndex -SolutionPackages $Package
            $index = if ($Kind -eq 'ordered') { [ordered]@{} } else { [System.Collections.Generic.Dictionary[System.String, System.Object]]::new() }
            foreach ($key in @($source.Keys)) {
                $index[$key] = $source[$key]
            }
            [PSCustomObject]@{
                Found   = Resolve-SPSAssemblySolution -AssemblyName $Known -Index $index
                Missing = Resolve-SPSAssemblySolution -AssemblyName $Unknown -Index $index
            }
        } $package $Kind $script:Registered 'Fabrikam.Docs, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed'

        $result.Found.MatchedBy | Should -BeExactly 'AssemblyNameAndKey' -Because $Case
        $result.Found.FarmSolutionName | Should -BeExactly 'contoso.intranet.wsp'
        $result.Missing | Should -BeNullOrEmpty
    }
}
