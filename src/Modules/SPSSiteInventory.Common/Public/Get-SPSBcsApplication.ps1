function Get-SPSBcsApplication {
    <#
        .SYNOPSIS
        Lists the Business Connectivity Services (BCS) LOB systems defined in the farm.

        .DESCRIPTION
        BCS applications are not migrated to SharePoint Online. The LOB systems, their
        entities (external content types) and their instances (the connections that
        external lists use) must be redeployed or replaced, for example with a hybrid BCS
        configuration, and the solutions that rely on them tested afterwards. The function
        reads the Business Data Connectivity metadata store and returns one row per LOB
        system, like the SMAT BCS report: its name, type, instances and entities.

        A service context needs a site collection, so the first site collection of each
        web application in the inventory is used. Web applications that share a metadata
        store return the same LOB systems; they are reported once, with every web
        application that sees them. A web application or LOB system that cannot be read
        adds a warning and marks the result incomplete, so a failure is never reported as
        an empty store. No connection setting, credential or Secure Store target
        application is read, and the external systems are not contacted.

        The function is read-only.

        .PARAMETER Inventory
        The site records returned by Get-SPSSiteInventory. Web application failure rows
        have no site collection to use, so the web application is reported as not read.

        .OUTPUTS
        A PSCustomObject with Applications (one row per LOB system), Complete ($false when
        something could not be read) and Warnings (messages for the run log).

        .EXAMPLE
        $bcs = Get-SPSBcsApplication -Inventory $inventory
        $bcs.Applications | Format-Table LobSystemName, LobSystemType, EntityCount
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Inventory
    )

    $warnings = [System.Collections.Generic.List[string]]::new()
    $complete = $true

    $anchors = [ordered]@{}
    $withoutSite = [System.Collections.Generic.List[string]]::new()
    foreach ($record in $Inventory) {
        if ($null -eq $record) {
            continue
        }
        $webApplicationUrl = [string]$record.WebAppUrl
        if ([string]::IsNullOrWhiteSpace($webApplicationUrl)) {
            continue
        }
        if ([string]$record.InventoryScope -eq 'WebApplication' -or [string]::IsNullOrWhiteSpace([string]$record.Url)) {
            if (-not $withoutSite.Contains($webApplicationUrl)) {
                $withoutSite.Add($webApplicationUrl)
            }
            continue
        }
        if (-not $anchors.Contains($webApplicationUrl)) {
            $anchors[$webApplicationUrl] = [string]$record.Url
        }
    }
    foreach ($webApplicationUrl in $withoutSite) {
        if (-not $anchors.Contains($webApplicationUrl)) {
            $complete = $false
            $warnings.Add("The BCS metadata store was not read for web application '$webApplicationUrl' because it has no site collection to use as a service context.")
        }
    }

    $stores = [System.Collections.Generic.Dictionary[string, object]]::new()
    foreach ($webApplicationUrl in @($anchors.Keys)) {
        try {
            $catalog = Get-SPBusinessDataCatalogMetadataObject -BdcObjectType Catalog -ServiceContext $anchors[$webApplicationUrl] -ErrorAction Stop
            if ($null -eq $catalog) {
                throw 'The metadata store is unavailable.'
            }
            $storeId = [string](Get-SPSPropertyValue -InputObject $catalog -Name 'Id')
            if ([string]::IsNullOrWhiteSpace($storeId)) {
                throw 'The metadata store has no readable ID.'
            }
            if ($stores.ContainsKey($storeId)) {
                $stores[$storeId].WebApplications.Add($webApplicationUrl)
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
            $store.WebApplications.Add($webApplicationUrl)
            $stores[$storeId] = $store
            foreach ($lobSystem in $lobSystems) {
                try {
                    $store.Rows.Add((ConvertTo-SPSBcsApplicationRecord -LobSystem $lobSystem))
                }
                catch {
                    $complete = $false
                    $warnings.Add("A BCS LOB system could not be read for web application '$webApplicationUrl': $($_.Exception.Message)")
                }
            }
        }
        catch {
            $complete = $false
            $warnings.Add("The BCS metadata store could not be read for web application '$webApplicationUrl': $($_.Exception.Message)")
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
