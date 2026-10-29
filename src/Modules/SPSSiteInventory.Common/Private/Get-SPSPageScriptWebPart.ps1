function Get-SPSPageScriptWebPart {
    <#
        .SYNOPSIS
        Lists the Script Editor and Content Editor web parts that carry script on a page.

        .DESCRIPTION
        Opens the web part manager of the shared view of the page, reads its web parts and asks
        Get-SPSScriptWebPartKind about each one. It returns one text per web part found
        ('Script Editor' or 'Content Editor') and nothing for a page without such a web part,
        which a page that holds no web part at all (a modern page, whose content is not in web
        part zones) is.

        The web part manager and the web it opens are disposed, also when a read fails, as
        SharePoint requires. A manager or a collection of web parts that is unavailable is an
        error, not an empty page: PowerShell turns an exception of a getter into $null, and a
        page that could not be read must not look like one without script. The caller decides
        what an error means for the assessment.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER File
        The page, an SPFile.

        .EXAMPLE
        @(Get-SPSPageScriptWebPart -File $web.GetFile('SitePages/Home.aspx'))
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $File
    )

    $manager = $null
    try {
        # The scope is passed as text, which PowerShell converts: the type of the enumeration lives in
        # System.Web, which is not always loaded.
        $manager = $File.GetLimitedWebPartManager('Shared')
        if ($null -eq $manager) {
            throw 'The web part manager is unavailable.'
        }
        $webParts = $manager.WebParts
        if ($null -eq $webParts) {
            throw 'The web part collection is unavailable.'
        }

        $kinds = [System.Collections.Generic.List[string]]::new()
        foreach ($webPart in $webParts) {
            $kind = Get-SPSScriptWebPartKind -WebPart $webPart
            if (-not [string]::IsNullOrEmpty($kind)) {
                $kinds.Add($kind)
            }
        }
        return $kinds.ToArray()
    }
    finally {
        if ($null -ne $manager) {
            # SharePoint creates a web for the manager and says to dispose of it, and of the manager.
            try {
                if ($null -ne $manager.PSObject.Properties['Web'] -and $null -ne $manager.Web) {
                    $manager.Web.Dispose()
                }
                if ($null -ne $manager.PSObject.Methods['Dispose']) {
                    $manager.Dispose()
                }
            }
            catch {
                Write-Verbose -Message "The web part manager could not be disposed: $($_.Exception.Message)"
            }
        }
    }
}
