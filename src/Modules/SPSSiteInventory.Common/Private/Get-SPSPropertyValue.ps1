function Get-SPSPropertyValue {
    <#
        .SYNOPSIS
        Reads a property and lets an exception from its getter propagate.

        .DESCRIPTION
        PowerShell turns an exception thrown by a .NET property getter into $null, with no
        error even in strict mode. That is harmless when $null is never a valid value, but
        it makes a failed read indistinguishable from a property that is legitimately
        null (for example SPList.EmailAlias on a list without incoming e-mail).

        Get-SPSPropertyValue reads the property through reflection, so a failing getter
        raises the underlying exception while a successfully read null stays null. A
        property that is not a plain .NET property (for example a note property) is read
        the normal way. Use it only for scalar values where null is meaningful.

        Private because it is an implementation detail of the collectors.

        .PARAMETER InputObject
        The object to read the property from.

        .PARAMETER Name
        The property name.

        .EXAMPLE
        Get-SPSPropertyValue -InputObject $list -Name 'EmailAlias'
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Name
    )

    if ($null -eq $InputObject) {
        throw "The object to read '$Name' from is unavailable."
    }

    $baseObject = $InputObject.PSObject.BaseObject
    $property = $baseObject.GetType().GetProperty($Name, [System.Reflection.BindingFlags]'Public,Instance')
    if ($null -eq $property -or $property.GetIndexParameters().Count -gt 0) {
        return $InputObject.$Name
    }

    try {
        return $property.GetValue($baseObject, $null)
    }
    catch {
        throw $_.Exception.GetBaseException()
    }
}
