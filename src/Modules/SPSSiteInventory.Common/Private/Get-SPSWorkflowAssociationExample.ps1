function Get-SPSWorkflowAssociationExample {
    <#
        .SYNOPSIS
        Writes the rows of the workflow association report as the examples of the Workflow2010 signals.

        .DESCRIPTION
        Gives up to five rows as text separated by '; ': the name of the workflow, where it is (the list or
        library and its web, or the web) and how many instances are running. The counted associations come
        first and, among them, the ones with the most running instances. A previous version, which is not
        counted but whose instances are in the running total, says so. The text goes in the inventory record,
        so that the CSV file and the detail of a site collection in the HTML report say which workflows the
        signals count.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Row
        The rows of the workflow association report (from Add-SPSWorkflowAssociationRow).

        .PARAMETER Maximum
        The number of rows to show. Defaults to 5.

        .EXAMPLE
        Get-SPSWorkflowAssociationExample -Row $rows
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Row = @(),

        [Parameter()]
        [ValidateRange(1, 100)]
        [System.Int32]
        $Maximum = 5
    )

    $first = @(
        $Row | Where-Object { $null -ne $_ } |
            Sort-Object -Property @{ Expression = { [System.Boolean]$_.Counted }; Descending = $true }, @{ Expression = { [System.Int32]$_.RunningInstances }; Descending = $true }, @{ Expression = { [System.String]$_.WorkflowName } }, @{ Expression = { [System.String]$_.WebUrl } }, @{ Expression = { [System.String]$_.ListTitle } } |
            Select-Object -First $Maximum
    )
    $text = foreach ($item in $first) {
        $where = if ([System.String]$item.Scope -eq 'List') { 'list {0}, {1}' -f [System.String]$item.ListTitle, [System.String]$item.WebUrl } else { 'web {0}' -f [System.String]$item.WebUrl }
        $suffix = if ([System.Boolean]$item.Counted) { '' } else { ' [previous version]' }
        '{0} ({1}): {2} running instance(s){3}' -f [System.String]$item.WorkflowName, $where, [System.Int32]$item.RunningInstances, $suffix
    }

    return (@($text) -join '; ')
}
