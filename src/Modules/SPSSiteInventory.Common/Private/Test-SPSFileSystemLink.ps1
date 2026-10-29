function Test-SPSFileSystemLink {
    <#
        .SYNOPSIS
        Says whether a file or a folder is a symbolic link or a junction.

        .DESCRIPTION
        A package that is already expanded in a folder is not trusted, and a link in it can lead out of
        the package: a symbolic link or a junction to a file or a folder anywhere. Test-SPSFileSystemLink
        tells such an item from a plain one, so that the readers of a package do not follow it.

        Only symbolic links and junctions count. The other reparse points are not links to somewhere
        else (a placeholder of a cloud file that is not downloaded yet, for example) and are read as
        any file.

        Private because it is an implementation detail of Get-SPSExpandedPackageInfo.

        .PARAMETER Item
        The file or the folder, as returned by Get-Item or Get-ChildItem.

        .OUTPUTS
        System.Boolean

        .EXAMPLE
        Test-SPSFileSystemLink -Item (Get-Item -LiteralPath .\Feature.xml -Force)
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $Item
    )

    if ($null -eq $Item) {
        return $false
    }
    # The attribute is cheap to read: the type of link is only asked for what can be a link.
    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
        return $false
    }
    return (@('SymbolicLink', 'Junction') -contains [System.String]$Item.LinkType)
}
