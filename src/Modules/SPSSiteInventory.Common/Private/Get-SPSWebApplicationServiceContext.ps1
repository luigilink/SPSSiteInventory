function Get-SPSWebApplicationServiceContext {
    <#
        .SYNOPSIS
        Gets the default service context of a web application.

        .DESCRIPTION
        A service context selects the service applications a web application is associated
        with, for example the Business Data Connectivity service. It is built from the
        service application proxy group of the web application, so no site collection is
        needed and a web application without any site collection can be read too.

        The context is the one of the default (non-tenant) site subscription, which is the
        one every site collection uses outside a multi-tenant farm.

        Private because it is an implementation detail of Get-SPSBcsApplication. It calls
        the SharePoint object model directly, so it is mocked in the unit tests.

        .PARAMETER WebApplication
        An SPWebApplication object returned by Get-SPWebApplication.

        .EXAMPLE
        Get-SPSWebApplicationServiceContext -WebApplication $webApplication
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $WebApplication
    )

    $proxyGroup = $WebApplication.ServiceApplicationProxyGroup
    if ($null -eq $proxyGroup) {
        throw "The service application proxy group of '$($WebApplication.Url)' could not be read."
    }

    $serviceContext = [Microsoft.SharePoint.SPServiceContext]::GetContext($proxyGroup, [Microsoft.SharePoint.SPSiteSubscriptionIdentifier]::Default)
    if ($null -eq $serviceContext) {
        throw "No service context is available for '$($WebApplication.Url)'."
    }

    return $serviceContext
}
