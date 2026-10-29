function Get-SPSProfilePropertyMapping {
    <#
        .SYNOPSIS
        Lists the profile property mappings of the User Profile service applications of the farm.

        .DESCRIPTION
        In the source farm, a profile property can be mapped to an attribute of a data source (Active
        Directory, or a Business Connectivity Services connection) so that the User Profile service fills it
        in, or exports it. SharePoint Online fills a fixed set of properties from Microsoft Entra ID and
        cannot be configured with other mappings: a value that the default properties do not carry has to be
        pushed into the profiles by a program of your own. The function returns one row per mapping, like the
        SMAT Custom Profile Property Mappings report: the connection and its type, the profile property with
        its display name and length, the attribute it is mapped to, the direction and the number of profiles
        that have a value for the property.

        Every mapping is listed, and the row says whether SharePoint Online fills the property
        (SynchronizedInSharePointOnline, from the fixed list that Microsoft documents) and whether it is one
        of the properties that SharePoint ships (BuiltInProperty, from PropertyConstants; empty when that
        list could not be read). The mappings of the default properties that SharePoint Online does not fill
        are in the report, as in SMAT (the Phonetic Search properties, for example): they need nothing unless
        something relies on them. A mapping of a property that SharePoint does not ship is a custom one.

        The User Profile service application of each web application is found through the service
        application proxy group of the web application, and read with the configuration manager of the
        service through the service context of that group, for the default (non-tenant) partition. No site
        collection is needed. Web applications that share a User Profile proxy are read once and reported
        once, with every web application that sees it. A service context binds the default User Profile
        proxy of its group, so a group that holds more than one marks the result incomplete: the others
        cannot be read. A web application, proxy or connection that cannot be read adds a warning and marks
        the result incomplete, so a failure is never reported as an empty service.

        The account that runs the inventory has to administer the User Profile service application (the farm
        account does): without the permission the connections cannot be read, and the result is incomplete.
        The number of profiles (PropertyUsage) is what UserProfileConfigManager.CountProfilesWithProperty
        returns, which the documentation does not describe further; it is left empty, with no effect on the
        completeness, when it cannot be read.

        The function is read-only: no profile is read, and no connection is contacted.

        .PARAMETER WebApplicationUrl
        Optional list of web application URLs to read, like the same parameter of
        Get-SPSSiteInventory. When omitted, all content web applications are read.

        .OUTPUTS
        A PSCustomObject with Mappings (one row per mapping), Complete ($false when something could not be
        read) and Warnings (messages for the run log).

        .EXAMPLE
        $profiles = Get-SPSProfilePropertyMapping
        $profiles.Mappings | Where-Object { -not $_.SynchronizedInSharePointOnline } | Format-Table ConnectionName, PropertyName, PropertyMapping

        .EXAMPLE
        Get-SPSProfilePropertyMapping -WebApplicationUrl 'https://intranet.contoso.com'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [System.String[]]
        $WebApplicationUrl = @()
    )

    $proxyTypeName = 'Microsoft.Office.Server.Administration.UserProfileApplicationProxy'
    $proxyDisplayName = 'User Profile Service Application Proxy'
    $warnings = [System.Collections.Generic.List[string]]::new()
    $complete = $true

    # Names are compared by their letters and digits, in lower case: 'Work Email' is WorkEmail, and SPS-SipAddress is SPSSipAddress.
    $toKey = { param ([System.String] $Name) ([System.Text.RegularExpressions.Regex]::Replace($Name, '[^A-Za-z0-9]', '')).ToLowerInvariant() }
    $onlineKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($onlineName in (Get-SPSOnlineProfilePropertyName)) {
        $null = $onlineKeys.Add((& $toKey $onlineName))
    }
    $builtInNames = Get-SPSBuiltInProfilePropertyName
    $builtInKeys = $null
    if ($null -ne $builtInNames) {
        $builtInKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($builtInName in $builtInNames) {
            $null = $builtInKeys.Add((& $toKey $builtInName))
        }
    }

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
        $profileProxies = @()
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
            $profileProxies = @($proxies | Where-Object { $null -ne $_ -and ($_.PSObject.TypeNames -contains $proxyTypeName -or [string]$_.TypeName -eq $proxyDisplayName) })
            $ids = [System.Collections.Generic.List[string]]::new()
            $names = [System.Collections.Generic.List[string]]::new()
            foreach ($profileProxy in $profileProxies) {
                $proxyId = Get-SPSPropertyValue -InputObject $profileProxy -Name 'Id'
                if ($null -eq $proxyId -or [guid]$proxyId -eq [guid]::Empty) {
                    throw 'The ID of a User Profile proxy could not be read.'
                }
                $ids.Add(([guid]$proxyId).ToString())
                $names.Add([string](Get-SPSPropertyValue -InputObject $profileProxy -Name 'Name'))
            }
            $storeId = (@($ids | Sort-Object) -join '; ')
            $storeName = (@($names | Sort-Object) -join '; ')
        }
        catch {
            $complete = $false
            $warnings.Add("The User Profile service application proxies could not be read for web application '$label': $($_.Exception.Message)")
            continue
        }

        if ($profileProxies.Count -eq 0) {
            continue
        }
        if ($stores.ContainsKey($storeId)) {
            if (-not $stores[$storeId].WebApplications.Contains($label)) {
                $stores[$storeId].WebApplications.Add($label)
            }
            continue
        }

        # The service is registered before it is read, so that a failure is reported once, not once per web application.
        $store = [PSCustomObject]@{
            ProxyId         = $storeId
            ProxyName       = $storeName
            WebApplications = [System.Collections.Generic.List[string]]::new()
            Rows            = [System.Collections.Generic.List[object]]::new()
        }
        $store.WebApplications.Add($label)
        $stores[$storeId] = $store

        try {
            if ($profileProxies.Count -gt 1) {
                $complete = $false
                $warnings.Add("Web application '$label' has $($profileProxies.Count) User Profile proxies in its service application proxy group: only the connections of the default one are read.")
            }
            $context = Get-SPSProxyGroupServiceContext -ProxyGroup $proxyGroup
            $manager = Get-SPSUserProfileConfigManager -ServiceContext $context
            # A collection is read directly: a function would enumerate it, and null means that the permission is missing.
            $connections = $manager.ConnectionManager
            if ($null -eq $connections) {
                throw 'The connections are unavailable: the account that runs the inventory has to administer the User Profile service application.'
            }
        }
        catch {
            $complete = $false
            $warnings.Add("The profile synchronization connections could not be read for web application '$label': $($_.Exception.Message)")
            continue
        }

        # The display name and the length of the properties come from their definitions; they are descriptive, so a failure leaves them empty.
        $definitions = @{}
        try {
            $coreProperties = $manager.ProfilePropertyManager.GetCoreProperties()
            if ($null -eq $coreProperties) {
                throw 'The property definitions are unavailable.'
            }
            foreach ($coreProperty in $coreProperties) {
                $definitions[[string](Get-SPSPropertyValue -InputObject $coreProperty -Name 'Name')] = [PSCustomObject]@{
                    DisplayName = [string](Get-SPSPropertyValue -InputObject $coreProperty -Name 'DisplayName')
                    Length      = Get-SPSPropertyValue -InputObject $coreProperty -Name 'Length'
                }
            }
        }
        catch {
            $definitions = @{}
            $warnings.Add("The profile property definitions could not be read for web application '$label', so the display names and the lengths of the properties are empty: $($_.Exception.Message)")
        }

        $usage = @{}
        foreach ($connection in $connections) {
            $connectionName = ''
            $connectionType = ''
            try {
                $connectionName = [string](Get-SPSPropertyValue -InputObject $connection -Name 'DisplayName')
                $connectionType = [string](Get-SPSPropertyValue -InputObject $connection -Name 'Type')
                $maps = @(Get-SPSConnectionPropertyMap -Connection $connection)
            }
            catch {
                $complete = $false
                $warnings.Add("The property mappings of a connection could not be read for web application '$label': $($_.Exception.Message)")
                continue
            }

            foreach ($map in $maps) {
                $propertyName = $map.ProfilePropertyName
                $definition = $definitions[$propertyName]
                $displayName = if ($null -ne $definition) { $definition.DisplayName } else { '' }
                $length = if ($null -ne $definition) { $definition.Length } else { $null }

                if (-not $usage.ContainsKey($propertyName)) {
                    $usage[$propertyName] = $null
                    try {
                        $usage[$propertyName] = [int]$manager.CountProfilesWithProperty($propertyName)
                    }
                    catch {
                        Write-Verbose -Message "The number of profiles with the property '$propertyName' could not be read: $($_.Exception.Message)"
                    }
                }

                $nameKey = & $toKey $propertyName
                $displayKey = & $toKey $displayName
                $synchronized = $onlineKeys.Contains($nameKey) -or ($displayKey.Length -gt 0 -and $onlineKeys.Contains($displayKey))
                $builtIn = $null
                if ($null -ne $builtInKeys) {
                    $builtIn = $builtInKeys.Contains($nameKey)
                }

                $store.Rows.Add([PSCustomObject]@{
                        ConnectionName                 = $connectionName
                        ConnectionType                 = $connectionType
                        PropertyName                   = $propertyName
                        PropertyDisplayName            = $displayName
                        PropertyMapping                = $map.DataSourcePropertyName
                        Direction                      = $map.Direction
                        PropertyLength                 = $length
                        PropertyUsage                  = $usage[$propertyName]
                        SynchronizedInSharePointOnline = $synchronized
                        BuiltInProperty                = $builtIn
                    })
            }
        }
    }

    $mappings = [System.Collections.Generic.List[object]]::new()
    foreach ($store in $stores.Values) {
        foreach ($row in @($store.Rows | Sort-Object -Property ConnectionName, PropertyName, Direction)) {
            $mappings.Add([PSCustomObject]@{
                    WebApplicationUrls             = ($store.WebApplications -join '; ')
                    UserProfileProxyName           = $store.ProxyName
                    UserProfileProxyId             = $store.ProxyId
                    ConnectionName                 = $row.ConnectionName
                    ConnectionType                 = $row.ConnectionType
                    PropertyName                   = $row.PropertyName
                    PropertyDisplayName            = $row.PropertyDisplayName
                    PropertyMapping                = $row.PropertyMapping
                    Direction                      = $row.Direction
                    PropertyLength                 = $row.PropertyLength
                    PropertyUsage                  = $row.PropertyUsage
                    SynchronizedInSharePointOnline = $row.SynchronizedInSharePointOnline
                    BuiltInProperty                = $row.BuiltInProperty
                })
        }
    }

    [PSCustomObject]@{
        Mappings = $mappings.ToArray()
        Complete = $complete
        Warnings = $warnings.ToArray()
    }
}
