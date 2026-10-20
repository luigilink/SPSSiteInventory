function Get-SPSSiteInventory {
    <#
        .SYNOPSIS
        Enumerates SharePoint site collections and returns their identity and volumetry.

        .DESCRIPTION
        Walks the requested web applications (or all content web applications when none
        is specified) and returns one record per site collection with the fields that
        drive the migration plan: URL, title, content database, root-web template, size,
        sub-web count and last activity date. Progress is displayed as sites are visited.
        Individual metadata failures are returned as partial records with warning details.

        This collector returns volumetry, identity and authentication configuration
        across every web application zone. FBA configured
        on any zone is surfaced on every collection in that web application; this does
        not measure actual sign-in usage. Authentication read errors stop collection.
        Customization signals that feed the complexity score are collected separately by
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

    $inventory = [System.Collections.Generic.List[object]]::new()
    foreach ($webApp in $webApps) {
        $authentication = Get-SPSWebApplicationAuthentication -WebApplication $webApp
        Write-Progress -Id 1 -Activity 'Enumerating site collections' -Status "Opening the site collection list for $($webApp.Url)" -PercentComplete 0
        Add-SPSInventoryEvent -Message "Starting site collection enumeration for web application '$($webApp.Url)'." -Level Information | Out-Host
        $addEnumerationFailure = {
            param ([string]$Message)
            $null = $inventory.Add([PSCustomObject]@{
                InventoryScope = 'WebApplication'
                Url = [string]$webApp.Url
                Title = 'Site collection enumeration failed'
                WebApp = $webApp.Name
                WebAppUrl = [string]$webApp.Url
                AuthenticationModes = $authentication.AuthenticationModes
                AuthenticationZones = $authentication.AuthenticationZones
                FbaMembershipProviders = $authentication.FbaMembershipProviders
                FbaRoleProviders = $authentication.FbaRoleProviders
                HasFbaZone = $authentication.HasFbaZone
                AuthenticationReviewRequired = $authentication.AuthenticationReviewRequired
                ContentDb = ''
                Template = ''
                SizeGB = $null
                SubWebCount = $null
                LastModified = $null
                SiteInventoryComplete = $false
                SiteInventoryWarnings = $Message
            })
        }
        try {
            $sites = $webApp.Sites
            if ($null -eq $sites) {
                throw "The site collection list is unavailable for web application '$($webApp.Url)'."
            }
        }
        catch {
            $failureMessage = "Site collection list could not be accessed: $($_.Exception.Message)"
            $null = Add-SPSInventoryEvent -Message "Could not access site collections for web application '$($webApp.Url)': $failureMessage" -Level Warning
            & $addEnumerationFailure $failureMessage
            Write-Progress -Id 1 -Activity 'Enumerating site collections' -Completed
            continue
        }

        $siteCount = $null
        try {
            $siteCount = [int]$sites.Count
        }
        catch {
            $null = Add-SPSInventoryEvent -Message "Could not determine the site count for web application '$($webApp.Url)'; progress will show an unknown total. $($_.Exception.Message)" -Level Warning
        }

        $siteIndex = 0
        try {
            foreach ($site in $sites) {
                $siteIndex++
                $siteUrl = ''
                $warnings = [System.Collections.Generic.List[string]]::new()
                try {
                    $siteUrl = [string]$site.Url
                }
                catch {
                    $warnings.Add("Site URL could not be read: $($_.Exception.Message)")
                }

                $progressStatus = if ($null -ne $siteCount) {
                    '{0}/{1}: {2}' -f $siteIndex, $siteCount, $siteUrl
                }
                else {
                    'Site {0} (total unknown): {1}' -f $siteIndex, $siteUrl
                }
                $percentComplete = if ($null -ne $siteCount -and $siteCount -gt 0) {
                    [int](($siteIndex / $siteCount) * 100)
                }
                else {
                    0
                }
                Write-Progress -Id 1 -Activity "Enumerating site collections in $($webApp.Url)" -Status $progressStatus -PercentComplete $percentComplete

                if ($siteIndex -eq 1 -or $siteIndex % 10 -eq 0 -or
                    ($null -ne $siteCount -and $siteIndex -eq $siteCount)) {
                    Add-SPSInventoryEvent -Message "Enumerating site collections in '$($webApp.Url)' ($progressStatus)." -Level Information | Out-Host
                }

                $rootWeb = $null
                $record = [ordered]@{
                    InventoryScope = 'SiteCollection'
                    Url = $siteUrl
                    Title = ''
                    WebApp = $webApp.Name
                    WebAppUrl = [string]$webApp.Url
                    AuthenticationModes = $authentication.AuthenticationModes
                    AuthenticationZones = $authentication.AuthenticationZones
                    FbaMembershipProviders = $authentication.FbaMembershipProviders
                    FbaRoleProviders = $authentication.FbaRoleProviders
                    HasFbaZone = $authentication.HasFbaZone
                    AuthenticationReviewRequired = $authentication.AuthenticationReviewRequired
                    ContentDb = ''
                    Template = ''
                    SizeGB = $null
                    SubWebCount = $null
                    LastModified = $null
                    SiteInventoryComplete = $true
                    SiteInventoryWarnings = ''
                }

                try {
                    try {
                        $rootWeb = $site.RootWeb
                        if ($null -eq $rootWeb) {
                            throw "The root web is unavailable."
                        }
                        $record.Title = $rootWeb.Title
                        $record.Template = '{0}#{1}' -f $rootWeb.WebTemplate, $rootWeb.Configuration
                        $record.LastModified = $rootWeb.LastItemModifiedDate
                    }
                    catch {
                        $warnings.Add("Root web metadata could not be fully read: $($_.Exception.Message)")
                    }

                    try {
                        $record.ContentDb = $site.ContentDatabase.Name
                    }
                    catch {
                        $warnings.Add("Content database could not be read: $($_.Exception.Message)")
                    }

                    try {
                        $record.SizeGB = [math]::Round($site.Usage.Storage / 1GB, 2)
                    }
                    catch {
                        $warnings.Add("Storage usage could not be read: $($_.Exception.Message)")
                    }

                    try {
                        $siteWebs = $site.AllWebs
                        if ($null -eq $siteWebs) {
                            throw "The web collection is unavailable."
                        }
                        $record.SubWebCount = $siteWebs.Count
                    }
                    catch {
                        $warnings.Add("Sub-web count could not be read: $($_.Exception.Message)")
                    }
                }
                finally {
                    if ($null -ne $rootWeb) {
                        try {
                            $rootWeb.Dispose()
                        }
                        catch {
                            $warnings.Add("Root web disposal failed: $($_.Exception.Message)")
                        }
                    }
                    try {
                        $site.Dispose()
                    }
                    catch {
                        $warnings.Add("Site collection disposal failed: $($_.Exception.Message)")
                    }
                }

                $record.SiteInventoryComplete = ($warnings.Count -eq 0)
                $record.SiteInventoryWarnings = $warnings -join '; '
                if (-not $record.SiteInventoryComplete) {
                    $null = Add-SPSInventoryEvent -Message "Site inventory is partial for '$siteUrl': $($record.SiteInventoryWarnings)" -Level Warning
                }
                $inventory.Add([PSCustomObject]$record)
            }
        }
        catch {
            $failureMessage = "Site collection enumeration stopped early after $siteIndex site collection(s): $($_.Exception.Message)"
            $null = Add-SPSInventoryEvent -Message "Site enumeration stopped early for web application '$($webApp.Url)': $failureMessage" -Level Warning
            & $addEnumerationFailure $failureMessage
        }
        finally {
            Write-Progress -Id 1 -Activity "Enumerating site collections in $($webApp.Url)" -Completed
        }
    }

    return $inventory.ToArray()
}
