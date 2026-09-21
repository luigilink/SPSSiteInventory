function Test-SPSCustomAssembly {
    <#
        .SYNOPSIS
        Tells whether an assembly strong name belongs to custom (non-Microsoft) code.

        .DESCRIPTION
        Test-SPSCustomAssembly is a pure helper (no SharePoint calls) used to tell an
        out-of-the-box SharePoint artifact from a custom one by looking at the assembly it
        lives in. Out-of-the-box event receivers, for example, are registered from
        Microsoft assemblies (Microsoft.SharePoint*, Microsoft.Office*); a custom receiver
        comes from a third-party or in-house assembly.

        Returns $true when the assembly is custom (should be counted as a migration
        signal), $false for a Microsoft assembly or an empty/unknown value (conservative:
        an unknown assembly is not counted, to avoid inflating the signal).

        Private because it is an implementation detail of Get-SPSSiteCustomization.

        .PARAMETER Assembly
        The assembly strong name, e.g. 'Microsoft.SharePoint, Version=16.0.0.0,
        Culture=neutral, PublicKeyToken=71e9bce111e9429c' or 'Contoso.Intranet, ...'.

        .EXAMPLE
        Test-SPSCustomAssembly -Assembly $eventReceiver.Assembly
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Position = 0)]
        [AllowNull()]
        [System.Object]
        $Assembly
    )

    $name = [string]$Assembly
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }

    $name = $name.TrimStart()

    # Out-of-the-box SharePoint / Office artifacts are registered from Microsoft
    # assemblies (Microsoft.SharePoint*, Microsoft.Office*, ...). No third-party or
    # in-house code signs its assembly under the Microsoft namespace, so treating any
    # 'Microsoft.*' assembly as non-custom is both safe and robust. -match is
    # case-insensitive by default.
    if ($name -match '^Microsoft\.') { return $false }

    return $true
}
