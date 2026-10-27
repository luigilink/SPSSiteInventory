function Group-SPSAssessmentWarning {
    <#
        .SYNOPSIS
        Groups the repeated assessment warnings of one site collection.

        .DESCRIPTION
        Two warnings are of the same kind when they are equal once the single-quoted
        names of their subject (list title, web URL) are replaced by a placeholder. The
        subject ends at the first quoted name that is followed by a colon, and what comes
        after that colon, the reason, is compared as it is, with its own quoted values,
        so different failures are never merged. A warning without such a colon has all
        its quoted names replaced. A quote is an opening quote after a space or a
        parenthesis, and a closing quote when no letter, digit or quote follows it, so
        that the apostrophe of a title such as 'Manager's Documents' does not end it.
        Digits and the rest of the text are compared as they are.

        The kinds are returned in the order of their first appearance. A kind that
        occurs once is returned unchanged; a kind that occurs N times is returned as
        its first occurrence followed by ' [+N-1 similar]'. Null and empty entries are
        ignored. A warning is never split on semicolons.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [System.String[]]
        $Warning
    )

    $getKind = {
        param ([System.String] $Text)

        $length = $Text.Length
        $kind = [System.Text.StringBuilder]::new()
        $position = 0
        while ($position -lt $length) {
            $close = -1
            if ($Text[$position] -eq [char]39 -and ($position -eq 0 -or [char]::IsWhiteSpace($Text[$position - 1]) -or $Text[$position - 1] -eq [char]40)) {
                for ($index = $position + 1; $index -lt $length; $index++) {
                    if ($Text[$index] -ne [char]39) {
                        continue
                    }
                    if ($index + 1 -eq $length -or -not ([char]::IsLetterOrDigit($Text[$index + 1]) -or $Text[$index + 1] -eq [char]39)) {
                        $close = $index
                        break
                    }
                }
            }
            if ($close -lt 0) {
                [void]$kind.Append($Text[$position])
                $position++
                continue
            }

            [void]$kind.Append("'?'")
            $position = $close + 1
            if ($position + 1 -lt $length -and $Text[$position] -eq [char]58 -and $Text[$position + 1] -eq [char]32) {
                # The subject ends here: the reason that follows is compared as it is.
                [void]$kind.Append($Text.Substring($position))
                break
            }
        }

        return $kind.ToString()
    }

    $kinds = [System.Collections.Specialized.OrderedDictionary]::new()
    foreach ($entry in $Warning) {
        if ([string]::IsNullOrEmpty($entry)) {
            continue
        }

        $kind = & $getKind $entry
        if ($kinds.Contains($kind)) {
            $kinds[$kind].Count++
        }
        else {
            $kinds[$kind] = [PSCustomObject]@{ First = $entry; Count = 1 }
        }
    }

    foreach ($group in $kinds.Values) {
        if ($group.Count -gt 1) {
            '{0} [+{1} similar]' -f $group.First, ($group.Count - 1)
        }
        else {
            $group.First
        }
    }
}
