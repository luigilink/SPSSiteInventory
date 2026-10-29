function Get-SPSSecureStoreApplication {
    <#
        .SYNOPSIS
        Lists the Secure Store target applications defined in the farm.

        .DESCRIPTION
        The Secure Store Service stores credentials and maps them to the identity of a user or a
        group, for example for the external lists of Business Connectivity Services or the data
        connections of Excel Services. Secure Store applications are not migrated to SharePoint
        Online: the ones that are still needed have to be created again in the target, where the
        Group Restricted type is the only supported one. The function returns one row per target
        application, like the SMAT Secure Store report: its name, display name, contact e-mail
        address, type, credential management URL and ticket time-out. The fields of an application
        and the credentials are not read, and no external system is contacted.

        The Secure Store service application of each web application is found through the service
        application proxy group of the web application, and read with Get-SPSecureStoreApplication
        through the service context of that group, for the default (non-tenant) partition. No site
        collection is needed, so a web application without any site collection is read too, and a
        web application whose proxy group has no Secure Store proxy simply has no Secure Store.

        Web applications that share a Secure Store proxy are read once and reported once, with every
        web application that sees it. A service context binds the default Secure Store proxy of its
        group, so that proxy identifies the store: a group that holds several is read through its
        default one (SPServiceContext.GetDefaultProxy), and groups that hold the same proxies with
        other defaults are read once each. A proxy that is the default of no group that was read
        cannot be read: it marks the result incomplete, and so does a default that cannot be told. A
        web application, proxy or application that cannot be read adds a warning and marks the result
        incomplete, so a failure is never reported as an empty store. When no web application has a
        Secure Store proxy at all, the result stays complete and a warning says so: a farm without the
        Secure Store service has none, and a proxy type that is not recognized would look the same.

        The list holds the target applications that the account which runs the inventory can
        administer (or all of them when the account has the permission of a Secure Store service
        administrator), so run it with an administrator of the Secure Store service application: a
        smaller list than expected is not an error that the function can see.

        The function is read-only.

        .PARAMETER WebApplicationUrl
        Optional list of web application URLs to read, like the same parameter of
        Get-SPSSiteInventory. When omitted, all content web applications are read.

        .OUTPUTS
        A PSCustomObject with Applications (one row per target application), Complete ($false when
        something could not be read) and Warnings (messages for the run log).

        .EXAMPLE
        $secureStore = Get-SPSSecureStoreApplication
        $secureStore.Applications | Format-Table Name, FriendlyName, ApplicationType

        .EXAMPLE
        Get-SPSSecureStoreApplication -WebApplicationUrl 'https://intranet.contoso.com'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [System.String[]]
        $WebApplicationUrl = @()
    )

    $proxyTypeName = 'Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplicationProxy'
    $proxyDisplayName = 'Secure Store Service Application Proxy'
    $warnings = [System.Collections.Generic.List[string]]::new()
    $complete = $true

    # A web application that cannot be found is a warning, not the end of the report of the others.
    $webApplications = [System.Collections.Generic.List[object]]::new()
    if ($WebApplicationUrl.Count -gt 0) {
        foreach ($url in $WebApplicationUrl) {
            try {
                foreach ($resolved in @(Get-SPWebApplication -Identity $url -ErrorAction Stop)) {
                    $webApplications.Add($resolved)
                }
            }
            catch {
                $complete = $false
                $warnings.Add("The web application '$url' could not be read: $($_.Exception.Message)")
            }
        }
    }
    else {
        foreach ($resolved in @(Get-SPWebApplication -ErrorAction Stop)) {
            $webApplications.Add($resolved)
        }
    }

    $stores = [System.Collections.Generic.Dictionary[string, object]]::new()
    # Every Secure Store proxy of the groups that were read, and the ones that were read or that a warning accounts for.
    $seenProxies = [ordered]@{}
    $accountedProxyIds = [System.Collections.Generic.HashSet[string]]::new()
    $checkedWebApplicationCount = 0
    foreach ($webApplication in $webApplications) {
        $webApplicationText = [string]$webApplication.Url
        $isReadable = -not [string]::IsNullOrWhiteSpace($webApplicationText)
        $label = if ($isReadable) { $webApplicationText } else { '(unknown web application)' }

        $proxyGroup = $null
        $candidates = @()
        try {
            if (-not $isReadable) {
                throw 'The web application URL could not be read.'
            }
            $proxyGroup = $webApplication.ServiceApplicationProxyGroup
            if ($null -eq $proxyGroup) {
                throw 'The service application proxy group could not be read.'
            }
            $proxies = $proxyGroup.Proxies
            if ($null -eq $proxies) {
                throw 'The service application proxies could not be read.'
            }
            $found = [System.Collections.Generic.List[object]]::new()
            foreach ($secureStoreProxy in @($proxies | Where-Object { $null -ne $_ -and ($_.PSObject.TypeNames -contains $proxyTypeName -or [string]$_.TypeName -eq $proxyDisplayName) })) {
                $proxyId = Get-SPSPropertyValue -InputObject $secureStoreProxy -Name 'Id'
                if ($null -eq $proxyId -or [guid]$proxyId -eq [guid]::Empty) {
                    throw 'The ID of a Secure Store proxy could not be read.'
                }
                $found.Add([PSCustomObject]@{
                        Id    = ([guid]$proxyId).ToString()
                        Name  = [string](Get-SPSPropertyValue -InputObject $secureStoreProxy -Name 'Name')
                        Proxy = $secureStoreProxy
                    })
            }
            # The IDs and the names are listed in the same order, so that a name is the one of the ID beside it.
            $candidates = @($found | Sort-Object -Property Id)
        }
        catch {
            $complete = $false
            $warnings.Add("The Secure Store service application proxies could not be read for web application '$label': $($_.Exception.Message)")
            continue
        }

        $checkedWebApplicationCount++
        if ($candidates.Count -eq 0) {
            continue
        }
        foreach ($candidate in $candidates) {
            $seenProxies[$candidate.Id] = $candidate.Name
        }

        # A service context binds the default proxy of its group: it is the one that is read, and the one that identifies the store.
        $context = $null
        $contextFailed = $false
        $contextFailure = ''
        $bound = $null
        $unresolvedReason = ''
        if ($candidates.Count -eq 1) {
            $bound = $candidates[0]
        }
        else {
            try {
                $context = Get-SPSProxyGroupServiceContext -ProxyGroup $proxyGroup
            }
            catch {
                $contextFailed = $true
                $contextFailure = $_.Exception.Message
            }
            if ($null -ne $context) {
                try {
                    $bound = Resolve-SPSContextProxy -Candidate $candidates -ServiceContext $context
                    if ($null -eq $bound) {
                        $unresolvedReason = 'the service context has no default Secure Store proxy among them'
                    }
                }
                catch {
                    $unresolvedReason = $_.Exception.Message
                }
            }
        }

        if ($null -ne $bound) {
            $storeId = $bound.Id
            $storeName = $bound.Name
            $null = $accountedProxyIds.Add($bound.Id)
        }
        else {
            $storeId = (@($candidates | ForEach-Object { $_.Id }) -join '; ')
            $storeName = (@($candidates | ForEach-Object { $_.Name }) -join '; ')
            foreach ($candidate in $candidates) {
                $null = $accountedProxyIds.Add($candidate.Id)
            }
        }

        if ($stores.ContainsKey($storeId)) {
            if (-not $stores[$storeId].WebApplications.Contains($label)) {
                $stores[$storeId].WebApplications.Add($label)
            }
            continue
        }

        # The store is registered before it is read, so that a failure is reported once, not once per web application.
        $store = [PSCustomObject]@{
            ProxyId         = $storeId
            ProxyName       = $storeName
            WebApplications = [System.Collections.Generic.List[string]]::new()
            Rows            = [System.Collections.Generic.List[object]]::new()
        }
        $store.WebApplications.Add($label)
        $stores[$storeId] = $store

        try {
            if ($contextFailed) {
                throw $contextFailure
            }
            if ($null -eq $bound) {
                $complete = $false
                $warnings.Add("Web application '$label' has $($candidates.Count) Secure Store proxies in its service application proxy group and its default one could not be determined ($unresolvedReason): only the Secure Store applications of the default one are read.")
            }
            if ($null -eq $context) {
                $context = Get-SPSProxyGroupServiceContext -ProxyGroup $proxyGroup
            }
            $targetApplications = @(Get-SPSecureStoreApplication -ServiceContext $context -All -ErrorAction Stop)
        }
        catch {
            $complete = $false
            $warnings.Add("The Secure Store applications could not be read for web application '$label': $($_.Exception.Message)")
            continue
        }

        foreach ($targetApplication in $targetApplications) {
            if ($null -eq $targetApplication) {
                continue
            }
            try {
                $store.Rows.Add((ConvertTo-SPSSecureStoreApplicationRecord -Application $targetApplication))
            }
            catch {
                $complete = $false
                $warnings.Add("A Secure Store application could not be read for web application '$label': $($_.Exception.Message)")
            }
        }
    }

    foreach ($seenId in @($seenProxies.Keys)) {
        if (-not $accountedProxyIds.Contains($seenId)) {
            $complete = $false
            $warnings.Add("The Secure Store proxy '$($seenProxies[$seenId])' ($seenId) is not the default Secure Store proxy of the service application proxy group of any web application that was read, so its target applications are not read.")
        }
    }
    # A farm without the Secure Store service has no proxy, and so has a farm whose proxy type is not recognized: the run log tells which one to check.
    if ($checkedWebApplicationCount -gt 0 -and $seenProxies.Count -eq 0) {
        $warnings.Add("No Secure Store service application proxy was found in the service application proxy group of the $checkedWebApplicationCount web application(s) that were read, so no Secure Store application is reported. A farm without the Secure Store service has none: otherwise check the service application proxies of the web applications.")
    }

    $applications = [System.Collections.Generic.List[object]]::new()
    foreach ($store in $stores.Values) {
        foreach ($row in @($store.Rows | Sort-Object -Property Name)) {
            $applications.Add([PSCustomObject]@{
                    WebApplicationUrls      = ($store.WebApplications -join '; ')
                    SecureStoreProxyName    = $store.ProxyName
                    SecureStoreProxyId      = $store.ProxyId
                    Name                    = $row.Name
                    FriendlyName            = $row.FriendlyName
                    ContactEmail            = $row.ContactEmail
                    ApplicationType         = $row.ApplicationType
                    CredentialManagementUrl = $row.CredentialManagementUrl
                    TicketTimeoutMinutes    = $row.TicketTimeoutMinutes
                })
        }
    }

    [PSCustomObject]@{
        Applications = $applications.ToArray()
        Complete     = $complete
        Warnings     = $warnings.ToArray()
    }
}
