# Resolve-SPSAudienceName reads audiences with the audience manager of the User Profile service, a SharePoint type that
# does not exist here. The failures are tested in this process. The reading is tested in a PowerShell process of its own,
# with stub types that have the names and the signatures of the SharePoint ones: the stubs stay out of the other tests.
BeforeAll {
    $script:ModulePath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $script:ModulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:ChildScript = Join-Path $TestDrive 'audience-child.ps1'
    Set-Content -Path $script:ChildScript -Encoding UTF8 -Value @'
param ([System.String] $ModulePath, [System.String] $Case)
$ErrorActionPreference = 'Stop'
$source = @"
using System;
namespace Microsoft.Office.Server.Audience {
    public class Audience {
        public string AudienceName { get; set; }
        public Guid AudienceID { get; set; }
    }
    public class AudienceManager {
        public object Context;
        public static int Constructed;
        public AudienceManager(object context) {
            Constructed++;
            Context = context;
        }
        public Audience GetAudience(Guid id) {
            if (id == new Guid("a88b9dcb-0000-0000-0000-000000000001")) { return new Audience { AudienceName = "Sales", AudienceID = id }; }
            if (id == new Guid("a88b9dcb-0000-0000-0000-000000000003")) { return new Audience { AudienceName = "  ", AudienceID = id }; }
            if (id == new Guid("a88b9dcb-0000-0000-0000-000000000004")) { throw new InvalidOperationException("audience unavailable"); }
            return null;
        }
        public Audience GetAudience(string name) { throw new InvalidOperationException("the String overload must not be used"); }
    }
}
"@
Add-Type -TypeDefinition $source
function global:Get-SPServiceContext {
    param ($Site)
    if ($Case -eq 'nocontext') { throw 'The site has no service context' }
    [PSCustomObject]@{ Site = $Site; Token = 'context' }
}
Import-Module -Name $ModulePath -Force
$module = Get-Module -Name SPSSiteInventory.Common
$ids = @('A88B9DCB-0000-0000-0000-000000000001', 'a88b9dcb-0000-0000-0000-000000000002', 'a88b9dcb-0000-0000-0000-000000000003', 'a88b9dcb-0000-0000-0000-000000000004', 'not-a-guid')
$names = & $module { param ($Identifiers) Resolve-SPSAudienceName -Site ([PSCustomObject]@{ Url = 'https://intranet' }) -AudienceId $Identifiers -Verbose 4>&1 } $ids
$result = [ordered]@{}
foreach ($item in @($names | Where-Object { $_ -is [hashtable] })) { foreach ($key in $item.Keys) { $result[$key] = $item[$key] } }
$verbose = @($names | Where-Object { $_ -isnot [hashtable] } | ForEach-Object { [string]$_ })
ConvertTo-Json -Compress -InputObject ([PSCustomObject]@{ Names = $result; Verbose = $verbose; Constructed = [Microsoft.Office.Server.Audience.AudienceManager]::Constructed })
'@

    function Invoke-AudienceChild {
        param ([string] $Case = 'names')
        $shell = (Get-Process -Id $PID).Path
        $output = @(& $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:ChildScript -ModulePath $script:ModulePath -Case $Case 2>&1 | ForEach-Object { [System.String]$_ })
        $line = @($output | Where-Object { $_ -like '{*' })
        [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Result = $(if ($line.Count -gt 0) { ConvertFrom-Json -InputObject $line[0] } else { $null }); Text = ($output -join [System.Environment]::NewLine) }
    }

    $global:SPSTestContextCalls = 0
    function global:Get-SPServiceContext {
        param ($Site)
        $global:SPSTestContextCalls++
        [PSCustomObject]@{ Site = $Site }
    }
}

AfterAll {
    Remove-Item -Path Function:\global:Get-SPServiceContext -ErrorAction SilentlyContinue
    Remove-Variable -Name SPSTestContextCalls -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Resolve-SPSAudienceName' {
    It 'gives the name of each audience that the audience manager finds, under the ID in lower case' {
        $run = Invoke-AudienceChild

        $run.ExitCode | Should -Be 0 -Because $run.Text
        $run.Result.Names.'a88b9dcb-0000-0000-0000-000000000001' | Should -Be 'Sales'
        $run.Result.Constructed | Should -Be 1
    }

    It 'leaves out an audience that does not exist, one with a blank name, one that fails, and what is not an ID, and keeps the others' {
        $run = Invoke-AudienceChild

        $names = @($run.Result.Names.PSObject.Properties | ForEach-Object { $_.Name })
        $names | Should -HaveCount 1
        $names | Should -BeExactly @('a88b9dcb-0000-0000-0000-000000000001')
        ($run.Result.Verbose -join ';') | Should -Match "audience 'a88b9dcb-0000-0000-0000-000000000004' could not be read.*audience unavailable"
    }

    It 'returns no name, and says why in the verbose stream, when the service context cannot be read' {
        $run = Invoke-AudienceChild -Case 'nocontext'

        $run.ExitCode | Should -Be 0 -Because $run.Text
        @($run.Result.Names.PSObject.Properties).Count | Should -Be 0
        ($run.Result.Verbose -join ';') | Should -Match 'The audiences could not be read, so their IDs are shown.*no service context'
        $run.Result.Constructed | Should -Be 0
    }

    It 'returns no name, and does not raise an error, when the audience manager type is not available' {
        $names = & $script:Module { Resolve-SPSAudienceName -Site ([PSCustomObject]@{ Url = 'https://intranet' }) -AudienceId @('a88b9dcb-0000-0000-0000-000000000001') }

        $names | Should -BeOfType ([hashtable])
        $names.Count | Should -Be 0
    }

    It 'returns an empty table without reading anything when no ID is given' {
        $global:SPSTestContextCalls = 0

        $names = & $script:Module { Resolve-SPSAudienceName -Site ([PSCustomObject]@{ Url = 'https://intranet' }) -AudienceId @() }

        $names | Should -BeOfType ([hashtable])
        $names.Count | Should -Be 0
        $global:SPSTestContextCalls | Should -Be 0
    }
}
