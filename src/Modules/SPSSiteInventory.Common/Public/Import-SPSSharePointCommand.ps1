function Import-SPSSharePointCommand {
    <#
        .SYNOPSIS
        Loads the SharePoint Server PowerShell commands into the current session.

        .DESCRIPTION
        SPSSiteInventory reads the farm object model (site collections, features, farm
        solutions), which requires the on-premises SharePoint commands. On SharePoint
        Server 2016 and 2019 these are exposed through the Microsoft.SharePoint.PowerShell
        PSSnapin; on Subscription Edition the SharePointServer module is also available.

        The function is idempotent (it does nothing when the commands are already loaded)
        and throws a clear error when SharePoint is not installed on the host, so the
        orchestrator can stop before attempting any farm call.

        .EXAMPLE
        Import-SPSSharePointCommand
    #>
    [CmdletBinding()]
    param ()

    if (Get-Command -Name 'Get-SPWebApplication' -ErrorAction SilentlyContinue) {
        Write-Verbose -Message 'SharePoint commands are already available in this session.'
        return
    }

    if ($null -eq (Get-SPSInstalledProductVersion)) {
        throw 'SharePoint does not appear to be installed on this host. Run SPSSiteInventory on a SharePoint farm server.'
    }

    # Prefer the module (Subscription Edition), fall back to the PSSnapin (2016/2019).
    if (Get-Module -ListAvailable -Name 'SharePointServer' -ErrorAction SilentlyContinue) {
        Import-Module -Name 'SharePointServer' -DisableNameChecking -ErrorAction Stop
    }
    elseif (Get-PSSnapin -Registered -Name 'Microsoft.SharePoint.PowerShell' -ErrorAction SilentlyContinue) {
        Add-PSSnapin -Name 'Microsoft.SharePoint.PowerShell' -ErrorAction Stop
    }
    else {
        throw 'Neither the SharePointServer module nor the Microsoft.SharePoint.PowerShell snap-in is registered on this host.'
    }
}
