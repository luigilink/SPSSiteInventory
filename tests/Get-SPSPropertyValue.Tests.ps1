# Behavior tests for Get-SPSPropertyValue (pure property access, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Get-SPSPropertyValue is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # A real .NET type is required: PowerShell also swallows exceptions from script properties.
    if (-not ('SPSTestPropertyBag' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestPropertyBag
{
    public string Name { get { return "invoices"; } }
    public string Empty { get { return null; } }
    public string Broken { get { throw new InvalidOperationException("alias store unavailable"); } }
    public string this[string key] { get { return "indexed"; } }
}
'@
    }

    function Get-Value {
        param ($Object, [string]$Name)
        & $script:Module { param ($Candidate, $PropertyName) Get-SPSPropertyValue -InputObject $Candidate -Name $PropertyName } $Object $Name
    }
}

Describe 'Get-SPSPropertyValue' {
    It 'returns the value of a readable property' {
        Get-Value -Object ([SPSTestPropertyBag]::new()) -Name 'Name' | Should -Be 'invoices'
    }

    It 'keeps a successfully read null as null' {
        Get-Value -Object ([SPSTestPropertyBag]::new()) -Name 'Empty' | Should -BeNullOrEmpty
    }

    It 'lets an exception thrown by the getter propagate instead of returning null' {
        { Get-Value -Object ([SPSTestPropertyBag]::new()) -Name 'Broken' } | Should -Throw '*alias store unavailable*'
    }

    It 'reads note properties and treats a missing property as null' {
        Get-Value -Object ([PSCustomObject]@{ EmailAlias = 'requests' }) -Name 'EmailAlias' | Should -Be 'requests'
        Get-Value -Object ([PSCustomObject]@{ Title = 'x' }) -Name 'EmailAlias' | Should -BeNullOrEmpty
    }

    It 'rejects a null object' {
        { Get-Value -Object $null -Name 'EmailAlias' } | Should -Throw '*unavailable*'
    }
}
