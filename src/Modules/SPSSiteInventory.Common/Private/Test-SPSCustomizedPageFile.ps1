function Test-SPSCustomizedPageFile {
    <#
        .SYNOPSIS
        Tells whether a file is a customized (unghosted) page that migration would revert.

        .DESCRIPTION
        SPFile.CustomizedPageStatus is a flags enumeration (None = 0, Uncustomized = 1,
        Customized = 2). A page edited with a tool such as SharePoint Designer becomes
        Customized and is reverted to its default state during migration. Following the
        SMAT Customized Pages scan, files last modified by the SharePoint System Account
        (SHAREPOINT\system) are ignored. When ModifiedBy cannot be read the file stays in
        scope, because the customization itself is still real.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER File
        The SPFile to evaluate.

        .EXAMPLE
        Test-SPSCustomizedPageFile -File $web.Files[0]
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $File
    )

    if ($null -eq $File -or $null -eq $File.PSObject.Properties['CustomizedPageStatus']) {
        return $false
    }

    $status = $File.CustomizedPageStatus
    $isCustomized = if ($status -is [System.String]) {
        ($status -split '\s*,\s*') -contains 'Customized'
    }
    else {
        ([int]$status -band 2) -eq 2
    }
    if (-not $isCustomized) {
        return $false
    }

    try {
        $modifiedBy = if ($null -ne $File.PSObject.Properties['ModifiedBy']) { $File.ModifiedBy } else { $null }
        if ($null -ne $modifiedBy -and
            $null -ne $modifiedBy.PSObject.Properties['LoginName'] -and
            [string]$modifiedBy.LoginName -eq 'SHAREPOINT\system') {
            return $false
        }
    }
    catch {
        return $true
    }

    return $true
}
