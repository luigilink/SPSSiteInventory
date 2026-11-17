function Add-SPSEventReceiverClass {
    <#
        .SYNOPSIS
        Counts a custom event receiver under the assembly and the class it is registered from.

        .DESCRIPTION
        SharePoint registers one event receiver per event type and per list, so a class that listens to
        six events on a hundred lists is 600 receivers. The table groups them by assembly and class
        for the event receiver report: for each group it keeps how many receivers there are, on how many
        lists, for which event types, and where the first one was found (the server-relative URL of the
        list, or its title when the URL cannot be read).

        Returns $false, and adds nothing, when the receiver needs a new group and the table already holds
        MaximumGroup of them. The groups that exist go on counting. The signal that counts the receivers
        is not read from this table, so a group that is left out never changes it.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Table
        The groups of the site collection, by assembly and class. It is changed in place.

        .PARAMETER Receiver
        The event receiver definition (SPEventReceiverDefinition): its Assembly, its Class and its Type.

        .PARAMETER List
        The list that the receiver is registered on.

        .PARAMETER MaximumGroup
        The most groups that the table may hold. Defaults to 200.

        .EXAMPLE
        $null = Add-SPSEventReceiverClass -Table $table -Receiver $receiver -List $list
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.Dictionary[System.String, System.Object]]
        $Table,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $Receiver,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $List,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [System.Int32]
        $MaximumGroup = 200
    )

    $assembly = [System.String]$Receiver.Assembly
    $class = [System.String]$Receiver.Class
    $key = '{0}|{1}' -f $assembly, $class
    $group = $null
    if (-not $Table.TryGetValue($key, [ref]$group)) {
        if ($Table.Count -ge $MaximumGroup) {
            return $false
        }
        $firstListUrl = [System.String]$List.RootFolder.ServerRelativeUrl
        if ([System.String]::IsNullOrWhiteSpace($firstListUrl)) {
            $firstListUrl = [System.String]$List.Title
        }
        $group = [PSCustomObject]@{
            Assembly      = $assembly
            Class         = $class
            ReceiverCount = 0
            List          = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
            EventType     = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
            FirstListUrl  = $firstListUrl
        }
        $Table.Add($key, $group)
    }

    $group.ReceiverCount++
    $listKey = if ($null -ne $List.ID) { [System.String]$List.ID } else { [System.String]$List.Title }
    [void]$group.List.Add($listKey)
    $eventType = [System.String]$Receiver.Type
    if (-not [System.String]::IsNullOrWhiteSpace($eventType)) {
        [void]$group.EventType.Add($eventType)
    }

    return $true
}
