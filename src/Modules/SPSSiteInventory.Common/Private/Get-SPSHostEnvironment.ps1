function Get-SPSHostEnvironment {
    <#
        .SYNOPSIS
        Describes the PowerShell host and the session that runs the toolkit.

        .DESCRIPTION
        Returns the PowerShell edition and version, the computer and account names, and whether
        the session is elevated. IsElevated is $null when it cannot be determined, which is the
        case outside Windows. The function only reads the session. It exists so that the readiness
        checks can be tested without depending on the host that runs the tests.

        .EXAMPLE
        Get-SPSHostEnvironment
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param ()

    # PSEdition and Platform do not exist in every PowerShell version: a missing key reads as $null.
    $edition = if ([System.String]::IsNullOrEmpty([System.String]$PSVersionTable.PSEdition)) { 'Desktop' } else { [System.String]$PSVersionTable.PSEdition }
    $isWindowsHost = ($edition -eq 'Desktop') -or ([System.String]$PSVersionTable.Platform -eq 'Win32NT')

    $isElevated = $null
    $userName = [System.Environment]::UserName
    if ($isWindowsHost) {
        try {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object -TypeName System.Security.Principal.WindowsPrincipal -ArgumentList $identity
            $isElevated = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
            $userName = $identity.Name
        }
        catch {
            Write-Verbose -Message "The elevation of the session could not be determined: $($_.Exception.Message)"
        }
    }

    [PSCustomObject]@{
        Edition      = $edition
        Version      = $PSVersionTable.PSVersion.ToString()
        VersionMajor = [System.Int32]$PSVersionTable.PSVersion.Major
        VersionMinor = [System.Int32]$PSVersionTable.PSVersion.Minor
        ComputerName = [System.Environment]::MachineName
        UserName     = $userName
        IsElevated   = $isElevated
    }
}
