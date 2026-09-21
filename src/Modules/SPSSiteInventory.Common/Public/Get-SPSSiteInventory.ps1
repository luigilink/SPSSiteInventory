function Get-SPSSiteInventory {
    <#
        .SYNOPSIS
        Enumerates SharePoint site collections and returns their identity and volumetry.

        .DESCRIPTION
        Walks the requested web applications (or all content web applications when none
        is specified) and returns one record per site collection with the fields that
        drive the migration plan: URL, title, content database, root-web template, size,
        sub-web count and last activity date.

        This collector deliberately returns only volumetry and identity. The
        customization signals that feed the complexity score are collected separately by
        Get-SPSSiteCustomization, so a fast "identity + size" pass can run on its own.

        Requires the SharePoint commands (see Import-SPSSharePointCommand) and to run as
        the farm account on a farm server.

        .PARAMETER WebApplicationUrl
        Optional list of web application URLs to limit the scan. When omitted, all
        content web applications are scanned.

        .EXAMPLE
        Get-SPSSiteInventory

        .EXAMPLE
        Get-SPSSiteInventory -WebApplicationUrl 'https://intranet.contoso.com'
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter()]
        [System.String[]]
        $WebApplicationUrl = @()
    )

    $webApps = if ($WebApplicationUrl.Count -gt 0) {
        $WebApplicationUrl | ForEach-Object { Get-SPWebApplication -Identity $_ -ErrorAction Stop }
    }
    else {
        Get-SPWebApplication -ErrorAction Stop
    }

    $inventory = foreach ($webApp in $webApps) {
        foreach ($site in $webApp.Sites) {
            try {
                $rootWeb = $site.RootWeb
                [PSCustomObject]@{
                    Url          = $site.Url
                    Title        = $rootWeb.Title
                    WebApp       = $webApp.Name
                    ContentDb    = $site.ContentDatabase.Name
                    Template     = ('{0}#{1}' -f $rootWeb.WebTemplate, $rootWeb.Configuration)
                    SizeGB       = [math]::Round($site.Usage.Storage / 1GB, 2)
                    SubWebCount  = $site.AllWebs.Count
                    LastModified = $rootWeb.LastItemModifiedDate
                }
                $rootWeb.Dispose()
            }
            catch {
                Write-Warning -Message "Failed to inventory site '$($site.Url)': $($_.Exception.Message)"
            }
            finally {
                $site.Dispose()
            }
        }
    }

    return @($inventory)
}
