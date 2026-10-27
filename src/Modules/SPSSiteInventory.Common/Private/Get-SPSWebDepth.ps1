function Get-SPSWebDepth {
    <#
        .SYNOPSIS
        Returns how many levels a web is below the root web of its site collection.

        .DESCRIPTION
        Compares the URL of the web with the URL of the site collection: the depth is 0 for the
        root web, 1 for a web directly below it, 2 for a web below that one, and so on. The
        comparison ignores case and a trailing slash. RelativeUrl is the part of the URL of
        the web that is below the root web, for example 'hr/payroll'.

        The scheme, the host and the port must be the same, so that the same path on another host
        is not taken for a subsite. Returns $null when a URL cannot be read or when the web is not
        below the site collection, so that the caller can mark its inventory partial instead of
        counting a wrong depth.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER SiteUrl
        The absolute URL of the site collection, for example https://intranet/sites/hr.

        .PARAMETER WebUrl
        The absolute URL of the web, for example https://intranet/sites/hr/payroll/2026.

        .EXAMPLE
        Get-SPSWebDepth -SiteUrl 'https://intranet/sites/hr' -WebUrl 'https://intranet/sites/hr/payroll/2026'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $SiteUrl,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $WebUrl
    )

    $separator = [System.Char[]]@('/')
    try {
        $siteUri = [System.Uri]$SiteUrl
        $webUri = [System.Uri]$WebUrl
        $siteSegment = @($siteUri.AbsolutePath.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries))
        $webSegment = @($webUri.AbsolutePath.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries))
        # The same path on another host or port, or with another scheme, is not below the site collection.
        # Uri.Port is the default port of the scheme when none is given, so https://host and https://host:443 are the same.
        if ($siteUri.Scheme -ne $webUri.Scheme -or
            $siteUri.Port -ne $webUri.Port -or
            -not [System.String]::Equals($siteUri.Host, $webUri.Host, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
    }
    catch {
        return $null
    }

    if ($webSegment.Count -lt $siteSegment.Count) {
        return $null
    }
    for ($index = 0; $index -lt $siteSegment.Count; $index++) {
        if (-not [System.String]::Equals($siteSegment[$index], $webSegment[$index], [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
    }

    $relativeSegment = @($webSegment | Select-Object -Skip $siteSegment.Count | ForEach-Object { [System.Uri]::UnescapeDataString($_) })
    return [PSCustomObject]@{
        Depth       = $relativeSegment.Count
        RelativeUrl = ($relativeSegment -join '/')
    }
}
