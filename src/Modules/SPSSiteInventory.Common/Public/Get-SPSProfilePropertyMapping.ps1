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
        of the properties that SharePoint ships (BuiltInProperty, from PropertyConstants). A property is
        identified by its internal name, in any case, and never by its display name, which anybody can give to
        a property of their own. The mappings of the default properties that SharePoint Online does not fill
        are in the report, as in SMAT (the Phonetic Search properties, for example): they need nothing unless
        something relies on them. A mapping of a property that SharePoint does not ship is a custom one. When
        the list of the properties that SharePoint ships cannot be read, BuiltInProperty is empty, the result
        is incomplete, and a warning says that every mapping of a property that SharePoint Online does not
        fill is reported as a possible custom one.

        The User Profile service application of each web application is found through the service
        application proxy group of the web application, and read with the configuration manager of the
        service through the service context of that group, for the default (non-tenant) partition. No site
        collection is needed. Web applications that share a User Profile proxy are read once and reported
        once, with every web application that sees it. A service context binds the default User Profile
        proxy of its group, so that proxy identifies the service: a group that holds several is read through
        its default one (SPServiceContext.GetDefaultProxy), and groups that hold the same proxies with other
        defaults are read once each. A proxy that is the default of no group that was read cannot be read:
        it marks the result incomplete, and so does a default that cannot be told. A web application, proxy
        or connection that cannot be read adds a warning and marks the result incomplete, so a failure is
        never reported as an empty service. When no web application has a User Profile proxy at all, the
        result stays complete and a warning says so: a farm without the User Profile service has none, and a
        proxy type that is not recognized would look the same.

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

    # A property is identified by its internal name, which SharePoint compares without regard to the case. A display name is a label that
    # anybody can give to a property of their own, so it never makes a property one that SharePoint Online fills.
    $onlineNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($onlineName in (Get-SPSOnlineProfilePropertyName)) {
        $null = $onlineNames.Add($onlineName)
    }
    $builtInList = Get-SPSBuiltInProfilePropertyName
    $builtInNames = $null
    if ($null -ne $builtInList) {
        $builtInNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($builtInName in $builtInList) {
            $null = $builtInNames.Add($builtInName)
        }
    }
    else {
        # Without that list a mapping of a property that SharePoint Online does not fill can be a default one or a custom one: it is not
        # told, so the result is incomplete and the rows have no BuiltInProperty.
        $complete = $false
        $warnings.Add('The list of the profile properties that SharePoint ships (PropertyConstants) could not be read, so BuiltInProperty is empty and every mapping of a property that SharePoint Online does not fill is reported as a possible custom one.')
    }

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
    # Every User Profile proxy of the groups that were read, and the ones that were read or that a warning accounts for.
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
            foreach ($profileProxy in @($proxies | Where-Object { $null -ne $_ -and ($_.PSObject.TypeNames -contains $proxyTypeName -or [string]$_.TypeName -eq $proxyDisplayName) })) {
                $proxyId = Get-SPSPropertyValue -InputObject $profileProxy -Name 'Id'
                if ($null -eq $proxyId -or [guid]$proxyId -eq [guid]::Empty) {
                    throw 'The ID of a User Profile proxy could not be read.'
                }
                $found.Add([PSCustomObject]@{
                        Id    = ([guid]$proxyId).ToString()
                        Name  = [string](Get-SPSPropertyValue -InputObject $profileProxy -Name 'Name')
                        Proxy = $profileProxy
                    })
            }
            # The IDs and the names are listed in the same order, so that a name is the one of the ID beside it.
            $candidates = @($found | Sort-Object -Property Id)
        }
        catch {
            $complete = $false
            $warnings.Add("The User Profile service application proxies could not be read for web application '$label': $($_.Exception.Message)")
            continue
        }

        $checkedWebApplicationCount++
        if ($candidates.Count -eq 0) {
            continue
        }
        foreach ($candidate in $candidates) {
            $seenProxies[$candidate.Id] = $candidate.Name
        }

        # A service context binds the default proxy of its group: it is the one that is read, and the one that identifies the service.
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
                        $unresolvedReason = 'the service context has no default User Profile proxy among them'
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
            if ($contextFailed) {
                throw $contextFailure
            }
            if ($null -eq $bound) {
                $complete = $false
                $warnings.Add("Web application '$label' has $($candidates.Count) User Profile proxies in its service application proxy group and its default one could not be determined ($unresolvedReason): only the connections of the default one are read.")
            }
            if ($null -eq $context) {
                $context = Get-SPSProxyGroupServiceContext -ProxyGroup $proxyGroup
            }
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

                $synchronized = $onlineNames.Contains($propertyName)
                $builtIn = $null
                if ($null -ne $builtInNames) {
                    $builtIn = $builtInNames.Contains($propertyName)
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

    foreach ($seenId in @($seenProxies.Keys)) {
        if (-not $accountedProxyIds.Contains($seenId)) {
            $complete = $false
            $warnings.Add("The User Profile proxy '$($seenProxies[$seenId])' ($seenId) is not the default User Profile proxy of the service application proxy group of any web application that was read, so its connections are not read.")
        }
    }
    # A farm without the User Profile service has no proxy, and so has a farm whose proxy type is not recognized: the run log tells which one to check.
    if ($checkedWebApplicationCount -gt 0 -and $seenProxies.Count -eq 0) {
        $warnings.Add("No User Profile service application proxy was found in the service application proxy group of the $checkedWebApplicationCount web application(s) that were read, so no profile property mapping is reported. A farm without the User Profile service has none: otherwise check the service application proxies of the web applications.")
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
