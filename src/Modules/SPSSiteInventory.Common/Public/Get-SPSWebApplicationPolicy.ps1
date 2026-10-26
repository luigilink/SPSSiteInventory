function Get-SPSWebApplicationPolicy {
    <#
        .SYNOPSIS
        Reads the permission policies and browser file handling of a web application.

        .DESCRIPTION
        Web application policies grant or deny permissions to users across every site
        collection of the web application and override site-level permissions. They are
        not migrated to SharePoint Online. The function returns the policies that apply
        to all zones plus the policies of every configured zone, and the Browser File
        Handling setting (Strict or Permissive). SharePoint Online enforces Strict, so
        .htm and .html files that open in the browser from a Permissive web application
        prompt a download after migration.

        Policies include the accounts SharePoint itself adds (for example the farm and
        search crawl accounts), so a count above zero is expected.

        Unreadable settings terminate collection rather than being reported as no
        policies, because PowerShell turns an exception thrown by a property getter into
        $null. No credentials are read.

        .PARAMETER WebApplication
        An SPWebApplication object returned by Get-SPWebApplication.

        .EXAMPLE
        Get-SPWebApplication | ForEach-Object { Get-SPSWebApplicationPolicy -WebApplication $_ }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $WebApplication
    )

    $browserFileHandling = $WebApplication.BrowserFileHandling
    if ($null -eq $browserFileHandling) {
        throw "Could not read the browser file handling setting for '$($WebApplication.Url)'."
    }

    $allZonePolicies = $WebApplication.Policies
    if ($null -eq $allZonePolicies) {
        throw "The web application policies are unavailable for '$($WebApplication.Url)'."
    }
    $zones = $WebApplication.IisSettings.Keys
    if ($null -eq $zones) {
        throw "No configured zones could be read for '$($WebApplication.Url)'."
    }

    $collections = [System.Collections.Generic.List[object]]::new()
    $collections.Add([PSCustomObject]@{ Zone = 'All zones'; Policies = $allZonePolicies })
    foreach ($zone in @($zones | Sort-Object)) {
        $zonePolicies = $WebApplication.ZonePolicies($zone)
        if ($null -eq $zonePolicies) {
            throw "The policies of zone '$zone' are unavailable for '$($WebApplication.Url)'."
        }
        $collections.Add([PSCustomObject]@{ Zone = [string]$zone; Policies = $zonePolicies })
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($collection in $collections) {
        foreach ($policy in $collection.Policies) {
            $userName = [string]$policy.UserName
            if ([string]::IsNullOrWhiteSpace($userName)) {
                throw "A policy user name could not be read for '$($WebApplication.Url)' ($($collection.Zone))."
            }
            $bindings = $policy.PolicyRoleBindings
            if ($null -eq $bindings) {
                throw "The permission policy levels of '$userName' could not be read for '$($WebApplication.Url)'."
            }

            $rows.Add([PSCustomObject]@{
                    Zone         = $collection.Zone
                    DisplayName  = [string]$policy.DisplayName
                    UserName     = $userName
                    IsSystemUser = [bool]$policy.IsSystemUser
                    Roles        = (@($bindings | ForEach-Object { [string]$_.Name }) -join ', ')
                })
        }
    }

    $examples = @(
        $rows | Select-Object -First 10 | ForEach-Object {
            $label = '{0}: {1}' -f $_.UserName, $_.Roles
            if ($_.Zone -ne 'All zones') { $label += ' [{0}]' -f $_.Zone }
            $label
        }
    )

    [PSCustomObject]@{
        BrowserFileHandling  = [string]$browserFileHandling
        WebAppPolicyCount    = $rows.Count
        WebAppPolicyExamples = ($examples -join '; ')
        Policies             = $rows.ToArray()
    }
}
