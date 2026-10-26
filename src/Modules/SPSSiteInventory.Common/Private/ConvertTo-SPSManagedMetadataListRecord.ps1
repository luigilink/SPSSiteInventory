function ConvertTo-SPSManagedMetadataListRecord {
    <#
        .SYNOPSIS
        Projects the managed metadata columns of a list into a portable inventory row.

        .DESCRIPTION
        A managed metadata column is a field of type TaxonomyFieldType or
        TaxonomyFieldTypeMulti, which includes the Enterprise Keywords column. Hidden
        fields are ignored, so the helper fields SharePoint adds for each column are not
        counted. Returns $null when the list has no managed metadata column.

        The row follows the SMAT "Managed Metadata Columns" list report. Term set IDs are
        read from the field definition, without calling the term store service, so term
        set names are not resolved and the term store itself is not queried. The list
        creator that SMAT reports is not collected.

        A property that cannot be read raises an error instead of being read as "no
        managed metadata column" (PowerShell turns a failing .NET getter into $null), so
        the collector can mark the inventory partial.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER List
        The SPList to inspect.

        .PARAMETER SiteUrl
        URL of the site collection that owns the list.

        .PARAMETER WebUrl
        URL of the web that owns the list.

        .EXAMPLE
        ConvertTo-SPSManagedMetadataListRecord -List $list -SiteUrl $site.Url -WebUrl $web.Url
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

    $fields = $List.Fields
    if ($null -eq $fields) {
        throw 'The field collection is unavailable.'
    }

    $columnNames = [System.Collections.Generic.List[string]]::new()
    $termSetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($field in $fields) {
        if ($null -eq $field) {
            throw 'A field could not be read.'
        }

        $fieldType = [string]$field.TypeAsString
        if ([string]::IsNullOrWhiteSpace($fieldType)) {
            throw 'A field has no readable type name.'
        }
        if ($fieldType -ne 'TaxonomyFieldType' -and $fieldType -ne 'TaxonomyFieldTypeMulti') {
            continue
        }

        $columnName = [string]$field.Title
        if ([string]::IsNullOrWhiteSpace($columnName)) {
            $columnName = [string]$field.InternalName
        }
        if ([string]::IsNullOrWhiteSpace($columnName)) {
            throw 'A managed metadata column has no readable name.'
        }

        $hidden = Get-SPSPropertyValue -InputObject $field -Name 'Hidden'
        if ($null -eq $hidden) {
            throw "The hidden state of the managed metadata column '$columnName' could not be read."
        }
        if ([bool]$hidden) {
            continue
        }

        $termSetValue = Get-SPSPropertyValue -InputObject $field -Name 'TermSetId'
        if ($null -eq $termSetValue) {
            throw "The term set of the managed metadata column '$columnName' could not be read."
        }
        $termSetId = [guid]$termSetValue
        if ($termSetId -ne [guid]::Empty) {
            [void]$termSetIds.Add($termSetId.ToString())
        }
        $columnNames.Add($columnName)
    }

    if ($columnNames.Count -eq 0) {
        return $null
    }

    $listTitle = [string]$List.Title
    if ([string]::IsNullOrWhiteSpace($listTitle)) {
        throw 'The list title could not be read.'
    }
    $rootFolder = $List.RootFolder
    $listUrl = if ($null -ne $rootFolder) { [string]$rootFolder.ServerRelativeUrl } else { '' }
    if ([string]::IsNullOrWhiteSpace($listUrl)) {
        throw "The URL of list '$listTitle' could not be read."
    }
    $itemCount = Get-SPSPropertyValue -InputObject $List -Name 'ItemCount'
    if ($null -eq $itemCount) {
        throw "The item count of list '$listTitle' could not be read."
    }

    $lastModified = ''
    $lastModifiedValue = $List.LastItemModifiedDate
    if ($lastModifiedValue -is [datetime]) {
        $lastModified = $lastModifiedValue.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    # Ordinal sorting keeps the output stable between runs and cultures.
    $sortedColumns = [string[]]$columnNames.ToArray()
    [System.Array]::Sort($sortedColumns, [System.StringComparer]::OrdinalIgnoreCase)
    $sortedTermSets = [string[]]@($termSetIds)
    [System.Array]::Sort($sortedTermSets, [System.StringComparer]::OrdinalIgnoreCase)

    [PSCustomObject]@{
        SiteUrl                    = $SiteUrl
        WebUrl                     = $WebUrl
        ListTitle                  = $listTitle
        ListUrl                    = $listUrl
        ListTemplate               = [string]$List.BaseTemplate
        ListType                   = [string]$List.BaseType
        ListItemCount              = [int]$itemCount
        ItemLastModifiedDate       = $lastModified
        ManagedMetadataColumnCount = $columnNames.Count
        ManagedMetadataColumns     = ($sortedColumns -join '; ')
        TermSetIds                 = ($sortedTermSets -join '; ')
    }
}
