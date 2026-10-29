# Get-SPSBuiltInProfilePropertyName reads the static fields of PropertyConstants, a SharePoint type that does not exist here.
# The failure when it is not loaded is tested in this process. The reading is tested in a PowerShell process of its own, with a
# stub type that has the name of the SharePoint one: the stub stays out of the other tests.
BeforeAll {
    $script:ModulePath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $script:ModulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:ChildScript = Join-Path $TestDrive 'constants-child.ps1'
    Set-Content -Path $script:ChildScript -Encoding UTF8 -Value @'
param ([System.String] $ModulePath, [System.String] $Case)
$ErrorActionPreference = 'Stop'
$withStrings = @"
namespace Microsoft.Office.Server.UserProfiles {
    public static class PropertyConstants {
        public const string AccountName = "AccountName";
        public static readonly string FirstName = "FirstName";
        public static readonly string SipAddress = "SPS-SipAddress";
        public static readonly string Blank = " ";
        public static readonly int Limit = 12;
        public static string Nothing = null;
        internal static readonly string Hidden = "Hidden";
    }
}
"@
$withoutStrings = @"
namespace Microsoft.Office.Server.UserProfiles {
    public static class PropertyConstants {
        public static readonly int Limit = 12;
    }
}
"@
Add-Type -TypeDefinition $(if ($Case -eq 'nostring') { $withoutStrings } else { $withStrings })
Import-Module -Name $ModulePath -Force
$module = Get-Module -Name SPSSiteInventory.Common
$names = & $module { Get-SPSBuiltInProfilePropertyName -Verbose 4>&1 }
$verbose = @($names | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { [string]$_.Message })
$values = @($names | Where-Object { $_ -is [string] })
ConvertTo-Json -Compress -InputObject ([PSCustomObject]@{ Names = @($values); Verbose = @($verbose); IsNull = ($values.Count -eq 0) })
'@

    function Invoke-ConstantsChild {
        param ([string] $Case = 'strings')
        $shell = (Get-Process -Id $PID).Path
        $output = @(& $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:ChildScript -ModulePath $script:ModulePath -Case $Case 2>&1 | ForEach-Object { [System.String]$_ })
        $line = @($output | Where-Object { $_ -like '{*' })
        [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Result = $(if ($line.Count -gt 0) { ConvertFrom-Json -InputObject $line[0] } else { $null }); Text = ($output -join [System.Environment]::NewLine) }
    }
}

Describe 'Get-SPSBuiltInProfilePropertyName' {
    It 'returns the values of the public static string fields of PropertyConstants, constants included' {
        $run = Invoke-ConstantsChild

        $run.ExitCode | Should -Be 0 -Because $run.Text
        # The order of the fields of a type is the one of its metadata, which nothing relies on.
        @($run.Result.Names | Sort-Object) | Should -Be @('AccountName', 'FirstName', 'SPS-SipAddress')
    }

    It 'leaves out a field that is not a string, a blank one, a null one and a non-public one' {
        $run = Invoke-ConstantsChild

        @($run.Result.Names) | Should -Not -Contain 'Hidden'
        @($run.Result.Names) | Should -Not -Contain 12
        @($run.Result.Names) | Should -HaveCount 3
    }

    It 'returns nothing, and says why in the verbose stream, when the type has no string field' {
        $run = Invoke-ConstantsChild -Case 'nostring'

        $run.ExitCode | Should -Be 0 -Because $run.Text
        $run.Result.IsNull | Should -BeTrue
        ($run.Result.Verbose -join ';') | Should -Match 'The built-in profile properties could not be listed: The PropertyConstants type has no string field'
    }

    It 'returns nothing, and does not raise an error, when the type is not available' {
        $names = & $script:Module { Get-SPSBuiltInProfilePropertyName }

        $names | Should -BeNullOrEmpty
    }
}
