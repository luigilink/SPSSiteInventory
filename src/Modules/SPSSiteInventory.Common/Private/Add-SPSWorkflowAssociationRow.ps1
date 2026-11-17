function Add-SPSWorkflowAssociationRow {
    <#
        .SYNOPSIS
        Adds the row of a classic workflow association to the rows of a site collection.

        .DESCRIPTION
        Workflow2010Count and Workflow2010RunningInstanceCount are totals for a site collection. The rows give the
        detail behind them, one for each association of a web, or of a list or library: the web, the list or
        library, the name of the workflow and its running instances.

        An association is counted in Workflow2010Count when it is one of the ActiveAssociation (the result of
        Get-SPSActiveWorkflowAssociations for the same associations). The previous versions of a workflow stay in
        SharePoint as associations of their own: they are not counted, but their running instances are in
        Workflow2010RunningInstanceCount, so they get a row too, with Counted false. The rows of the counted
        associations are all kept, so that they always add up to Workflow2010Count. The rows of the previous
        versions stop at MaximumPreviousVersion for a site collection: the function returns $false, and adds
        nothing, when one does not fit. The counts are not read from the rows, so a row that is left out never
        changes them.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Table
        The rows of the site collection: an object that has a Current list (the counted associations) and a
        Previous list. It is changed in place.

        .PARAMETER Association
        The workflow association (SPWorkflowAssociation): its Name and its running instances are read.

        .PARAMETER ActiveAssociation
        The associations of the same web or list that count, from Get-SPSActiveWorkflowAssociations. The
        association is counted when it is one of them (the same object, not one of the same name).

        .PARAMETER SiteUrl
        The URL of the site collection.

        .PARAMETER WebUrl
        The URL of the web that holds the association, or the list.

        .PARAMETER Scope
        Web for an association of a web, List for an association of a list or library. Defaults to Web.

        .PARAMETER ListTitle
        The title of the list or library. Leave it out for an association of a web.

        .PARAMETER ListUrl
        The server-relative URL of the list or library. Leave it out for an association of a web.

        .PARAMETER MaximumPreviousVersion
        The most rows of previous versions that the table may hold. Defaults to 1000.

        .EXAMPLE
        $null = Add-SPSWorkflowAssociationRow -Table $table -Association $association -ActiveAssociation $active -SiteUrl $site.Url -WebUrl $web.Url
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Table,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $Association,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $ActiveAssociation = @(),

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $SiteUrl,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $WebUrl,

        [Parameter()]
        [ValidateSet('Web', 'List')]
        [System.String]
        $Scope = 'Web',

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $ListTitle = '',

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $ListUrl = '',

        [Parameter()]
        [ValidateRange(1, 100000)]
        [System.Int32]
        $MaximumPreviousVersion = 1000
    )

    # The objects are compared themselves. The base object of a custom object is shared by all of them, so it is not used for those.
    $identityOf = {
        param ($Item)
        $base = $Item.PSObject.BaseObject
        if ($base -is [System.Management.Automation.PSCustomObject]) {
            return $Item
        }
        return $base
    }
    $target = & $identityOf $Association
    $counted = $false
    foreach ($active in @($ActiveAssociation)) {
        if ($null -ne $active -and [System.Object]::ReferenceEquals((& $identityOf $active), $target)) {
            $counted = $true
            break
        }
    }

    if (-not $counted -and $Table.Previous.Count -ge $MaximumPreviousVersion) {
        return $false
    }

    $row = [PSCustomObject]@{
        SiteUrl          = $SiteUrl
        WebUrl           = $WebUrl
        Scope            = $Scope
        ListTitle        = $ListTitle
        ListUrl          = $ListUrl
        WorkflowName     = [System.String]$Association.Name
        Counted          = $counted
        RunningInstances = [System.Int32](Get-SPSWorkflowAssociationRunningCount -WorkflowAssociations @($Association))
    }
    if ($counted) {
        $Table.Current.Add($row)
    }
    else {
        $Table.Previous.Add($row)
    }

    return $true
}
