function Save-SPSFarmSolutionPackage {
    <#
        .SYNOPSIS
        Saves the package (WSP) of each farm solution in a folder, to inspect them offline.

        .DESCRIPTION
        Reads the solutions of the farm with Get-SPSolution and saves the file of each one with
        SolutionFile.SaveAs, as the wiki tells to do by hand. Nothing is changed in the farm: the file
        of a solution is only read.

        Each package is saved under the name of its solution. A name that does not end in .wsp gets that
        extension, because the inspection of a folder reads .wsp and .cab files. A character that a
        file name cannot hold is replaced by an underscore, so that a package is never written outside
        the folder. A name that is taken, which only happens when two names become the same, gets a number
        before the extension, so that a package never replaces another one.

        The folder is created when it is missing, and not when the farm has no solution. A solution whose
        package cannot be saved does not stop the others: it is listed in Failure with the reason, and
        the partial file that it left is removed.

        Returns an object with Path (the full path of the folder), Requested (the number of solutions),
        Saved (the number of packages that were saved) and Failure (an entry with Name and Reason for
        each package that was not saved, with the message of the error that SharePoint or the file system
        gave). The function throws when the solutions of the farm cannot be read, or when the folder
        cannot be created.

        Private because it is an implementation detail of Invoke-SPSSiteInventory.ps1.

        .PARAMETER Path
        The folder where the packages are saved. A relative path is read from the current location.

        .PARAMETER Solution
        Optional. The solutions to save (SPSolution objects). By default, all the solutions of the farm
        (Get-SPSolution).

        .EXAMPLE
        Save-SPSFarmSolutionPackage -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'SPSSiteInventory-packages-1')
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter()]
        [AllowNull()]
        [System.Object[]]
        $Solution
    )

    # SaveAs is a .NET method: it reads a relative path from the directory of the process, not from the location of PowerShell.
    $folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not $PSBoundParameters.ContainsKey('Solution')) {
        $Solution = @(Get-SPSolution -ErrorAction Stop)
    }
    $solutionList = @($Solution | Where-Object { $null -ne $_ })

    $failure = [System.Collections.Generic.List[object]]::new()
    $saved = 0
    if ($solutionList.Count -gt 0) {
        # CreateDirectory throws on every platform when a file is in the way; New-Item -Force does not always.
        $null = [System.IO.Directory]::CreateDirectory($folder)
        foreach ($item in $solutionList) {
            $name = [System.String]$item.Name
            $target = $null
            try {
                if ($null -eq $item.SolutionFile) {
                    throw 'The solution has no package file.'
                }
                $baseName = [System.Text.RegularExpressions.Regex]::Replace($name, '[\\/:*?"<>|\x00-\x1f]', '_').Trim().TrimEnd('.', ' ')
                if ([System.String]::IsNullOrWhiteSpace($baseName)) {
                    $baseName = 'solution'
                }
                if ($baseName -notmatch '\.wsp$') {
                    $baseName += '.wsp'
                }
                $stem = $baseName.Substring(0, $baseName.Length - 4)
                $fileName = $baseName
                $number = 1
                while (Test-Path -LiteralPath ([System.IO.Path]::Combine($folder, $fileName))) {
                    $number++
                    $fileName = '{0}-{1}.wsp' -f $stem, $number
                }
                $target = [System.IO.Path]::Combine($folder, $fileName)
                $item.SolutionFile.SaveAs($target)
                if (-not (Test-Path -LiteralPath $target)) {
                    throw 'The package file was not written.'
                }
                $saved++
                Write-Verbose -Message ("Saved the package of the farm solution '{0}' as '{1}'." -f $name, $fileName)
            }
            catch {
                if ($null -ne $target -and (Test-Path -LiteralPath $target)) {
                    Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                }
                # PowerShell wraps the exception of a .NET method: the reason is the one that is inside.
                $reason = $_.Exception.Message
                if ($_.Exception -is [System.Management.Automation.MethodInvocationException] -and $null -ne $_.Exception.InnerException) {
                    $reason = $_.Exception.InnerException.Message
                }
                $failure.Add([PSCustomObject]@{ Name = $name; Reason = $reason })
            }
        }
    }

    return [PSCustomObject]@{
        Path      = $folder
        Requested = $solutionList.Count
        Saved     = $saved
        Failure   = $failure.ToArray()
    }
}
