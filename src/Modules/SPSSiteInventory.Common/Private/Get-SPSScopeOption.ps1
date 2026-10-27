function Get-SPSScopeOption {
    <#
        .SYNOPSIS
        Reads and validates the Scope section of the inventory settings.

        .DESCRIPTION
        The Scope section says which site collections the inventory covers.
        IncludePersonalSites (default $false) keeps the personal sites (My Sites) in the
        inventory, and IncludeSiteMasters (default $false) keeps the site masters, the hidden
        site collections that SharePoint creates to speed up the creation of personal sites.
        Both are left out by default, also when the section is missing, as in a 1.x settings
        file. A value that is not a boolean is rejected instead of being coerced: the string
        'false' would count as $true and bring back the sites the operator meant to leave out.

        Private because it is an implementation detail of the settings loader and of the
        orchestrator, which share it so that the default and the validation live in one place.

        .PARAMETER Settings
        The Scope section, or nothing when the settings file has none.

        .EXAMPLE
        (Get-SPSScopeOption -Settings @{ IncludePersonalSites = $true }).IncludePersonalSites
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Collections.IDictionary]
        $Settings = @{}
    )

    $option = @{
        IncludePersonalSites = $false
        IncludeSiteMasters = $false
    }
    foreach ($name in @('IncludePersonalSites', 'IncludeSiteMasters')) {
        if ($null -ne $Settings -and $Settings.Contains($name)) {
            $value = $Settings[$name]
            if ($value -isnot [System.Boolean]) {
                throw ('Scope.{0} must be $true or $false.' -f $name)
            }
            $option[$name] = $value
        }
    }

    [PSCustomObject]@{
        IncludePersonalSites = $option['IncludePersonalSites']
        IncludeSiteMasters = $option['IncludeSiteMasters']
    }
}
