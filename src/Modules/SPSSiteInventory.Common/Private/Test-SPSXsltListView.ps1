function Test-SPSXsltListView {
    <#
        .SYNOPSIS
        Tells whether a list view renders with a customized XSLT.

        .DESCRIPTION
        A list view that SharePoint draws with an XSL style sheet of its own, or with XSL kept in
        the view, is one of the usual reasons for a list to fall back to the classic experience: the
        modern list ignores the XSLT of its views. The view is customized when its XslLink is set
        to a style sheet other than main.xsl, the default of every view, or when its Xsl is not
        empty.

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
    if ($xslLink -and $xslLink -ne 'main.xsl') {
        return $true
    }

    return -not [string]::IsNullOrWhiteSpace([string](Get-SPSPropertyValue -InputObject $View -Name 'Xsl'))
}
