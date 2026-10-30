function Test-SPSXsltListView {
    <#
        .SYNOPSIS
        Tells whether a list view renders with a customized XSLT.

        .DESCRIPTION
        A list view that SharePoint draws with an XSL style sheet of its own, or with XSL kept in
        the view, is one of the usual reasons for a list to fall back to the classic experience: the
        modern list ignores the XSLT of its views. The view is customized when its Xsl is not
        empty, or when its XslLink is set to a style sheet that SharePoint does not ship.

        A bare file name is looked up in the XSL folder of SharePoint (/_layouts/15/xsl), which is why
        main.xsl, the default of every view, needs no path, and so is a path into that folder. The
        style sheets that are there ship with SharePoint: blog.xsl for the web parts of a blog and
        AssetPicker.xsl for the views of an asset library, for example. What a farm solution adds to
        that folder is reported with the farm solutions, not here. Any other value, such as a path in
        the Style Library or in the folder of a custom solution, is a style sheet of the farm.

        The caller leaves out the personal views and the hidden ones, which are the views that a web
        part keeps its settings in.

        The properties are read strictly: a getter that fails raises its exception, so that an
        unreadable view is not taken for one without XSLT. A property that the view does not have
        reads as empty.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER View
        An SPView of a list.

        .EXAMPLE
        Test-SPSXsltListView -View $list.Views[0]
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $View
    )

    $xslLink = ([string](Get-SPSPropertyValue -InputObject $View -Name 'XslLink')).Trim()
    $isShipped = $xslLink -notmatch '[/\\]' -or $xslLink -match '(^|[/\\])_layouts[/\\](\d+[/\\])?xsl[/\\][^/\\]+$'
    if ($xslLink -and -not $isShipped) {
        return $true
    }

    return -not [string]::IsNullOrWhiteSpace([string](Get-SPSPropertyValue -InputObject $View -Name 'Xsl'))
}
