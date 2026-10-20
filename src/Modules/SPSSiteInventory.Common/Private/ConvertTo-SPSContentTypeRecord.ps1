function ConvertTo-SPSContentTypeRecord {
    <#
        .SYNOPSIS
        Projects a web content type or list binding into a portable inventory row.

        .DESCRIPTION
        Keeps IDs, parent IDs, fields and document-template references without
        inferring that a name, group or non-standard ID makes a content type custom.
        List content-type IDs are preserved, not merged with their parent definition.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $ContentType,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SiteUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebUrl,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Web', 'List')]
        [System.String]
        $Scope,

        [Parameter()]
        [System.String]
        $ListTitle = '',

        [Parameter()]
        [System.String]
        $ListUrl = ''
    )

    $id = [string]$ContentType.Id
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw "A content type on '$WebUrl' has no readable ID."
    }
    $fieldCollection = $ContentType.Fields
    if ($null -eq $fieldCollection) {
        throw "Could not read fields for content type '$id' on '$WebUrl'."
    }
    $fields = @($fieldCollection | Where-Object { $null -ne $_ })

    [PSCustomObject]@{
        SiteUrl             = $SiteUrl
        WebUrl              = $WebUrl
        Scope               = $Scope
        ListTitle           = $ListTitle
        ListUrl             = $ListUrl
        ContentTypeId       = $id
        Name                = [string]$ContentType.Name
        Group               = [string]$ContentType.Group
        ParentContentTypeId = if ($null -ne $ContentType.Parent) { [string]$ContentType.Parent.Id } else { '' }
        FieldCount          = $fields.Count
        FieldTypes          = (@($fields | ForEach-Object { $_.TypeAsString } | Sort-Object -Unique) -join '; ')
        DocumentTemplateUrl = [string]$ContentType.DocumentTemplateUrl
        Hidden              = [bool]$ContentType.Hidden
        ReadOnly            = [bool]$ContentType.ReadOnly
        Sealed              = [bool]$ContentType.Sealed
    }
}
