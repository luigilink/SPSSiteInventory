function Get-SPSSiteExclusionReason {
    <#
        .SYNOPSIS
        Says whether a site collection is left out of the inventory by the Scope settings.

        .DESCRIPTION
        Returns 'SiteMaster', 'PersonalSite' or $null (the site stays in the scan).

        A site master is a hidden site collection that SharePoint creates to speed up the
        creation of personal sites. It is recognized by its host name, which is
        sitemaster- followed by a GUID, so it can be skipped before it is opened. It also has
        the personal site template, but it is governed only by IncludeSiteMaster, never by
        IncludePersonalSite.

        A personal site (My Site) is recognized by the template of its root web, SPSPERS
        followed by # and a configuration number. The My Site host (SPSMSITEHOST) is a real
        site and is not a personal site. The template needs no User Profile Service
        application and also finds the personal sites whose profile is gone.

        A URL or a template that is empty or unknown never excludes anything, so a site whose
        root web cannot be read stays in the scan.

        Private because it is an implementation detail of the site enumeration. It is a pure
        function so that the rules can be tested without a farm.

        .PARAMETER Url
        The URL of the site collection.

        .PARAMETER Template
        The template of the root web, as WebTemplate#Configuration (for example SPSPERS#10).

        .PARAMETER IncludePersonalSite
        Keeps the personal sites. Defaults to $false.

        .PARAMETER IncludeSiteMaster
        Keeps the site masters. Defaults to $false.

        .EXAMPLE
        Get-SPSSiteExclusionReason -Url 'https://mysite.contoso.com/personal/user' -Template 'SPSPERS#10'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Url = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Template = '',

        [Parameter()]
        [System.Boolean]
        $IncludePersonalSite = $false,

        [Parameter()]
        [System.Boolean]
        $IncludeSiteMaster = $false
    )

    $siteMasterHost = '^(?:[a-z][a-z0-9+.\-]*://)?sitemaster-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?::[0-9]+)?(?:[/?#].*)?$'
    if (-not [string]::IsNullOrWhiteSpace($Url) -and $Url.Trim() -match $siteMasterHost) {
        if ($IncludeSiteMaster) {
            return $null
        }
        return 'SiteMaster'
    }

    if (-not $IncludePersonalSite -and
        -not [string]::IsNullOrWhiteSpace($Template) -and
        $Template.Trim() -match '^SPSPERS(?:#|$)') {
        return 'PersonalSite'
    }

    return $null
}
