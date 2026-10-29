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

    It 'reports a view whose XslLink is <Link>' -ForEach @(
        @{ Link = '/sites/team/Style Library/XSL Style Sheets/custom.xsl' }
        @{ Link = 'custom.xsl' }
        @{ Link = '~sitecollection/Style Library/brand.xsl' }
        @{ Link = '/Style Library/main.xsl' }
    ) {
        Test-View -View ([PSCustomObject]@{ XslLink = $Link; Xsl = '' }) | Should -BeTrue
    }

    It 'reports a view that keeps its own XSL' {
        Test-View -View ([PSCustomObject]@{ XslLink = 'main.xsl'; Xsl = '<xsl:stylesheet version="1.0"></xsl:stylesheet>' }) | Should -BeTrue
        Test-View -View ([PSCustomObject]@{ XslLink = $null; Xsl = '<xsl:stylesheet />' }) | Should -BeTrue
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
        Test-View -View ([PSCustomObject]@{ XslLink = 'custom.xsl' }) | Should -BeOfType [bool]
        Test-View -View ([PSCustomObject]@{ XslLink = 'main.xsl' }) | Should -BeOfType [bool]
    }
}
