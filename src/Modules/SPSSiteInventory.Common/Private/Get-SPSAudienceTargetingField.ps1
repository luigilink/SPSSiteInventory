function Get-SPSAudienceTargetingField {
    <#
        .SYNOPSIS
        Finds the audience targeting column of a list, or tells that the list has none.

        .DESCRIPTION
        A list has the Target Audiences column only when the audience targeting was enabled on it (List
        Settings > Audience targeting settings), and the Pages library of a publishing site has it from the
        start. The column has the same ID everywhere, 61cbb965-1e04-4273-b658-eedaa662f48d, but not the same
        internal name: Target_x0020_Audiences in a list, Audience in a Pages library. So it is found by its
        ID first, and by its type (TargetTo) when the ID is not the one.

        The ID of a column that cannot be read raises an error instead of being read as no column
        (PowerShell turns a failing .NET getter into $null), so that a list that could not be read is not
        taken for a list without targeting; the type is only the second chance and is read as it comes.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER List
        The SPList to look at.

        .OUTPUTS
        The column (an SPField), or $null when the list has no audience targeting column.

        .EXAMPLE
        $field = Get-SPSAudienceTargetingField -List $list
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $List
    )

    $targetingFieldId = [guid]'61cbb965-1e04-4273-b658-eedaa662f48d'

    # A collection is read directly: a function would enumerate it, and null is never a valid collection.
    $fields = $List.Fields
    if ($null -eq $fields) {
        throw "The columns of list '$($List.Title)' could not be read."
    }

    foreach ($field in $fields) {
        if ($null -eq $field) {
            continue
        }
        $fieldId = Get-SPSPropertyValue -InputObject $field -Name 'Id'
        if ($null -ne $fieldId -and [guid]$fieldId -eq $targetingFieldId) {
            return $field
        }
        if ([string]$field.TypeAsString -eq 'TargetTo') {
            return $field
        }
    }
    return $null
}
