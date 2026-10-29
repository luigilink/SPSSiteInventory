# Behavior tests for Get-SPSScriptWebPartKind (classification of a web part, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # A real .NET type: PowerShell turns an exception of a getter into $null, so only a compiled getter
    # reproduces a web part property that cannot be read.
    if (-not ('SPSTestBrokenContentPart' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class SPSTestBrokenContentPart
{
    public string ContentLink { get { return ""; } }
    public object Content { get { throw new InvalidOperationException("content unavailable"); } }
}

public class SPSTestBrokenLinkPart
{
    public string ContentLink { get { throw new InvalidOperationException("link unavailable"); } }
    public object Content { get { return null; } }
}
'@
    }

    function Get-Kind {
        param ($WebPart)
        & $script:Module { param ($Candidate) Get-SPSScriptWebPartKind -WebPart $Candidate } $WebPart
    }

    function New-TestWebPart {
        param ([string[]]$TypeName, $Content = $null, $ContentLink = $null)
        $webPart = [PSCustomObject]@{ Title = 'Part'; Content = $Content; ContentLink = $ContentLink }
        foreach ($name in $TypeName) { $webPart.PSObject.TypeNames.Insert(0, $name) }
        return $webPart
    }

    function New-TestXmlContent {
        param ([string]$Xml)
        $document = [System.Xml.XmlDocument]::new()
        $document.LoadXml($Xml)
        return $document.DocumentElement
    }
}

Describe 'Get-SPSScriptWebPartKind' {
    It 'reports a Script Editor web part, whatever it holds' {
        Get-Kind -WebPart (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ScriptEditorWebPart' -Content '<script>alert(1)</script>') | Should -Be 'Script Editor'
        Get-Kind -WebPart (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ScriptEditorWebPart') | Should -Be 'Script Editor'
    }

    It 'reports a class derived from the Script Editor web part' {
        Get-Kind -WebPart (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ScriptEditorWebPart', 'Contoso.BrandedScriptPart') | Should -Be 'Script Editor'
    }

    It 'reports a Content Editor web part whose content has a script tag, as text' {
        $webPart = New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -Content '<div>Hello</div><script type="text/javascript">run();</script>'
        Get-Kind -WebPart $webPart | Should -Be 'Content Editor'
    }

    It 'reports a Content Editor web part whose content is an XML element, as text, CDATA or escaped markup' -ForEach @(
        @{ Xml = '<Content xmlns="http://schemas.microsoft.com/WebPart/v2/ContentEditor"><![CDATA[<script>run();</script>]]></Content>' }
        @{ Xml = '<Content xmlns="http://schemas.microsoft.com/WebPart/v2/ContentEditor">&lt;script src="/SiteAssets/app.js"&gt;&lt;/script&gt;</Content>' }
        @{ Xml = '<Content xmlns="http://schemas.microsoft.com/WebPart/v2/ContentEditor"><![CDATA[<SCRIPT >run();</SCRIPT>]]></Content>' }
        @{ Xml = '<Content xmlns="http://schemas.microsoft.com/WebPart/v2/ContentEditor"><![CDATA[<  script>run();</script>]]></Content>' }
        @{ Xml = '<Content xmlns="http://schemas.microsoft.com/WebPart/v2/ContentEditor"><div><script>run();</script></div></Content>' }
    ) {
        $webPart = New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -Content (New-TestXmlContent -Xml $Xml)
        Get-Kind -WebPart $webPart | Should -Be 'Content Editor'
    }

    It 'reports a Content Editor web part that links to a file, whatever its content' {
        $webPart = New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -ContentLink '/SiteAssets/banner.html'
        Get-Kind -WebPart $webPart | Should -Be 'Content Editor'
    }

    It 'does not report a Content Editor web part that holds only formatted text' {
        $text = New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -Content '<h1>Welcome</h1><p>Contact the <b>help desk</b>.</p>'
        Get-Kind -WebPart $text | Should -Be ''

        $xml = New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -Content (New-TestXmlContent -Xml '<Content xmlns="http://schemas.microsoft.com/WebPart/v2/ContentEditor"><![CDATA[<p>Hello</p>]]></Content>')
        Get-Kind -WebPart $xml | Should -Be ''

        $empty = New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart'
        Get-Kind -WebPart $empty | Should -Be ''
    }

    It 'does not take a word that merely contains script for a script tag' {
        $webPart = New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -Content '<p>The postscript and the scripts of the play.</p>'
        Get-Kind -WebPart $webPart | Should -Be ''

        $element = New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart' -Content '<scripture>Genesis</scripture>'
        Get-Kind -WebPart $element | Should -Be ''
    }

    It 'does not report any other web part' {
        Get-Kind -WebPart (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.XsltListViewWebPart', 'System.Web.UI.WebControls.WebParts.WebPart' -Content '<script>x</script>') | Should -Be ''
        Get-Kind -WebPart (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.PageViewerWebPart') | Should -Be ''
        Get-Kind -WebPart (New-TestWebPart -TypeName 'Contoso.ScriptEditorWebPart') | Should -Be ''
        Get-Kind -WebPart ([PSCustomObject]@{ Title = 'Plain' }) | Should -Be ''
    }

    It 'does not report a missing web part' {
        Get-Kind -WebPart $null | Should -Be ''
    }

    It 'rejects a Content Editor web part whose content cannot be read, instead of taking it for one without script' {
        $broken = [SPSTestBrokenContentPart]::new()
        $broken.PSObject.TypeNames.Insert(0, 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart')
        { Get-Kind -WebPart $broken } | Should -Throw '*content unavailable*'
    }

    It 'rejects a Content Editor web part whose link cannot be read' {
        $broken = [SPSTestBrokenLinkPart]::new()
        $broken.PSObject.TypeNames.Insert(0, 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart')
        { Get-Kind -WebPart $broken } | Should -Throw '*link unavailable*'
    }

    It 'returns text' {
        Get-Kind -WebPart (New-TestWebPart -TypeName 'Microsoft.SharePoint.WebPartPages.ScriptEditorWebPart') | Should -BeOfType [string]
        Get-Kind -WebPart $null | Should -BeOfType [string]
    }
}
