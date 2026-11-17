function ConvertTo-SPSEventReceiverClassRow {
    <#
        .SYNOPSIS
        Turns the groups of Add-SPSEventReceiverClass into the rows of the event receiver report.

        .DESCRIPTION
        Returns one row for each assembly and class of a site collection, the largest first: the site
        collection, the assembly as it is registered and split (name, version, public key token), the
        class, the number of receivers, the number of lists, the event types and the first list where
        the class is registered.

        When an index of the inspected packages is given, each row also says which solution ships the
        assembly. SolutionMatch is NotChecked when no index is given (no package was inspected), None
        when no inspected package ships the assembly, and AssemblyNameAndKey or AssemblyName when one does
        (see Resolve-SPSAssemblySolution). FarmSolutionName and PackageName are empty unless one does.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Table
        The groups of the site collection (from Add-SPSEventReceiverClass).

        .PARAMETER SiteUrl
        The URL of the site collection.

        .PARAMETER SolutionAssemblyIndex
        Optional index from Get-SPSSolutionAssemblyIndex. Leave it out when no package was inspected.

        .EXAMPLE
        ConvertTo-SPSEventReceiverClassRow -Table $table -SiteUrl $site.Url -SolutionAssemblyIndex $index
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.Dictionary[System.String, System.Object]]
        $Table,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $SiteUrl,

        [Parameter()]
        [System.Collections.IDictionary]
        $SolutionAssemblyIndex = $null
    )

    if ($Table.Count -eq 0) {
        return @()
    }

    $row = foreach ($group in $Table.Values) {
        $identity = ConvertFrom-SPSAssemblyName -DisplayName $group.Assembly
        $solutionMatch = 'NotChecked'
        $farmSolutionName = ''
        $packageName = ''
        if ($null -ne $SolutionAssemblyIndex) {
            $solution = Resolve-SPSAssemblySolution -AssemblyName $group.Assembly -Index $SolutionAssemblyIndex
            if ($null -eq $solution) {
                $solutionMatch = 'None'
            }
            else {
                $solutionMatch = $solution.MatchedBy
                $farmSolutionName = $solution.FarmSolutionName
                $packageName = $solution.PackageName
            }
        }
        [PSCustomObject]@{
            SiteUrl          = $SiteUrl
            Assembly         = $group.Assembly
            AssemblyName     = $identity.Name
            AssemblyVersion  = $identity.Version
            PublicKeyToken   = $identity.PublicKeyToken
            Class            = $group.Class
            ReceiverCount    = [System.Int32]$group.ReceiverCount
            ListCount        = [System.Int32]$group.List.Count
            EventTypes       = (@($group.EventType | Sort-Object) -join '; ')
            FirstListUrl     = $group.FirstListUrl
            SolutionMatch    = $solutionMatch
            FarmSolutionName = $farmSolutionName
            PackageName      = $packageName
        }
    }

    return @($row | Sort-Object -Property @{ Expression = { $_.ReceiverCount }; Descending = $true }, @{ Expression = { $_.AssemblyName } }, @{ Expression = { $_.Class } }, @{ Expression = { $_.Assembly } })
}
