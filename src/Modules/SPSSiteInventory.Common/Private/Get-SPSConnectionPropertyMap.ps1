function Get-SPSConnectionPropertyMap {
    <#
        .SYNOPSIS
        Reads the profile property mappings of a synchronization connection of the User Profile service.

        .DESCRIPTION
        A mapping ties a profile property to an attribute of the data source of a connection, to import the
        value into the profile or to export it. The public API shows them in two ways:

        - Most connections have a PropertyMapping, a PropertyMapCollection of PropertyMap objects
          (ProfileProperty, DataSourcePropertyName, IsExport). The collection declares no interface, so it
          is enumerated with its GetEnumerator method.
        - An Active Directory import connection, which is the default of SharePoint Server 2016 and later,
          has no PropertyMapping (it is $null), and its mappings can only be written through the public API.
          They are read from the method that SharePoint itself uses, the non-public ADImportPropertyMappings,
          which returns objects whose ProfileProperty (the name of the property) and ADAttribute (the
          attribute of the directory) are non-public members. Such a mapping imports: the connection has no
          export.

        A connection of another kind without a PropertyMapping, a method or a member that is not there, and
        anything that cannot be read raise an error that names the connection, so that the caller marks the
        inventory incomplete: a connection that cannot be read is never an empty one.

        The function is read-only. Private because it is an implementation detail of
        Get-SPSProfilePropertyMapping.

        .PARAMETER Connection
        A Connection of the ConnectionManager of the User Profile service application.

        .OUTPUTS
        One object per mapping, with ProfilePropertyName, DataSourcePropertyName and Direction (Import or
        Export).

        .EXAMPLE
        $manager.ConnectionManager | ForEach-Object { Get-SPSConnectionPropertyMap -Connection $_ }
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Connection
    )

    $connectionName = [string](Get-SPSPropertyValue -InputObject $Connection -Name 'DisplayName')
    $connectionType = [string](Get-SPSPropertyValue -InputObject $Connection -Name 'Type')
    $label = "'{0}' ({1})" -f $connectionName, $connectionType

    # A collection is read directly: a function would enumerate it, and null is a valid value here (an import).
    $propertyMapping = $Connection.PropertyMapping
    $maps = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $propertyMapping) {
        $enumerator = $propertyMapping.GetEnumerator()
        if ($null -eq $enumerator) {
            throw "The property mappings of connection $label could not be enumerated."
        }
        while ($enumerator.MoveNext()) {
            $map = $enumerator.Current
            $property = Get-SPSPropertyValue -InputObject $map -Name 'ProfileProperty'
            if ($null -eq $property) {
                throw "A property mapping of connection $label has no profile property."
            }
            $propertyName = [string](Get-SPSPropertyValue -InputObject $property -Name 'Name')
            $attribute = [string](Get-SPSPropertyValue -InputObject $map -Name 'DataSourcePropertyName')
            if ([string]::IsNullOrWhiteSpace($propertyName)) {
                throw "A property mapping of connection $label has no readable profile property name."
            }
            $isExport = [bool](Get-SPSPropertyValue -InputObject $map -Name 'IsExport')
            $maps.Add([PSCustomObject]@{
                    ProfilePropertyName    = $propertyName
                    DataSourcePropertyName = $attribute
                    Direction              = $(if ($isExport) { 'Export' } else { 'Import' })
                })
        }
        return $maps.ToArray()
    }

    if ($connectionType -ne 'ActiveDirectoryImport') {
        throw "The property mappings of connection $label could not be read: it has no PropertyMapping and is not an Active Directory import connection."
    }

    $flags = [System.Reflection.BindingFlags]'Instance,Public,NonPublic'
    $method = @($Connection.GetType().GetMethods($flags) | Where-Object { $_.Name -eq 'ADImportPropertyMappings' }) | Select-Object -First 1
    if ($null -eq $method) {
        throw "The method that reads the property mappings of the Active Directory import connection $label was not found."
    }
    try {
        $items = $method.Invoke($Connection, $null)
    }
    catch {
        throw "The property mappings of the Active Directory import connection $label could not be read: $($_.Exception.GetBaseException().Message)"
    }
    if ($null -eq $items) {
        throw "The property mappings of the Active Directory import connection $label could not be read: SharePoint returned none, not even an empty list."
    }

    $readMember = {
        param ([System.Object] $Object, [System.String] $Name)
        $type = $Object.GetType()
        $property = $type.GetProperty($Name, $flags)
        if ($null -ne $property) {
            return $property.GetValue($Object, $null)
        }
        $field = $type.GetField($Name, $flags)
        if ($null -ne $field) {
            return $field.GetValue($Object)
        }
        throw "A property mapping of the Active Directory import connection $label has no member named $Name."
    }

    foreach ($item in $items) {
        if ($null -eq $item) {
            continue
        }
        $propertyName = [string](& $readMember $item 'ProfileProperty')
        $attribute = [string](& $readMember $item 'ADAttribute')
        if ([string]::IsNullOrWhiteSpace($propertyName)) {
            throw "A property mapping of the Active Directory import connection $label has no readable profile property name."
        }
        $maps.Add([PSCustomObject]@{
                ProfilePropertyName    = $propertyName
                DataSourcePropertyName = $attribute
                Direction              = 'Import'
            })
    }
    return $maps.ToArray()
}
