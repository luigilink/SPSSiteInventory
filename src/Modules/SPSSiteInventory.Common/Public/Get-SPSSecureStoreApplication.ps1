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
        group, so a group that holds more than one Secure Store proxy marks the result incomplete: the
        applications of the others cannot be read. A web application, proxy or application that
        cannot be read adds a warning and marks the result incomplete, so a failure is never reported
        as an empty store.

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

    $webApplications = if ($WebApplicationUrl.Count -gt 0) {
        $WebApplicationUrl | ForEach-Object { Get-SPWebApplication -Identity $_ -ErrorAction Stop }
    }
    else {
        Get-SPWebApplication -ErrorAction Stop
    }

    $stores = [System.Collections.Generic.Dictionary[string, object]]::new()
    foreach ($webApplication in @($webApplications)) {
        $webApplicationText = [string]$webApplication.Url
        $isReadable = -not [string]::IsNullOrWhiteSpace($webApplicationText)
        $label = if ($isReadable) { $webApplicationText } else { '(unknown web application)' }

        $proxyGroup = $null
        $secureStoreProxies = @()
        $storeId = ''
        $storeName = ''
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
            $secureStoreProxies = @($proxies | Where-Object { $null -ne $_ -and ($_.PSObject.TypeNames -contains $proxyTypeName -or [string]$_.TypeName -eq $proxyDisplayName) })
            $ids = [System.Collections.Generic.List[string]]::new()
            $names = [System.Collections.Generic.List[string]]::new()
            foreach ($secureStoreProxy in $secureStoreProxies) {
                $proxyId = Get-SPSPropertyValue -InputObject $secureStoreProxy -Name 'Id'
                if ($null -eq $proxyId -or [guid]$proxyId -eq [guid]::Empty) {
                    throw 'The ID of a Secure Store proxy could not be read.'
                }
                $ids.Add(([guid]$proxyId).ToString())
                $names.Add([string](Get-SPSPropertyValue -InputObject $secureStoreProxy -Name 'Name'))
            }
            $storeId = (@($ids | Sort-Object) -join '; ')
            $storeName = (@($names | Sort-Object) -join '; ')
        }
        catch {
            $complete = $false
            $warnings.Add("The Secure Store service application proxies could not be read for web application '$label': $($_.Exception.Message)")
            continue
        }

        if ($secureStoreProxies.Count -eq 0) {
            continue
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
            if ($secureStoreProxies.Count -gt 1) {
                $complete = $false
                $warnings.Add("Web application '$label' has $($secureStoreProxies.Count) Secure Store proxies in its service application proxy group: only the Secure Store applications of the default one are read.")
            }
            $context = Get-SPSProxyGroupServiceContext -ProxyGroup $proxyGroup
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
