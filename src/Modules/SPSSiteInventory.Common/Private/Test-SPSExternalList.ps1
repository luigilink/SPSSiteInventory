function Test-SPSExternalList {
    <#
        .SYNOPSIS
        Tests whether a list is an external list.

        .DESCRIPTION
        An external list is backed by a Business Connectivity Services (BCS) external
        content type. SharePoint flags such a list as having an external data source, and
        the flag is stored with the list, so reading it does not call the Business Data
        Connectivity service or the external system.

        A flag that cannot be read raises an error instead of being read as "not an
        external list" (PowerShell turns a failing .NET getter into $null), so the caller
        can mark the inventory partial.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER List
        The SPList to inspect.

        .EXAMPLE
        Test-SPSExternalList -List $list
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $List
    )

    $hasExternalDataSource = Get-SPSPropertyValue -InputObject $List -Name 'HasExternalDataSource'
    if ($null -eq $hasExternalDataSource) {
        throw 'The external data source flag could not be read.'
    }

    return [bool]$hasExternalDataSource
}
