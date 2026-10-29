function Get-SPSBuiltInProfilePropertyName {
    <#
        .SYNOPSIS
        Lists the names of the profile properties that SharePoint itself defines.

        .DESCRIPTION
        The User Profile service has no flag that tells a property that SharePoint ships from one that an
        administrator added. The names of the first ones are the static fields of
        Microsoft.Office.Server.UserProfiles.PropertyConstants (AccountName, FirstName, SPS-SipAddress,
        PhoneticFirstName and so on), so the values of those fields are the built-in names.

        The list is best effort: when the type cannot be found, or its fields cannot be read, the function
        returns $null and says why in the verbose stream, and the caller treats every property as a
        possible custom one instead of guessing. A string field is a name; the other fields are ignored.

        The function is read-only. Private because it is an implementation detail of
        Get-SPSProfilePropertyMapping.

        .OUTPUTS
        The names, as strings, or $null when they cannot be read.

        .EXAMPLE
        $builtIn = Get-SPSBuiltInProfilePropertyName
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param ()

    try {
        $typeName = 'Microsoft.Office.Server.UserProfiles.PropertyConstants'
        $constantsType = $typeName -as [System.Type]
        if ($null -eq $constantsType) {
            try {
                $null = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.Office.Server.UserProfiles')
            }
            catch {
                Write-Verbose -Message "The assembly of the User Profile service could not be loaded by its partial name: $($_.Exception.Message)"
            }
            $constantsType = $typeName -as [System.Type]
        }
        if ($null -eq $constantsType) {
            throw 'The PropertyConstants type is not available.'
        }

        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($field in $constantsType.GetFields([System.Reflection.BindingFlags]'Public,Static')) {
            $value = $field.GetValue($null)
            if ($value -is [System.String] -and -not [string]::IsNullOrWhiteSpace($value)) {
                $names.Add($value)
            }
        }
        if ($names.Count -eq 0) {
            throw 'The PropertyConstants type has no string field.'
        }
        return [string[]]$names.ToArray()
    }
    catch {
        Write-Verbose -Message "The built-in profile properties could not be listed: $($_.Exception.Message)"
        return $null
    }
}
