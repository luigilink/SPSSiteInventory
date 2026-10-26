function ConvertTo-SPSPageLayoutIdentity {
    <#
        .SYNOPSIS
        Turns a Page Layout column value into a normalized identity.

        .DESCRIPTION
        The PublishingPageLayout column is a URL column that stores "url, description".
        Only the URL identifies the layout. It is normalized (absolute URLs reduced to
        their path, URL escapes decoded, backslashes and repeated slashes collapsed,
        leading slash enforced) so the same layout always yields the same Key whatever
        form SharePoint stored. Two layouts that share a file name in different Master
        Page Gallery folders keep different keys.

        Name is the path below the Master Page Gallery (for example
        'BrandA/Article.aspx'), which keeps the display short but unambiguous. Returns
        $null when the value holds no URL.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER LayoutValue
        The raw Page Layout column value.

        .EXAMPLE
        ConvertTo-SPSPageLayoutIdentity -LayoutValue '/_catalogs/masterpage/ArticleLeft.aspx, Article Left'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $LayoutValue
    )

    $text = [string]$LayoutValue
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $path = ($text -split ',\s', 2)[0].Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $null
    }

    $uri = $null
    if ($path -match '^[a-zA-Z][a-zA-Z0-9+.-]*://' -and [System.Uri]::TryCreate($path, [System.UriKind]::Absolute, [ref]$uri)) {
        $path = $uri.AbsolutePath
    }
    $path = [System.Uri]::UnescapeDataString($path).Replace('\', '/') -replace '/{2,}', '/'
    if (-not $path.StartsWith('/')) {
        $path = '/' + $path
    }

    $galleryMarker = '/_catalogs/masterpage/'
    $markerIndex = $path.IndexOf($galleryMarker, [System.StringComparison]::OrdinalIgnoreCase)
    $name = if ($markerIndex -ge 0) { $path.Substring($markerIndex + $galleryMarker.Length) } else { $path }

    return [PSCustomObject]@{
        Key  = $path
        Name = $name
    }
}
