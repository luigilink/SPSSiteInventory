function Group-SPSAssessmentWarning {
    <#
        .SYNOPSIS
        Groups the repeated assessment warnings of one site collection.

        .DESCRIPTION
        Two warnings are of the same kind when they are equal once every single-quoted
        token (list title, web URL) is replaced by a placeholder. Digits and the rest of
        the text are compared as they are, so different failures are never merged.

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

    $kinds = [System.Collections.Specialized.OrderedDictionary]::new()
    foreach ($entry in $Warning) {
        if ([string]::IsNullOrEmpty($entry)) {
            continue
        }

        $kind = [regex]::Replace($entry, "'[^']*'", "'?'")
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
