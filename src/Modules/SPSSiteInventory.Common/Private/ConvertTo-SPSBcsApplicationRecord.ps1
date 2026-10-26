function ConvertTo-SPSBcsApplicationRecord {
    <#
        .SYNOPSIS
        Projects a Business Data Connectivity LOB system into a portable inventory row.

        .DESCRIPTION
        A LOB system is the Business Connectivity Services (BCS) definition of an external
        system: its type, its instances (the connections that external lists use) and its
        entities (the external content types). It is not migrated to SharePoint Online.

        The row holds the name, the system type, the instance names and the entity names
        written as namespace.name. Connection properties, credentials and Secure Store
        target applications are not read. At most MaxEntityName entity names are written,
        and EntityCount always holds the full number.

        A property that cannot be read raises an error instead of being read as an empty
        value (PowerShell turns a failing .NET getter into $null), so the caller can mark
        the BCS inventory incomplete.

        Private because it is an implementation detail of Get-SPSBcsApplication.

        .PARAMETER LobSystem
        A LobSystem metadata object from the Business Data Connectivity metadata store.

        .PARAMETER MaxEntityName
        Maximum number of entity names written to LobEntities. Defaults to 20.

        .EXAMPLE
        $catalog.GetLobSystems('*') | ForEach-Object { ConvertTo-SPSBcsApplicationRecord -LobSystem $_ }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $LobSystem,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [System.Int32]
        $MaxEntityName = 20
    )

    $name = [string](Get-SPSPropertyValue -InputObject $LobSystem -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'A LOB system has no readable name.'
    }
    $systemType = Get-SPSPropertyValue -InputObject $LobSystem -Name 'SystemType'
    if ($null -eq $systemType) {
        throw "The system type of LOB system '$name' could not be read."
    }

    # Collections are read directly: a function would enumerate them, and null is never a valid collection.
    $instances = $LobSystem.LobSystemInstances
    if ($null -eq $instances) {
        throw "The instances of LOB system '$name' could not be read."
    }
    $instanceNames = [System.Collections.Generic.List[string]]::new()
    foreach ($instance in $instances) {
        $instanceName = [string](Get-SPSPropertyValue -InputObject $instance -Name 'Name')
        if ([string]::IsNullOrWhiteSpace($instanceName)) {
            throw "An instance of LOB system '$name' has no readable name."
        }
        $instanceNames.Add($instanceName)
    }

    $entities = $LobSystem.Entities
    if ($null -eq $entities) {
        throw "The entities of LOB system '$name' could not be read."
    }
    $entityNames = [System.Collections.Generic.List[string]]::new()
    foreach ($entity in $entities) {
        $entityName = [string](Get-SPSPropertyValue -InputObject $entity -Name 'Name')
        $entityNamespace = [string](Get-SPSPropertyValue -InputObject $entity -Name 'Namespace')
        if ([string]::IsNullOrWhiteSpace($entityName) -or [string]::IsNullOrWhiteSpace($entityNamespace)) {
            throw "An entity of LOB system '$name' has no readable name or namespace."
        }
        $entityNames.Add(('{0}.{1}' -f $entityNamespace, $entityName))
    }

    # Ordinal sorting keeps the output stable between runs and cultures.
    $sortedInstances = [string[]]$instanceNames.ToArray()
    [System.Array]::Sort($sortedInstances, [System.StringComparer]::OrdinalIgnoreCase)
    $sortedEntities = [string[]]$entityNames.ToArray()
    [System.Array]::Sort($sortedEntities, [System.StringComparer]::OrdinalIgnoreCase)
    $shownEntities = @($sortedEntities | Select-Object -First $MaxEntityName)
    $entityText = $shownEntities -join '; '
    if ($sortedEntities.Count -gt $MaxEntityName) {
        $entityText += ' (+{0} more)' -f ($sortedEntities.Count - $MaxEntityName)
    }

    [PSCustomObject]@{
        LobSystemName      = $name
        LobSystemType      = [string]$systemType
        LobSystemInstances = ($sortedInstances -join '; ')
        EntityCount        = $sortedEntities.Count
        LobEntities        = $entityText
    }
}
