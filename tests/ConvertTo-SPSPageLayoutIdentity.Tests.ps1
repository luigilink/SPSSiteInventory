# Behavior tests for ConvertTo-SPSPageLayoutIdentity (pure URL normalization, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # ConvertTo-SPSPageLayoutIdentity is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-LayoutIdentity {
        param ($Value)
        & $script:Module { param ($Candidate) ConvertTo-SPSPageLayoutIdentity -LayoutValue $Candidate } $Value
    }
}

Describe 'ConvertTo-SPSPageLayoutIdentity' {
    It 'uses the path below the Master Page Gallery as the display name' {
        $identity = Get-LayoutIdentity -Value '/_catalogs/masterpage/ArticleLeft.aspx, Article Left'

        $identity.Key | Should -Be '/_catalogs/masterpage/ArticleLeft.aspx'
        $identity.Name | Should -Be 'ArticleLeft.aspx'
    }

    It 'keeps the folder in the name for a layout in a gallery subfolder' {
        $identity = Get-LayoutIdentity -Value '/_catalogs/masterpage/BrandA/Article.aspx, Brand A'

        $identity.Name | Should -Be 'BrandA/Article.aspx'
    }

    It 'gives layouts that share a file name in different folders different keys' {
        $first = Get-LayoutIdentity -Value '/_catalogs/masterpage/BrandA/Article.aspx, A'
        $second = Get-LayoutIdentity -Value '/_catalogs/masterpage/BrandB/Article.aspx, B'

        $first.Key | Should -Not -Be $second.Key
    }

    It 'reduces an absolute URL to its path so it matches the server-relative form' {
        $absolute = Get-LayoutIdentity -Value 'https://INTRANET.contoso.com:8443/sites/team/_catalogs/masterpage/ArticleLeft.aspx?x=1, Left'
        $relative = Get-LayoutIdentity -Value '/sites/team/_catalogs/masterpage/ArticleLeft.aspx, Left'

        $absolute.Key | Should -Be '/sites/team/_catalogs/masterpage/ArticleLeft.aspx'
        $absolute.Key | Should -Be $relative.Key
        $absolute.Name | Should -Be 'ArticleLeft.aspx'
    }

    It 'decodes URL escapes and normalizes separators' {
        (Get-LayoutIdentity -Value '/sites/team/_catalogs/masterpage/My%20Layout.aspx, x').Key | Should -Be '/sites/team/_catalogs/masterpage/My Layout.aspx'
        (Get-LayoutIdentity -Value '\sites\team\_catalogs\masterpage\BrandA\Article.aspx, x').Key | Should -Be '/sites/team/_catalogs/masterpage/BrandA/Article.aspx'
        (Get-LayoutIdentity -Value '/sites/team/_catalogs/masterpage//Article.aspx, x').Key | Should -Be '/sites/team/_catalogs/masterpage/Article.aspx'
        (Get-LayoutIdentity -Value '_catalogs/masterpage/Relative.aspx, x').Key | Should -Be '/_catalogs/masterpage/Relative.aspx'
    }

    It 'accepts a bare URL without a description' {
        (Get-LayoutIdentity -Value '/_catalogs/masterpage/A.aspx').Name | Should -Be 'A.aspx'
    }

    It 'uses the whole path as the name outside the Master Page Gallery' {
        (Get-LayoutIdentity -Value '/sites/team/Style Library/Layouts/Custom.aspx, Custom').Name | Should -Be '/sites/team/Style Library/Layouts/Custom.aspx'
    }

    It 'returns null when the value holds no URL' {
        Get-LayoutIdentity -Value $null | Should -BeNullOrEmpty
        Get-LayoutIdentity -Value '' | Should -BeNullOrEmpty
        Get-LayoutIdentity -Value '   ' | Should -BeNullOrEmpty
        Get-LayoutIdentity -Value ', only a description' | Should -BeNullOrEmpty
    }
}
