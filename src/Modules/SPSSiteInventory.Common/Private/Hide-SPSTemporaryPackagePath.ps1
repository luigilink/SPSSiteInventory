function Hide-SPSTemporaryPackagePath {
    <#
        .SYNOPSIS
        Takes the temporary folders of the scan out of the text of the package records, before they reach the reports.

        .DESCRIPTION
        The package files are sent, so they must not show the profile of the account that ran the scan. A
        package that was saved from the farm is read from a temporary folder, and a failure of the inspection
        quotes the path that it could not read in its Detail. The expansion of a package has a work folder
        in the temporary folder as well. This function changes the records, in place:

        - the PackagePath of a package that was saved from the farm (a path that has the name of Folder) says
          '(saved from the farm)' and the name of the package, because the folder is gone when the report is
          written;
        - Folder, where it appears in any text of a record (Detail, Difference, and the same texts of its
          assemblies and features), is replaced by '(saved from the farm)';
        - a work folder of the expansion (spswsp- and 32 hexadecimal digits, directly in WorkRoot) is replaced by
          '(work folder)'.

        Only these paths are replaced: a package that the user gave keeps its own path, also when it is in the
        temporary folder. A value that is not text is left as it is. The function goes down four levels of nested
        objects below a record, which is more than the records have, so that a loop of references cannot make it
        run for ever. It does not return anything.

        Private because it is an implementation detail of Invoke-SPSSiteInventory.ps1.

        .PARAMETER Record
        The package records (from Get-SPSSolutionPackageInfo).

        .PARAMETER Folder
        The folder where the scan saved the packages of the farm solutions. Leave it empty when it saved none.

        .PARAMETER WorkRoot
        The folder that holds the work folders of the expansion. Defaults to the temporary folder of the system,
        which is where Get-SPSSolutionPackageInfo expands the packages.

        .EXAMPLE
        Hide-SPSTemporaryPackagePath -Record $solutionPackages -Folder $exportFolder
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Record,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Folder,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $WorkRoot = [System.IO.Path]::GetTempPath()
    )

    $separator = @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $replacement = [System.Collections.Generic.List[object]]::new()
    $folderName = ''
    if (-not [System.String]::IsNullOrWhiteSpace($Folder)) {
        $folderText = $Folder.TrimEnd($separator)
        $folderName = [System.IO.Path]::GetFileName($folderText)
        $replacement.Add([PSCustomObject]@{ Pattern = [System.Text.RegularExpressions.Regex]::Escape($folderText); Text = '(saved from the farm)' })
    }
    if (-not [System.String]::IsNullOrWhiteSpace($WorkRoot)) {
        $rootText = $WorkRoot.TrimEnd($separator)
        $replacement.Add([PSCustomObject]@{ Pattern = [System.Text.RegularExpressions.Regex]::Escape($rootText) + '[\\/]spswsp-[0-9a-f]{32}'; Text = '(work folder)' })
    }

    $hide = {
        param ([System.String]$Text)
        $result = $Text
        foreach ($item in $replacement) {
            $result = [System.Text.RegularExpressions.Regex]::Replace($result, $item.Pattern, $item.Text, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        return $result
    }

    $visit = $null
    $visit = {
        param ($Object, [System.Int32]$Depth)
        if ($Depth -gt 4) {
            return
        }
        foreach ($property in @($Object.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })) {
            $value = $property.Value
            if ($value -is [System.String]) {
                $hidden = & $hide $value
                if ($hidden -cne $value) {
                    $property.Value = $hidden
                }
            }
            elseif ($value -is [System.Management.Automation.PSCustomObject]) {
                & $visit $value ($Depth + 1)
            }
            elseif ($value -is [System.Collections.IEnumerable]) {
                $item = @($value)
                $changed = $false
                for ($index = 0; $index -lt $item.Count; $index++) {
                    if ($item[$index] -is [System.String]) {
                        $hidden = & $hide $item[$index]
                        if ($hidden -cne $item[$index]) {
                            $item[$index] = $hidden
                            $changed = $true
                        }
                    }
                    elseif ($item[$index] -is [System.Management.Automation.PSCustomObject]) {
                        & $visit $item[$index] ($Depth + 1)
                    }
                }
                if ($changed) {
                    $property.Value = $item
                }
            }
        }
    }

    foreach ($package in @($Record | Where-Object { $null -ne $_ })) {
        if ($folderName.Length -gt 0 -and
            ([System.String]$package.PackagePath).IndexOf($folderName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $package.PackagePath = '(saved from the farm) ' + [System.String]$package.PackageName
        }
        & $visit $package 0
    }
}
