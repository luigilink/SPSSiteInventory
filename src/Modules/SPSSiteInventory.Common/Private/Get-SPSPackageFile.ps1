function Get-SPSPackageFile {
    <#
        .SYNOPSIS
        Lists the files of an expanded package, without following a link.

        .DESCRIPTION
        Walks the folder of an expanded package and returns every file, the hidden and the system ones
        too: a hidden DLL is still a DLL of the package, and the assessment must see it. A symbolic link
        or a junction is not followed and is returned apart: its target can be anywhere, and a package
        that is not trusted can be made of links that lead out of it (or round and round).

        Private because it is an implementation detail of Get-SPSExpandedPackageInfo.

        .PARAMETER Root
        The folder that holds the expanded package.

        .OUTPUTS
        An object with File (the files) and Link (the full path of every link that was left alone).

        .EXAMPLE
        (Get-SPSPackageFile -Root $folder).File | Where-Object { $_.Extension -ieq '.dll' }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Root
    )

    $file = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $link = [System.Collections.Generic.List[System.String]]::new()
    $pending = [System.Collections.Generic.Stack[System.String]]::new()
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        $folder = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force)) {
            if (Test-SPSFileSystemLink -Item $item) {
                $link.Add($item.FullName)
            }
            elseif ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            }
            else {
                $file.Add($item)
            }
        }
    }

    return [PSCustomObject]@{
        File = $file.ToArray()
        Link = $link.ToArray()
    }
}
