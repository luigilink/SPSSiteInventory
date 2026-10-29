function Resolve-SPSAudienceName {
    <#
        .SYNOPSIS
        Gets the names of audiences of the User Profile service from their IDs.

        .DESCRIPTION
        The audience targeting column stores the ID of an audience, not its name. The names are read
        through the audience manager of the User Profile service application that the site collection
        uses (Microsoft.Office.Server.Audience.AudienceManager, with the service context of the site), as
        the SMAT report does, where an ID that cannot be resolved is shown as it is: the audience may have
        been deleted after it was used on an item.

        The names are best effort. When the audience manager cannot be built (no User Profile service
        application for the site, no permission to read the audiences, the type not loaded) or an audience
        is not found, the ID has no entry in the result, and the caller shows the ID. Nothing here marks an
        inventory incomplete: the item and the list that target an audience are known from the column, only
        the name is missing. The reason is written to the verbose stream.

        The function is read-only. Private because it is an implementation detail of
        Get-SPSSiteCustomization.

        .PARAMETER Site
        The site collection (SPSite) whose User Profile service application is used.

        .PARAMETER AudienceId
        The IDs of the audiences to look up, as GUID strings.

        .OUTPUTS
        A hashtable from each ID (the string given, in lower case) to the name of the audience. An ID that
        could not be resolved is not in it.

        .EXAMPLE
        $names = Resolve-SPSAudienceName -Site $site -AudienceId @('a88b9dcb-0000-0000-0000-000000000001')
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Site,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.String[]]
        $AudienceId
    )

    $names = @{}
    if ($AudienceId.Count -eq 0) {
        return $names
    }

    try {
        $context = Get-SPServiceContext -Site $Site -ErrorAction Stop
        if ($null -eq $context) {
            throw 'The service context of the site collection is unavailable.'
        }
        $managerType = 'Microsoft.Office.Server.Audience.AudienceManager' -as [System.Type]
        if ($null -eq $managerType) {
            # The assembly of the User Profile service is not always loaded by the SharePoint commands.
            $null = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.Office.Server.UserProfiles')
            $managerType = 'Microsoft.Office.Server.Audience.AudienceManager' -as [System.Type]
        }
        if ($null -eq $managerType) {
            throw 'The audience manager type is not available.'
        }
        $manager = New-Object -TypeName 'Microsoft.Office.Server.Audience.AudienceManager' -ArgumentList $context
    }
    catch {
        Write-Verbose -Message "The audiences could not be read, so their IDs are shown: $($_.Exception.Message)"
        return $names
    }

    foreach ($id in $AudienceId) {
        try {
            $guid = [guid]::Empty
            if (-not [guid]::TryParse($id, [ref]$guid)) {
                continue
            }
            # GetAudience(Guid) returns $null for an audience that does not exist; the cast keeps the String overload out.
            $audience = $manager.GetAudience([guid]$guid)
            if ($null -ne $audience) {
                $audienceName = [string](Get-SPSPropertyValue -InputObject $audience -Name 'AudienceName')
                if (-not [string]::IsNullOrWhiteSpace($audienceName)) {
                    $names[$id.ToLowerInvariant()] = $audienceName
                }
            }
        }
        catch {
            Write-Verbose -Message "The audience '$id' could not be read, so its ID is shown: $($_.Exception.Message)"
        }
    }
    return $names
}
