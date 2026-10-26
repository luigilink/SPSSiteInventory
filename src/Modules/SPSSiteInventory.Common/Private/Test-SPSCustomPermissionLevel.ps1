function Test-SPSCustomPermissionLevel {
    <#
        .SYNOPSIS
        Tells whether a permission level (role definition) is custom.

        .DESCRIPTION
        SharePoint gives Limited Access, Read, Contribute, Design, Full Control, Edit and
        Restricted Read a base type (SPRoleType). A role definition whose Type is None was
        either created by a user or provisioned by SharePoint for a feature or site
        template (View Only, Approve, Manage Hierarchy, Restricted Interfaces for
        Translation, Moderate, Records Center Web Service Submitters). The provisioned
        levels are told apart from custom ones by name, using BuiltInName. Names are
        localized, so on a non-English farm the localized names must be added to the
        settings, otherwise those provisioned levels are reported as custom.

        A missing or null Type or Name is rejected: PowerShell turns an exception thrown
        by a property getter into $null, which would hide an unreadable permission level
        behind a negative signal.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER RoleDefinition
        The SPRoleDefinition to evaluate.

        .PARAMETER BuiltInName
        Names of the permission levels SharePoint provisions, compared case-insensitively.

        .EXAMPLE
        Test-SPSCustomPermissionLevel -RoleDefinition $role -BuiltInName @('View Only', 'Approve')
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $RoleDefinition,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $BuiltInName = @()
    )

    $type = $null
    $name = $null
    if ($null -ne $RoleDefinition) {
        if ($null -ne $RoleDefinition.PSObject.Properties['Type']) {
            $type = $RoleDefinition.Type
        }
        if ($null -ne $RoleDefinition.PSObject.Properties['Name']) {
            $name = [string]$RoleDefinition.Name
        }
    }
    if ($null -eq $type -or [string]::IsNullOrWhiteSpace($name)) {
        throw 'The permission level type or name could not be read.'
    }

    $typeText = [string]$type
    if ($typeText -ne 'None' -and $typeText -ne '0') {
        return $false
    }

    return -not (@($BuiltInName) -contains $name)
}
