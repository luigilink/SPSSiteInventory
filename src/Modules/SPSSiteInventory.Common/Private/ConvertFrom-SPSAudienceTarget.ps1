function ConvertFrom-SPSAudienceTarget {
    <#
        .SYNOPSIS
        Splits the value of the audience targeting column of a list item into what the item targets.

        .DESCRIPTION
        The Target Audiences column (internal name Target_x0020_Audiences, and Audience in a Pages library)
        holds a string of three parts separated by two semicolons:

        1. the global audiences: the IDs of audiences of the User Profile service, separated by commas;
        2. the distribution lists and the security groups: distinguished names, separated by line breaks;
        3. the SharePoint groups: names, separated by commas.

        ';;;;' targets nothing, and ';;;;Owners' targets the SharePoint group Owners only. A part may be
        empty, the text may have spaces around the separators and a comma at the end (`GUID1,GUID2,;;;;`),
        so each value is trimmed and an empty one is left out. What is in the first part and is not a
        GUID is kept apart, so that nothing that the column holds is lost. A value that is $null or empty
        is a value that targets nothing.

        The function is pure: it reads no farm. Private because it is an implementation detail of
        Get-SPSSiteCustomization.

        .PARAMETER Value
        The value of the column, as a string. $null and an empty string are accepted.

        .OUTPUTS
        A PSCustomObject with AudienceId (GUIDs, in lower case), DistributionList (distinguished names),
        SharePointGroup (names), Unrecognized (what the first part holds that is not a GUID) and IsEmpty
        ($true when the value targets nothing). Each is listed once, in the order of the value.

        .EXAMPLE
        ConvertFrom-SPSAudienceTarget -Value 'a88b9dcb-0000-0000-0000-000000000001;;cn=all developers,ou=lists;;Owners'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Value
    )

    $text = if ($null -eq $Value) { '' } else { $Value }
    # At most three parts: a separator that comes after the third part belongs to it.
    $parts = [System.Text.RegularExpressions.Regex]::new(';;').Split($text, 3)
    $audienceText = $parts[0]
    $listText = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    $groupText = if ($parts.Count -gt 2) { $parts[2] } else { '' }

    $add = {
        param ([System.Collections.Generic.List[string]] $Target, [System.Collections.Generic.HashSet[string]] $Seen, [System.String] $Entry)
        if ($Entry.Length -gt 0 -and $Seen.Add($Entry)) {
            $Target.Add($Entry)
        }
    }

    $audienceId = [System.Collections.Generic.List[string]]::new()
    $audienceSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $unrecognized = [System.Collections.Generic.List[string]]::new()
    $unrecognizedSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($token in ($audienceText -split ',')) {
        $trimmed = $token.Trim()
        $guid = [guid]::Empty
        if ($trimmed.Length -eq 0) {
            continue
        }
        if ([guid]::TryParse($trimmed, [ref]$guid)) {
            & $add $audienceId $audienceSeen $guid.ToString('D')
        }
        else {
            & $add $unrecognized $unrecognizedSeen $trimmed
        }
    }

    $distributionList = [System.Collections.Generic.List[string]]::new()
    $listSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($token in ($listText -split '\r\n|\r|\n')) {
        & $add $distributionList $listSeen $token.Trim()
    }

    $sharePointGroup = [System.Collections.Generic.List[string]]::new()
    $groupSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($token in ($groupText -split ',')) {
        & $add $sharePointGroup $groupSeen $token.Trim()
    }

    [PSCustomObject]@{
        AudienceId       = [string[]]$audienceId.ToArray()
        DistributionList = [string[]]$distributionList.ToArray()
        SharePointGroup  = [string[]]$sharePointGroup.ToArray()
        Unrecognized     = [string[]]$unrecognized.ToArray()
        IsEmpty          = ($audienceId.Count + $distributionList.Count + $sharePointGroup.Count + $unrecognized.Count) -eq 0
    }
}
