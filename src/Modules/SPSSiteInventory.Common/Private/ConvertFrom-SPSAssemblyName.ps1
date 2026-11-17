function ConvertFrom-SPSAssemblyName {
    <#
        .SYNOPSIS
        Splits the display name of an assembly into its name, version, culture and public key token.

        .DESCRIPTION
        SharePoint stores the assembly of an event receiver as a display name, for example
        'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'. The text
        is split and nothing is loaded. The function does not throw, whatever the text: a value that
        someone typed by hand is read as far as it can be, and a part that is missing is an empty
        string. The public key token is in lower case, and it is empty for an assembly that is not
        signed (PublicKeyToken=null).

        Private because it is an implementation detail of the event receiver report.

        .PARAMETER DisplayName
        The display name of the assembly.

        .EXAMPLE
        ConvertFrom-SPSAssemblyName -DisplayName 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $DisplayName
    )

    $name = ''
    $version = ''
    $culture = ''
    $token = ''
    $part = @(([System.String]$DisplayName) -split ',')
    if ($part.Count -gt 0) {
        $name = $part[0].Trim()
    }
    for ($index = 1; $index -lt $part.Count; $index++) {
        $pair = $part[$index] -split '=', 2
        if ($pair.Count -ne 2) {
            continue
        }
        $key = $pair[0].Trim()
        $value = $pair[1].Trim()
        switch -Regex ($key) {
            '^Version$' { $version = $value }
            '^Culture$' { $culture = $value }
            '^PublicKeyToken$' { $token = if ($value -ieq 'null') { '' } else { $value.ToLowerInvariant() } }
        }
    }

    return [PSCustomObject]@{
        Name           = $name
        Version        = $version
        Culture        = $culture
        PublicKeyToken = $token
    }
}
