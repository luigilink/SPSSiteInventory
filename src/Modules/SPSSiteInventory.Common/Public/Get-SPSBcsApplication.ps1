function Get-SPSBcsApplication {
    <#
        .SYNOPSIS
        Lists the Business Connectivity Services (BCS) LOB systems defined in the farm.

        .DESCRIPTION
        BCS is retired in SharePoint Online (30 September 2024), so BCS applications cannot
        be migrated there: the LOB systems, their entities (external content types) and
        their instances (the connections that external lists use) need a replacement, for
        example with Power Apps. BCS is not retired in SharePoint Server Subscription
        Edition. The function reads the Business Data Connectivity metadata
        store and returns one row per LOB system, like the SMAT BCS report: its name, type,
        instances and entities.

        Each web application is read through its own default service context, so a web
        application without any site collection is read too. Web applications that share a
        metadata store return the same LOB systems; they are reported once, with every web
        application that sees them. A web application or LOB system that cannot be read adds
        a warning and marks the result incomplete, so a failure is never reported as an
        empty store. No connection setting, credential or Secure Store target application
        is read, and the external systems are not contacted.

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
            $serviceContext = Get-SPSWebApplicationServiceContext -WebApplication $webApplication
            $catalog = Get-SPBusinessDataCatalogMetadataObject -BdcObjectType Catalog -ServiceContext $serviceContext -ErrorAction Stop
            if ($null -eq $catalog) {
                throw 'The metadata store is unavailable.'
            }
            $storeId = [string](Get-SPSPropertyValue -InputObject $catalog -Name 'Id')
            if ([string]::IsNullOrWhiteSpace($storeId)) {
                throw 'The metadata store has no readable ID.'
            }
            if ($stores.ContainsKey($storeId)) {
                $stores[$storeId].WebApplications.Add($label)
                continue
            }

            $lobSystems = $catalog.GetLobSystems('*')
            if ($null -eq $lobSystems) {
                throw 'The list of LOB systems is unavailable.'
            }
            $store = [PSCustomObject]@{
                WebApplications = [System.Collections.Generic.List[string]]::new()
                Rows            = [System.Collections.Generic.List[object]]::new()
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

    $applications = [System.Collections.Generic.List[object]]::new()
    foreach ($store in $stores.Values) {
        foreach ($row in @($store.Rows | Sort-Object -Property LobSystemName)) {
            $applications.Add([PSCustomObject]@{
                    WebApplicationUrls = ($store.WebApplications -join '; ')
                    LobSystemName      = $row.LobSystemName
                    LobSystemType      = $row.LobSystemType
                    LobSystemInstances = $row.LobSystemInstances
                    EntityCount        = $row.EntityCount
                    LobEntities        = $row.LobEntities
                })
        }
    }

    [PSCustomObject]@{
        Applications = $applications.ToArray()
        Complete     = $complete
        Warnings     = $warnings.ToArray()
    }
}
