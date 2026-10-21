function Get-SPSActiveWorkflowAssociations {
    <#
        .SYNOPSIS
        Returns workflow associations that should count for migration complexity.

        .DESCRIPTION
        SharePoint can keep historical "previous version" associations beside the
        current workflow association. This helper keeps active associations and
        excludes historical ones when they can be identified through object metadata.

        Detection order:
        1. Explicit metadata (`IsCurrent = $false`, `IsLatestVersion = $false`).
        2. Name fallback only when metadata is unavailable: "BaseName (...:date...)"
           is treated as historical if another association exists with the same
           base name.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $WorkflowAssociations = @()
    )

    $associations = @($WorkflowAssociations | Where-Object { $null -ne $_ })
    if ($associations.Count -eq 0) {
        return $associations
    }

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($association in $associations) {
        $isHistorical = $false

        $isCurrentProperty = $association.PSObject.Properties['IsCurrent']
        if ($null -ne $isCurrentProperty -and $null -ne $isCurrentProperty.Value) {
            if (-not [bool]$isCurrentProperty.Value) {
                $isHistorical = $true
            }
        }

        if (-not $isHistorical) {
            $isLatestVersionProperty = $association.PSObject.Properties['IsLatestVersion']
            if ($null -ne $isLatestVersionProperty -and $null -ne $isLatestVersionProperty.Value) {
                if (-not [bool]$isLatestVersionProperty.Value) {
                    $isHistorical = $true
                }
            }
        }

        if (-not $isHistorical -and
            $null -eq $isCurrentProperty -and
            $null -eq $association.PSObject.Properties['IsLatestVersion']) {
            $name = [string]$association.Name
            $match = [System.Text.RegularExpressions.Regex]::Match(
                $name,
                '^(?<base>.+?)\s*\((?<meta>[^)]*:[^)]*\d{2,})\)$')

            if ($match.Success) {
                $baseName = $match.Groups['base'].Value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($baseName)) {
                    $hasBaseAssociation = @($associations | Where-Object {
                            $candidateName = [string]$_.Name
                            $candidateName.Trim().Equals($baseName, [System.StringComparison]::OrdinalIgnoreCase)
                        }).Count -gt 0
                    if ($hasBaseAssociation) {
                        $isHistorical = $true
                    }
                }
            }
        }

        if (-not $isHistorical) {
            $result.Add($association)
        }
    }

    return $result.ToArray()
}
