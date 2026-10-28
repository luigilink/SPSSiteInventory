# Behavior tests for Test-SPSCustomMasterPage (pure classification, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Test-Custom {
        param ([AllowNull()][string]$Url)
        & $script:Module { param ($Value) Test-SPSCustomMasterPage -Url $Value } $Url
    }
}

Describe 'Test-SPSCustomMasterPage' {
    It 'does not report <Url>, which SharePoint provisions' -ForEach @(
        @{ Url = '/_catalogs/masterpage/seattle.master' }
        @{ Url = '/_catalogs/masterpage/oslo.master' }
        @{ Url = '/_catalogs/masterpage/v4.master' }
        @{ Url = '/_catalogs/masterpage/mysite15.master' }
        @{ Url = '/sites/team/_catalogs/masterpage/seattle.master' }
        @{ Url = 'https://intranet.contoso.com/sites/team/_catalogs/masterpage/mysite15.master' }
        @{ Url = '/_catalogs/MasterPage/Seattle.Master' }
        @{ Url = '  /_catalogs/masterpage/oslo.master  ' }
        @{ Url = '\_catalogs\masterpage\v4.master' }
        @{ Url = '/_catalogs/masterpage/seattle.master?v=2' }
    ) {
        Test-Custom -Url $Url | Should -BeFalse
    }

    It 'reports <Url>, which is not a master page that SharePoint provisions' -ForEach @(
        @{ Url = '/_catalogs/masterpage/lab.master' }
        @{ Url = '/_catalogs/masterpage/contoso.master' }
        @{ Url = '/_catalogs/masterpage/myseattle.master' }
        @{ Url = '/_catalogs/masterpage/contoso-v4.master' }
        @{ Url = '/_catalogs/masterpage/seattle.master.old' }
        @{ Url = '/_catalogs/masterpage/Contoso/seattle.master' }
        @{ Url = '/Style Library/seattle.master' }
        @{ Url = '/sites/team/seattle.master' }
        @{ Url = 'seattle.master' }
        @{ Url = 'https://intranet.contoso.com/sites/team/_catalogs/masterpage/brand.master' }
    ) {
        Test-Custom -Url $Url | Should -BeTrue
    }

    It 'does not report a web that has no master page of its own' {
        Test-Custom -Url $null | Should -BeFalse
        Test-Custom -Url '' | Should -BeFalse
        Test-Custom -Url '   ' | Should -BeFalse
    }

    It 'returns a boolean' {
        Test-Custom -Url '/_catalogs/masterpage/seattle.master' | Should -BeOfType [bool]
        Test-Custom -Url '/_catalogs/masterpage/lab.master' | Should -BeOfType [bool]
    }
}
