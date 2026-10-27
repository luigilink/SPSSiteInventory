function Get-SPSBcsApplication {
    <#
        .SYNOPSIS
        Lists the Business Connectivity Services (BCS) LOB systems defined in the farm.

        .DESCRIPTION
        BCS is retired in SharePoint Online (30 September 2024), so BCS applications cannot
        be migrated there: the LOB systems, their entities (external content types) and
        their instances (the connections that external lists use) need a replacement, for
        example with Power Apps. BCS is not retired in SharePoint Server Subscription
        Edition. The function reads the Business Data Connectivity (BDC) metadata store and
        returns one row per LOB system, like the SMAT BCS report: its name, type,
        instances and entities.

        The BDC service application of each web application is found through the service
        application proxy group of the web application and read through its proxy, for the
        default (non-tenant) partition. No site collection is needed, so a web application
        without any site collection is read too, and a web application whose proxy group has
        no BDC proxy simply has no BCS.

        Web applications that share a BDC service application are read once and reported
        once, with every web application that sees it. A store is identified by the ID of
        its BDC service application: the ID of a catalog only identifies an object inside
        one store, so two stores can share it. A web application, proxy or LOB system that
        cannot be read adds a warning and marks the result incomplete, so a failure is never
        reported as an empty store. No connection setting, credential or Secure Store
        target application is read, and the external systems are not contacted.

        The function is read-only.

        .PARAMETER WebApplicationUrl
        Optional list of web application URLs to read, like the same parameter of
        Get-SPSSiteInventory. When omitted, all content web applications are read.

        .OUTPUTS
        A PSCustomObject with Applications (one row per LOB system), Complete ($false when
        something could not be read) and Warnings (messages for the run log).

        .EXAMPLE
        $bcs = Get-SPSBcsApplication
        $bcs.Applications | Format-Table LobSystemName, LobSystemType, EntityCount

        .EXAMPLE
        Get-SPSBcsApplication -WebApplicationUrl 'https://intranet.contoso.com'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [System.String[]]
        $WebApplicationUrl = @()
    )

    $bdcProxyTypeName = 'Microsoft.SharePoint.BusinessData.SharedService.BdcServiceApplicationProxy'
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
        }
        catch {
            $complete = $false
            $warnings.Add("The BCS service application proxies could not be read for web application '$label': $($_.Exception.Message)")
            continue
        }

        foreach ($proxy in @($proxies | Where-Object { $null -ne $_ -and $_.PSObject.TypeNames -contains $bdcProxyTypeName })) {
            try {
                $serviceApplicationId = $proxy.GetServiceApplicationId()
                if ($null -eq $serviceApplicationId -or [guid]$serviceApplicationId -eq [guid]::Empty) {
                    throw 'The BDC service application ID could not be read.'
                }
                $storeId = ([guid]$serviceApplicationId).ToString()
                if ($stores.ContainsKey($storeId)) {
                    if (-not $stores[$storeId].WebApplications.Contains($label)) {
                        $stores[$storeId].WebApplications.Add($label)
                    }
                    continue
                }

                $catalog = $proxy.GetAdministrationMetadataCatalog()
                if ($null -eq $catalog) {
                    throw 'The metadata store is unavailable.'
                }
                $lobSystems = $catalog.GetLobSystems('*')
                if ($null -eq $lobSystems) {
                    throw 'The list of LOB systems is unavailable.'
                }
                $store = [PSCustomObject]@{
                    ServiceApplicationId = $storeId
                    WebApplications      = [System.Collections.Generic.List[string]]::new()
                    Rows                 = [System.Collections.Generic.List[object]]::new()
                }
                $store.WebApplications.Add($label)
                $stores[$storeId] = $store
                foreach ($lobSystem in $lobSystems) {
                    try {
                        $store.Rows.Add((ConvertTo-SPSBcsApplicationRecord -LobSystem $lobSystem))
                    }
                    catch {
                        $complete = $false
                        $warnings.Add("A BCS LOB system could not be read for web application '$label': $($_.Exception.Message)")
                    }
                }
            }
            catch {
                $complete = $false
                $warnings.Add("The BCS metadata store could not be read for web application '$label': $($_.Exception.Message)")
            }
        }
    }

    $applications = [System.Collections.Generic.List[object]]::new()
    foreach ($store in $stores.Values) {
        foreach ($row in @($store.Rows | Sort-Object -Property LobSystemName)) {
            $applications.Add([PSCustomObject]@{
                    WebApplicationUrls      = ($store.WebApplications -join '; ')
                    BdcServiceApplicationId = $store.ServiceApplicationId
                    LobSystemName           = $row.LobSystemName
                    LobSystemType           = $row.LobSystemType
                    LobSystemInstances      = $row.LobSystemInstances
                    EntityCount             = $row.EntityCount
                    LobEntities             = $row.LobEntities
                })
        }
    }

    [PSCustomObject]@{
        Applications = $applications.ToArray()
        Complete     = $complete
        Warnings     = $warnings.ToArray()
    }
}
