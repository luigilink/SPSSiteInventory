function Get-SPSUserProfileConfigManager {
    <#
        .SYNOPSIS
        Gets the configuration manager of the User Profile service for a service context.

        .DESCRIPTION
        UserProfileConfigManager (Microsoft.Office.Server.UserProfiles) is the entry point of the connections
        and the property definitions of a User Profile service application. It needs the context of the proxy
        group of the service application, and the account that runs the inventory has to administer the
        service application: without the permission its ConnectionManager is $null.

        The type is looked up among the loaded assemblies, as the other SharePoint types of the toolkit are.
        The assembly of the User Profile service is not always loaded by the SharePoint commands, so it is
        loaded by its partial name when the type is not found (Windows PowerShell 5.1, which the farm runs).
        A session where it cannot be found gets a clear error.

        Private because it is an implementation detail of Get-SPSProfilePropertyMapping.

        .PARAMETER ServiceContext
        The SPServiceContext of the proxy group of the User Profile service application.

        .EXAMPLE
        $manager = Get-SPSUserProfileConfigManager -ServiceContext (Get-SPSProxyGroupServiceContext -ProxyGroup $group)
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $ServiceContext
    )

    $typeName = 'Microsoft.Office.Server.UserProfiles.UserProfileConfigManager'
    $managerType = $typeName -as [System.Type]
    if ($null -eq $managerType) {
        try {
            $null = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.Office.Server.UserProfiles')
        }
        catch {
            Write-Verbose -Message "The assembly of the User Profile service could not be loaded by its partial name: $($_.Exception.Message)"
        }
        $managerType = $typeName -as [System.Type]
    }
    if ($null -eq $managerType) {
        throw 'The user profile configuration manager type is not available: run the inventory in a SharePoint Management Shell on a farm server.'
    }

    $manager = New-Object -TypeName $typeName -ArgumentList $ServiceContext
    if ($null -eq $manager) {
        throw 'The user profile configuration manager could not be created.'
    }
    return $manager
}
