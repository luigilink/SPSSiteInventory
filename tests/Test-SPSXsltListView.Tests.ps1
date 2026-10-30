# Behavior tests for Test-SPSXsltListView (classification of a list view, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # A real .NET type: PowerShell turns an exception of a getter into $null, so only a compiled getter
    # reproduces a view property that cannot be read.
    if (-not ('SPSTestBrokenView' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestBrokenView
{
    public string XslLink { get { return ""; } }
    public string Xsl { get { throw new InvalidOperationException("xsl unavailable"); } }
}

public class SPSTestBrokenLinkView
{
    public string XslLink { get { throw new InvalidOperationException("link unavailable"); } }
    public string Xsl { get { return ""; } }
}
'@
    }

    function Test-View {
        param ($View)
        & $script:Module { param ($Candidate) Test-SPSXsltListView -View $Candidate } $View
    }
}

Describe 'Test-SPSXsltListView' {
    It 'does not report a view that uses the default style sheet' -ForEach @(
        @{ Link = 'main.xsl' }
        @{ Link = 'MAIN.XSL' }
        @{ Link = '  main.xsl  ' }
        @{ Link = '' }
        @{ Link = $null }
    ) {
        Test-View -View ([PSCustomObject]@{ XslLink = $Link; Xsl = '' }) | Should -BeFalse
    }

    # SharePoint looks a bare file name up in its own XSL folder: the asset library and the web parts of a
    # blog name AssetPicker.xsl and blog.xsl without a path, like every view names main.xsl.
    It 'does not report a view whose XslLink is <Link>, a style sheet that SharePoint ships' -ForEach @(
        @{ Link = 'blog.xsl' }
        @{ Link = 'AssetPicker.xsl' }
        @{ Link = 'groupboard.xsl' }
        @{ Link = '/_layouts/15/xsl/blog.xsl' }
        @{ Link = '/_layouts/xsl/main.xsl' }
        @{ Link = '/_LAYOUTS/15/XSL/Blog.XSL' }
        @{ Link = '_layouts/15/xsl/main.xsl' }
        @{ Link = '~site/_layouts/15/xsl/main.xsl' }
        @{ Link = '/sites/team/_layouts/15/xsl/main.xsl' }
        @{ Link = '\_layouts\15\xsl\main.xsl' }
    ) {
        Test-View -View ([PSCustomObject]@{ XslLink = $Link; Xsl = '' }) | Should -BeFalse
    }

    It 'reports a view whose XslLink is <Link>' -ForEach @(
        @{ Link = '/sites/team/Style Library/XSL Style Sheets/custom.xsl' }
        @{ Link = '~sitecollection/Style Library/brand.xsl' }
        @{ Link = '/Style Library/main.xsl' }
        @{ Link = '/_layouts/15/MyProject/custom.xsl' }
        @{ Link = '/_layouts/15/xsl/sub/custom.xsl' }
        @{ Link = '/_layouts/15/xslfiles/custom.xsl' }
        @{ Link = '/layouts/15/xsl/custom.xsl' }
        @{ Link = '/Style Library/my_layouts/xsl/custom.xsl' }
        @{ Link = '..\Style Library\custom.xsl' }
        @{ Link = 'https://cdn.contoso.com/xsl/custom.xsl' }
        @{ Link = 'https://cdn.contoso.com/_layouts/15/xsl/custom.xsl' }
        @{ Link = '//cdn.contoso.com/_layouts/15/xsl/custom.xsl' }
        @{ Link = '/\cdn.contoso.com/_layouts/15/xsl/custom.xsl' }
        @{ Link = '\\fileserver\share\_layouts\15\xsl\custom.xsl' }
        @{ Link = 'HTTPS://CDN.CONTOSO.COM/_LAYOUTS/15/XSL/MAIN.XSL' }
        @{ Link = 'http://sharepoint.contoso.com/_layouts/15/xsl/main.xsl' }
        @{ Link = 'file:///C:/inetpub/_layouts/15/xsl/custom.xsl' }
        @{ Link = 'C:\inetpub\_layouts\15\xsl\custom.xsl' }
    ) {
        Test-View -View ([PSCustomObject]@{ XslLink = $Link; Xsl = '' }) | Should -BeTrue
    }

    It 'reports a view that keeps its own XSL' {
        Test-View -View ([PSCustomObject]@{ XslLink = 'main.xsl'; Xsl = '<xsl:stylesheet version="1.0"></xsl:stylesheet>' }) | Should -BeTrue
        Test-View -View ([PSCustomObject]@{ XslLink = $null; Xsl = '<xsl:stylesheet />' }) | Should -BeTrue
        Test-View -View ([PSCustomObject]@{ XslLink = 'blog.xsl'; Xsl = '<xsl:stylesheet />' }) | Should -BeTrue
    }

    It 'does not report a view whose XSL is blank' {
        Test-View -View ([PSCustomObject]@{ XslLink = 'main.xsl'; Xsl = '   ' }) | Should -BeFalse
        Test-View -View ([PSCustomObject]@{ XslLink = 'main.xsl'; Xsl = $null }) | Should -BeFalse
    }

    It 'does not report a view that has neither property' {
        Test-View -View ([PSCustomObject]@{ Title = 'All Items' }) | Should -BeFalse
    }

    It 'rejects an XSL that cannot be read, instead of taking the view for one without XSLT' {
        { Test-View -View ([SPSTestBrokenView]::new()) } | Should -Throw '*xsl unavailable*'
    }

    It 'rejects an XslLink that cannot be read' {
        { Test-View -View ([SPSTestBrokenLinkView]::new()) } | Should -Throw '*link unavailable*'
    }

    It 'rejects a missing view' {
        { Test-View -View $null } | Should -Throw '*unavailable*'
    }

    It 'returns a boolean' {
        Test-View -View ([PSCustomObject]@{ XslLink = '/Style Library/custom.xsl' }) | Should -BeOfType [bool]
        Test-View -View ([PSCustomObject]@{ XslLink = 'main.xsl' }) | Should -BeOfType [bool]
    }
}
