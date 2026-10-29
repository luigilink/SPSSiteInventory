# Get-SPSProxyGroupServiceContext builds the service context of a proxy group with SharePoint types, which do not exist here.
# The failure when they are not loaded is tested in this process. The call itself is tested in a PowerShell process of its
# own, with stub types that have the names and the signatures of the two SharePoint types: the stubs stay out of the other
# tests, which rely on the types not being loaded.
BeforeAll {
    $script:ModulePath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $script:ModulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:ChildScript = Join-Path $TestDrive 'context-child.ps1'
    Set-Content -Path $script:ChildScript -Encoding UTF8 -Value @'
param ([System.String] $ModulePath, [System.String] $Case)
$ErrorActionPreference = 'Stop'
$source = @"
namespace Microsoft.SharePoint {
    public class SPSiteSubscriptionIdentifier {
        public static SPSiteSubscriptionIdentifier Default { get { return new SPSiteSubscriptionIdentifier(); } }
    }
    public class SPServiceContext {
        public object ProxyGroup;
        public SPSiteSubscriptionIdentifier Subscription;
        public static SPServiceContext GetContext(object proxyGroup, SPSiteSubscriptionIdentifier subscription) {
            if (proxyGroup is string && (string)proxyGroup == "none") { return null; }
            return new SPServiceContext { ProxyGroup = proxyGroup, Subscription = subscription };
        }
    }
}
"@
Add-Type -TypeDefinition $source
Import-Module -Name $ModulePath -Force
$module = Get-Module -Name SPSSiteInventory.Common
$group = if ($Case -eq 'none') { 'none' } else { [PSCustomObject]@{ Name = 'Default' } }
try {
    $context = & $module { param ($ProxyGroup) Get-SPSProxyGroupServiceContext -ProxyGroup $ProxyGroup } $group
    ConvertTo-Json -Compress -InputObject ([PSCustomObject]@{
            Type = $context.GetType().FullName
            GroupName = [string]$context.ProxyGroup.Name
            Subscription = $context.Subscription.GetType().FullName
            Error = ''
        })
}
catch {
    ConvertTo-Json -Compress -InputObject ([PSCustomObject]@{ Type = ''; GroupName = ''; Subscription = ''; Error = $_.Exception.Message })
}
'@

    function Invoke-ContextChild {
        param ([string] $Case = 'group')
        $shell = (Get-Process -Id $PID).Path
        $output = @(& $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:ChildScript -ModulePath $script:ModulePath -Case $Case 2>&1 | ForEach-Object { [System.String]$_ })
        $line = @($output | Where-Object { $_ -like '{*' })
        [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Result = $(if ($line.Count -gt 0) { ConvertFrom-Json -InputObject $line[0] } else { $null }); Text = ($output -join [System.Environment]::NewLine) }
    }
}

Describe 'Get-SPSProxyGroupServiceContext' {
    It 'raises a clear error when the SharePoint types are not loaded' {
        { & $script:Module { Get-SPSProxyGroupServiceContext -ProxyGroup ([PSCustomObject]@{ Name = 'Default' }) } } | Should -Throw '*service context types are not loaded*'
    }

    It 'gets the context of the proxy group for the default site subscription' {
        $run = Invoke-ContextChild

        $run.ExitCode | Should -Be 0 -Because $run.Text
        $run.Result.Error | Should -Be '' -Because $run.Text
        $run.Result.Type | Should -Be 'Microsoft.SharePoint.SPServiceContext'
        $run.Result.GroupName | Should -Be 'Default'
        $run.Result.Subscription | Should -Be 'Microsoft.SharePoint.SPSiteSubscriptionIdentifier'
    }

    It 'raises an error when SharePoint gives no context' {
        $run = Invoke-ContextChild -Case 'none'

        $run.ExitCode | Should -Be 0 -Because $run.Text
        $run.Result.Error | Should -Match 'service context of the service application proxy group is unavailable'
    }

    It 'looks the SharePoint types up among the loaded assemblies' {
        $text = Get-Content -LiteralPath (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src/Modules/SPSSiteInventory.Common/Private/Get-SPSProxyGroupServiceContext.ps1') -Raw

        $text | Should -Match "'Microsoft\.SharePoint\.SPServiceContext' -as \[System\.Type\]"
        $text | Should -Match "'Microsoft\.SharePoint\.SPSiteSubscriptionIdentifier' -as \[System\.Type\]"
        $text | Should -Not -Match '\[Type\]::GetType|\[System\.Type\]::GetType'
    }
}
