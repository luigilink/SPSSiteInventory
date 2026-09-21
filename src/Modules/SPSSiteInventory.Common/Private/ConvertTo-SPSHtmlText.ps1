function ConvertTo-SPSHtmlText {
    <#
        .SYNOPSIS
        Encodes a value for safe inclusion in HTML text or attributes.

        .DESCRIPTION
        ConvertTo-SPSHtmlText is a pure helper (no SharePoint calls) used by the HTML
        report generator. It escapes the five characters that would otherwise break the
        markup or allow injection: &, <, >, " and '. A $null value becomes an empty
        string. The order matters: ampersands are escaped first so the entities added by
        the following replacements are not double-escaped.

        Kept as a private function because it is an implementation detail of
        ConvertTo-SPSInventoryHtml and never needs to be called directly.

        .PARAMETER Value
        The value to encode. Non-string values are converted with ToString() first.

        .EXAMPLE
        ConvertTo-SPSHtmlText -Value 'A & B <tag>'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Position = 0)]
        [AllowNull()]
        [System.Object]
        $Value
    )

    if ($null -eq $Value) { return '' }

    $text = [string]$Value

    $text = $text.Replace('&', '&amp;')
    $text = $text.Replace('<', '&lt;')
    $text = $text.Replace('>', '&gt;')
    $text = $text.Replace('"', '&quot;')
    $text = $text.Replace("'", '&#39;')

    return $text
}
