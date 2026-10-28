function Test-SPSBlockedAccessException {
    <#
        .SYNOPSIS
        Tells whether an exception is the error that SharePoint raises for a site collection locked with NoAccess.

        .DESCRIPTION
        SharePoint refuses every read of a site collection that is locked with NoAccess. The
        getters of its lock flags, its root web, its storage, its solutions and its webs all raise
        the same COM error, "Access to this Web site has been blocked" (HRESULT 0x81020071).
        PowerShell hides the exception of a .NET property getter as a $null when the property is
        read the usual way, so a lock read that way was reported as unknown.

        The HRESULT is what tells the error apart on every farm. The English text of the message
        is accepted too, in case the HRESULT was lost when the exception was wrapped; the message
        is localized with the language of the farm, so it is not enough on its own. The
        exception and its inner exceptions are checked.

        The other lock errors are not this one: for example a NoAdditions lock raises 0x81070966,
        "Additions to this Web site have been blocked", when something is added.

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Exception
        The exception to check. $null is not the blocked error.

        .EXAMPLE
        Test-SPSBlockedAccessException -Exception $_.Exception
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Exception]
        $Exception
    )

    # 0x81020071, written as the signed 32-bit number that Exception.HResult returns.
    $blockedHResult = -2130575247

    $current = $Exception
    while ($null -ne $current) {
        if ($current.HResult -eq $blockedHResult) {
            return $true
        }
        if ($current.Message -match 'Access to this Web site has been blocked') {
            return $true
        }
        $current = $current.InnerException
    }

    return $false
}
