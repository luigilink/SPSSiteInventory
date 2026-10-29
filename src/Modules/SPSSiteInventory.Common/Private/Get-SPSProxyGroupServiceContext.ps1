function Get-SPSProxyGroupServiceContext {
    <#
        .SYNOPSIS
        Gets the service context of a service application proxy group, for the default (non-tenant) partition.

        .DESCRIPTION
        A service context binds the service applications of a proxy group, so the commands that take a
        -ServiceContext (the Secure Store ones, for example) can read a service application without a site
        collection: a web application that has none is read too. The context is built for the default site
        subscription, that is the farm without a tenant.

        The two SharePoint types are looked up among the loaded assemblies, as the other SharePoint types
        of the toolkit are, so a session where the SharePoint commands are not loaded gets a clear error.

        Private because it is an implementation detail of the collectors of the farm-level reports.

        .PARAMETER ProxyGroup
        The SPServiceApplicationProxyGroup of a web application (SPWebApplication.ServiceApplicationProxyGroup).

        .EXAMPLE
        $context = Get-SPSProxyGroupServiceContext -ProxyGroup $webApplication.ServiceApplicationProxyGroup
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $ProxyGroup
    )

    $contextType = 'Microsoft.SharePoint.SPServiceContext' -as [System.Type]
    $subscriptionType = 'Microsoft.SharePoint.SPSiteSubscriptionIdentifier' -as [System.Type]
    if ($null -eq $contextType -or $null -eq $subscriptionType) {
        throw 'The SharePoint service context types are not loaded: run the inventory in a SharePoint Management Shell or after Import-SPSSharePointCommand.'
    }

    $context = $contextType::GetContext($ProxyGroup, $subscriptionType::Default)
    if ($null -eq $context) {
        throw 'The service context of the service application proxy group is unavailable.'
    }
    return $context
}
