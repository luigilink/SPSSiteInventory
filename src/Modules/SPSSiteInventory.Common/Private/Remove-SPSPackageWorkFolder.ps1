function Remove-SPSPackageWorkFolder {
    <#
        .SYNOPSIS
        Removes a temporary folder in which the scan saved the packages of the farm solutions.

        .DESCRIPTION
        The packages are the code of the solutions, so the folder is removed with its content as soon as
        they are read. The function only removes a folder that is exactly of the form that the scan gives
        it: it is directly in the temporary folder of the system, and its name is 'SPSSiteInventory-packages-'
        and 32 hexadecimal digits. It refuses any other, and a link, with a warning, so that a wrong path (the
        reports folder, for example) can never be deleted, and that a link is never followed.

        A virus scanner can hold a file for a moment, so the removal is tried three times. When the folder
        cannot be removed, a warning gives its path, so that it can be removed by hand.

        Returns $true when the folder is gone (it is also when it did not exist) and $false when it is
        still there, or was refused, or was not removed because of -WhatIf or -Confirm.

        Private because it is an implementation detail of Invoke-SPSSiteInventory.ps1.

        .PARAMETER Path
        The folder to remove.

        .EXAMPLE
        Remove-SPSPackageWorkFolder -Path $exportFolder
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path
    )

    $separator = @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $folder = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)).TrimEnd($separator)
    $parent = [System.IO.Path]::GetDirectoryName($folder)
    $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd($separator)
    $isScanFolder = ([System.IO.Path]::GetFileName($folder) -match '^SPSSiteInventory-packages-[0-9a-f]{32}$') -and
        $null -ne $parent -and [System.String]::Equals($parent.TrimEnd($separator), $temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $isScanFolder) {
        Write-Warning -Message "The folder '$folder' is not a temporary folder of the packages of the scan, so it is not removed."
        return $false
    }
    if (-not (Test-Path -LiteralPath $folder)) {
        return $true
    }
    if (((Get-Item -LiteralPath $folder -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Write-Warning -Message "The folder '$folder' is a link, not a folder that the scan made, so it is not removed."
        return $false
    }
    if (-not $PSCmdlet.ShouldProcess($folder, 'Remove the temporary folder of the packages of the farm solutions')) {
        return $false
    }

    for ($attempt = 1; $attempt -le 3 -and (Test-Path -LiteralPath $folder); $attempt++) {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $folder) {
            Start-Sleep -Milliseconds 250
        }
    }
    if (Test-Path -LiteralPath $folder) {
        Write-Warning -Message "The temporary folder '$folder' could not be removed. It holds the packages of the farm solutions: remove it by hand."
        return $false
    }

    return $true
}
