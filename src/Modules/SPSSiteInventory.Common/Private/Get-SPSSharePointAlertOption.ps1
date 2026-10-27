function Get-SPSSharePointAlertOption {
    <#
        .SYNOPSIS
        Reads and validates the SharePointAlerts section of the inventory settings.

        .DESCRIPTION
        The SharePointAlerts section holds the options of the SharePoint alerts report.
        IncludeUserLogin (default $true) says whether the login name of the owner of each
        alert is collected. A login name is personal data, so a value that is not a
        boolean is rejected instead of being coerced: the string 'false' would count as
        $true and collect the names the operator meant to leave out.

        Private because it is an implementation detail of the settings loader and of the
        collectors, which share it so that the default and the validation live in one place.

        .PARAMETER Settings
        The SharePointAlerts section, or nothing when the settings file has none.

        .EXAMPLE
        (Get-SPSSharePointAlertOption -Settings @{ IncludeUserLogin = $false }).IncludeUserLogin
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

    $includeUserLogin = $true
    if ($null -ne $Settings -and $Settings.Contains('IncludeUserLogin')) {
        $value = $Settings['IncludeUserLogin']
        if ($value -isnot [System.Boolean]) {
            throw 'SharePointAlerts.IncludeUserLogin must be $true or $false.'
        }
        $includeUserLogin = $value
    }

    [PSCustomObject]@{
        IncludeUserLogin = $includeUserLogin
    }
}
