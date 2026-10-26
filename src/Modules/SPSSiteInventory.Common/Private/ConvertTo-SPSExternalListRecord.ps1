function ConvertTo-SPSExternalListRecord {
    <#
        .SYNOPSIS
        Projects an external list into a portable inventory row.

        .DESCRIPTION
        An external list is backed by a Business Connectivity Services (BCS) external
        content type: its items stay in the external system, so neither the list nor the
        BCS definition behind it is migrated. SharePoint flags such a list as having an
        external data source. Returns $null for any other list.

        The row identifies the list and the BCS binding SharePoint stores with it: the
        LOB system instance, the entity namespace and the entity name. They are read from
        the list definition in the content database, so neither the Business Data
        Connectivity service nor the external system is called. Item counts and dates are
        not collected because the items are not stored in SharePoint, and the list
        creator that SMAT reports is not collected either.

        A property that cannot be read raises an error instead of being read as "not an
        external list" or as an empty binding (PowerShell turns a failing .NET getter
        into $null), so the collector can mark the inventory partial.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER List
        The SPList to inspect.

        .PARAMETER SiteUrl
        URL of the site collection that owns the list.

        .PARAMETER WebUrl
        URL of the web that owns the list.

        .EXAMPLE
        ConvertTo-SPSExternalListRecord -List $list -SiteUrl $site.Url -WebUrl $web.Url
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $List,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SiteUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebUrl
    )

    $hasExternalDataSource = Get-SPSPropertyValue -InputObject $List -Name 'HasExternalDataSource'
    if ($null -eq $hasExternalDataSource) {
        throw 'The external data source flag could not be read.'
    }
    if (-not [bool]$hasExternalDataSource) {
        return $null
    }

    $listTitle = [string](Get-SPSPropertyValue -InputObject $List -Name 'Title')
    if ([string]::IsNullOrWhiteSpace($listTitle)) {
        throw 'The list title could not be read.'
    }
    $rootFolder = Get-SPSPropertyValue -InputObject $List -Name 'RootFolder'
    $listUrl = if ($null -ne $rootFolder) { [string](Get-SPSPropertyValue -InputObject $rootFolder -Name 'ServerRelativeUrl') } else { '' }
    if ([string]::IsNullOrWhiteSpace($listUrl)) {
        throw "The URL of list '$listTitle' could not be read."
    }

    $dataSource = Get-SPSPropertyValue -InputObject $List -Name 'DataSource'
    if ($null -eq $dataSource) {
        throw "The external data source of list '$listTitle' could not be read."
    }

    # SharePoint requires these three values on every external list data source.
    $binding = @{}
    foreach ($key in @('LobSystemInstance', 'EntityNamespace', 'Entity')) {
        $value = [string]$dataSource.GetProperty($key)
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "The $key of the external data source of list '$listTitle' could not be read."
        }
        $binding[$key] = $value
    }

    [PSCustomObject]@{
        SiteUrl           = $SiteUrl
        WebUrl            = $WebUrl
        ListTitle         = $listTitle
        ListUrl           = $listUrl
        LobSystemInstance = $binding['LobSystemInstance']
        EntityNamespace   = $binding['EntityNamespace']
        Entity            = $binding['Entity']
    }
}
