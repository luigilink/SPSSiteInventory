# Get-SPSUserProfileConfigManager creates a SharePoint type that does not exist here. The failure is tested in this process. The creation
# is tested in a PowerShell process of its own, with a stub type that has the name and the constructor of the SharePoint one.
BeforeAll {
    $script:ModulePath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $script:ModulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:ChildScript = Join-Path $TestDrive 'manager-child.ps1'
    Set-Content -Path $script:ChildScript -Encoding UTF8 -Value @'
param ([System.String] $ModulePath)
$ErrorActionPreference = 'Stop'
$source = @"
namespace Microsoft.Office.Server.UserProfiles {
    public class UserProfileConfigManager {
        public object Context;
        public UserProfileConfigManager(object context) { Context = context; }
    }
}
"@
Add-Type -TypeDefinition $source
Import-Module -Name $ModulePath -Force
$module = Get-Module -Name SPSSiteInventory.Common
$manager = & $module { param ($Token) Get-SPSUserProfileConfigManager -ServiceContext $Token } ([PSCustomObject]@{ Name = 'context' })
ConvertTo-Json -Compress -InputObject ([PSCustomObject]@{ Type = $manager.GetType().FullName; Context = [string]$manager.Context.Name })
'@

    function Invoke-ManagerChild {
        $shell = (Get-Process -Id $PID).Path
        $output = @(& $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:ChildScript -ModulePath $script:ModulePath 2>&1 | ForEach-Object { [System.String]$_ })
        $line = @($output | Where-Object { $_ -like '{*' })
        [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Result = $(if ($line.Count -gt 0) { ConvertFrom-Json -InputObject $line[0] } else { $null }); Text = ($output -join [System.Environment]::NewLine) }
    }
}

Describe 'Get-SPSUserProfileConfigManager' {
    It 'raises a clear error when the SharePoint type is not available' {
        { & $script:Module { Get-SPSUserProfileConfigManager -ServiceContext ([PSCustomObject]@{ Name = 'context' }) } } | Should -Throw '*configuration manager type is not available*'
    }

    It 'creates the manager with the service context' {
        $run = Invoke-ManagerChild

        $run.ExitCode | Should -Be 0 -Because $run.Text
        $run.Result.Type | Should -Be 'Microsoft.Office.Server.UserProfiles.UserProfileConfigManager'
        $run.Result.Context | Should -Be 'context'
    }

    It 'looks the type up among the loaded assemblies, loads the assembly of the service by its partial name when it is not there, and has no GetType call with an assembly name' {
        $text = Get-Content -LiteralPath (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src/Modules/SPSSiteInventory.Common/Private/Get-SPSUserProfileConfigManager.ps1') -Raw

        $text | Should -Match '-as \[System\.Type\]'
        $text | Should -Match "LoadWithPartialName\('Microsoft\.Office\.Server\.UserProfiles'\)"
        $text | Should -Not -Match '\[Type\]::GetType|\[System\.Type\]::GetType'
    }
}
