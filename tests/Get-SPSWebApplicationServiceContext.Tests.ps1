# Behavior tests for Get-SPSWebApplicationServiceContext. Only the failure path can run without a farm:
# the success path calls SPServiceContext, which needs the SharePoint object model.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Get-SPSWebApplicationServiceContext is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common
}

Describe 'Get-SPSWebApplicationServiceContext' {
    It 'rejects a web application whose service application proxy group cannot be read' {
        $webApplication = [PSCustomObject]@{ Url = 'https://intranet'; ServiceApplicationProxyGroup = $null }

        { & $script:Module { param ($Candidate) Get-SPSWebApplicationServiceContext -WebApplication $Candidate } $webApplication } |
            Should -Throw "*service application proxy group of 'https://intranet' could not be read*"
    }
}
