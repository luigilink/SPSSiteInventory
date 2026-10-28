function Test-SPSCustomMasterPage {
    <#
        .SYNOPSIS
        Tells whether the master page of a web is a customization.

        .DESCRIPTION
        SharePoint provisions a few master pages in the master page gallery
        (/_catalogs/masterpage) of a site collection: seattle.master, the default since
        SharePoint 2013, oslo.master, v4.master, the master page of SharePoint 2010, and
        mysite15.master, which the My Site templates use (the My Site host and the personal
        sites). A web that uses one of them is not customized, so only another master page
        is reported.

        The URL is compared on its folder and its file name, not on a part of the text: a
        copy of seattle.master in another folder, or a master page whose name only contains
        one of these names (such as contoso-v4.master), is a customization. An empty URL is
        not: the web has no master page of its own.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Url
        The CustomMasterUrl of the web: a server-relative or an absolute URL.

        .EXAMPLE
        Test-SPSCustomMasterPage -Url '/_catalogs/masterpage/contoso.master'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Url
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $path = $Url.Trim().Replace('\', '/')
    $queryStart = $path.IndexOfAny([char[]]@('?', '#'))
    if ($queryStart -ge 0) {
        $path = $path.Substring(0, $queryStart)
    }

    return -not ($path -match '(^|/)_catalogs/masterpage/(seattle|oslo|v4|mysite15)\.master$')
}
