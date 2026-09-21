function Get-SPSInstalledProductVersion {
    <#
        .SYNOPSIS
        Returns the installed SharePoint product version from Microsoft.SharePoint.dll.

        .DESCRIPTION
        Reads the file version of the highest-numbered Microsoft.SharePoint.dll under
        the Web Server Extensions ISAPI folder. This is the most reliable way to tell
        whether SharePoint is installed on the host without loading any SharePoint
        command.

        Returns a [System.Diagnostics.FileVersionInfo], or $null when SharePoint is not
        installed on the host. The function is silent (no Write-Error) so callers can
        branch on $null themselves.

        .EXAMPLE
        $v = Get-SPSInstalledProductVersion
        if ($v) { "$($v.ProductMajorPart).$($v.ProductMinorPart).$($v.ProductBuildPart)" }
    #>
    [CmdletBinding()]
    [OutputType([System.Diagnostics.FileVersionInfo])]
    param ()

    $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
    $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue |
        Sort-Object { $_.Directory } -Descending |
        Select-Object -First 1

    if ($null -eq $fullPath) {
        Write-Verbose -Message 'SharePoint binary not found; SharePoint does not appear to be installed on this host.'
        return $null
    }

    return [System.Diagnostics.FileVersionInfo]::GetVersionInfo($fullPath.FullName)
}
