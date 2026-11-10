function Get-SPSEventReceiverExample {
    <#
        .SYNOPSIS
        Writes the rows of the event receiver report as the examples of the EventReceivers signal.

        .DESCRIPTION
        Gives up to five rows, the ones that come first, as text separated by '; ': the assembly and the class,
        how many receivers there are and on how many lists, the first list where the class is registered
        and, when an inspected package ships the assembly, the farm solution (or the package, when it is
        not deployed in the farm). The text goes in the inventory record, so that the CSV file and the
        detail of a site collection in the HTML report say which assemblies and classes the signal counts.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Row
        The rows from ConvertTo-SPSEventReceiverClassRow, in the order to show them.

        .PARAMETER Maximum
        The number of rows to show. Defaults to 5.

        .EXAMPLE
        Get-SPSEventReceiverExample -Row $rows
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

    $text = foreach ($item in @($Row | Where-Object { $null -ne $_ } | Select-Object -First $Maximum)) {
        $assemblyName = if ([System.String]::IsNullOrWhiteSpace([System.String]$item.AssemblyName)) { [System.String]$item.Assembly } else { [System.String]$item.AssemblyName }
        $className = if ([System.String]::IsNullOrWhiteSpace([System.String]$item.Class)) { '' } else { ' / ' + [System.String]$item.Class }
        $where = if ([System.String]::IsNullOrWhiteSpace([System.String]$item.FirstListUrl)) { '' } else { ', first ' + [System.String]$item.FirstListUrl }
        $solution = if ($item.FarmSolutionName) { ' (solution ' + [System.String]$item.FarmSolutionName + ')' } elseif ($item.PackageName) { ' (package ' + [System.String]$item.PackageName + ')' } else { '' }
        '{0}{1}: {2} receiver(s) on {3} list(s){4}{5}' -f $assemblyName, $className, [System.Int32]$item.ReceiverCount, [System.Int32]$item.ListCount, $where, $solution
    }

    return (@($text) -join '; ')
}
