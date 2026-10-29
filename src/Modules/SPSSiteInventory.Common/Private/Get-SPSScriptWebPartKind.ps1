function Get-SPSScriptWebPartKind {
    <#
        .SYNOPSIS
        Tells whether a web part is a Script Editor or a Content Editor web part that carries script.

        .DESCRIPTION
        The modern experience has no web part for custom script: the Script Editor web part and
        the Content Editor web part are classic-only, and the script they hold has to be rebuilt
        (a SharePoint Framework web part or extension). The function returns:

        - 'Script Editor' for a Script Editor web part, whatever it holds;
        - 'Content Editor' for a Content Editor web part that embeds a script tag in its content
          or links to a file (its ContentLink), which is usually a script or an HTML page. A Content
          Editor web part that holds only formatted text is not reported: the Text web part
          replaces it;
        - an empty string for any other web part.

        The web part is recognized by the full name of its class or of one of its base classes
        (Microsoft.SharePoint.WebPartPages.ScriptEditorWebPart and
        Microsoft.SharePoint.WebPartPages.ContentEditorWebPart), as PowerShell lists them in the
        type names of the object, so that nothing of SharePoint has to be loaded to ask. The
        properties of a Content Editor web part are read strictly: a getter that fails raises its
        exception, so that an unreadable web part is not taken for one without script.

        Private because it is an implementation detail of Get-SPSPageScriptWebPart.

        .PARAMETER WebPart
        A web part of SPLimitedWebPartManager.WebParts.

        .EXAMPLE
        Get-SPSScriptWebPartKind -WebPart $webPart
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $WebPart
    )

    if ($null -eq $WebPart) {
        return ''
    }

    $typeNames = @($WebPart.PSObject.TypeNames)
    if ($typeNames -contains 'Microsoft.SharePoint.WebPartPages.ScriptEditorWebPart') {
        return 'Script Editor'
    }
    if ($typeNames -notcontains 'Microsoft.SharePoint.WebPartPages.ContentEditorWebPart') {
        return ''
    }

    $contentLink = Get-SPSPropertyValue -InputObject $WebPart -Name 'ContentLink'
    if (-not [string]::IsNullOrWhiteSpace([string]$contentLink)) {
        return 'Content Editor'
    }

    # The content is an XML element that holds the HTML as text or as CDATA; both forms are searched.
    $content = Get-SPSPropertyValue -InputObject $WebPart -Name 'Content'
    $contentText = if ($content -is [System.Xml.XmlNode]) { '{0} {1}' -f $content.InnerText, $content.InnerXml } else { [string]$content }
    if ($contentText -match '(?i)(<|&lt;)\s*script\b') {
        return 'Content Editor'
    }

    return ''
}
