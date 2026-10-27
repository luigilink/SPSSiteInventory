# Behavior tests for Test-SPSExternalList (no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Test-SPSExternalList is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # A real .NET type is required: PowerShell turns a failing getter into $null, and also swallows
    # exceptions from script properties, so only a compiled getter reproduces a failed property read.
    if (-not ('SPSTestFlaggedList' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestFlaggedList
{
    public bool Fail { get; set; }
    public bool Flag { get; set; }
    public bool HasExternalDataSource { get { if (Fail) { throw new InvalidOperationException("flag unavailable"); } return Flag; } }
}
'@
    }

    function Test-List {
        param ($List)
        & $script:Module { param ($Candidate) Test-SPSExternalList -List $Candidate } $List
    }
}

Describe 'Test-SPSExternalList' {
    It 'reports a list flagged as having an external data source' {
        Test-List -List ([PSCustomObject]@{ HasExternalDataSource = $true }) | Should -BeTrue
    }

    It 'reports a list without an external data source' {
        Test-List -List ([PSCustomObject]@{ HasExternalDataSource = $false }) | Should -BeFalse
    }

    It 'reads the flag of a real .NET list' {
        $list = [SPSTestFlaggedList]::new()
        Test-List -List $list | Should -BeFalse

        $list.Flag = $true
        Test-List -List $list | Should -BeTrue
    }

    It 'rejects a missing flag instead of reading the list as not external' {
        { Test-List -List ([PSCustomObject]@{ Title = 'Customers' }) } | Should -Throw '*external data source flag could not be read*'
        { Test-List -List ([PSCustomObject]@{ HasExternalDataSource = $null }) } | Should -Throw '*external data source flag could not be read*'
    }

    It 'lets a failing flag getter propagate instead of reading the list as not external' {
        $list = [SPSTestFlaggedList]::new()
        $list.Fail = $true

        { Test-List -List $list } | Should -Throw '*flag unavailable*'
    }
}
