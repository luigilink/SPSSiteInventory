function Get-SPSTargetProfile {
    <#
        .SYNOPSIS
        Returns the profile of a target mode: how the inventory words its categories and its waves.

        .DESCRIPTION
        The same inventory answers two questions, and the target mode says which one is asked:

        - SharePointOnline (the default): can each site collection move to SharePoint Online? A full-trust
          solution is a blocker there, and the categories are Simple, Moderate, Complex and Blocking.
        - SharePointOnPrem: is each site collection ready for the modern experience, and what does it take
          to modernize it where it is? A full-trust solution still runs, so it is not a blocker but code to
          rebuild with the SharePoint Framework (SPFx), and the categories are Modern-ready, Light
          remediation, Rebuild (SPFx) and Blocked.

        The four categories keep their numbers (1 to 4) in both modes, so a score, a wave mapping or a
        script that reads Category does not change. The mode changes the words: the name of each category,
        the file names of the pages of a split HTML report (the slug of the name), and the waves that the
        orchestrator plans when the settings have none. What counts as a blocker or as a weight is the
        Scoring section of the settings, which the preset of each mode ships.

        A mode that is not given is SharePointOnline, as in a settings file of a version that did not have
        it: the caller leaves the parameter out. A value that is given but is not one of the two names is
        rejected instead of being coerced, an empty one included: a misspelled mode would otherwise run as
        SharePointOnline without anybody having chosen it. The comparison ignores the case, and the profile
        returns the name in its canonical case.

        Private because it is an implementation detail of the settings loader, the scoring and the reports,
        which share it so that the names and the validation live in one place.

        .PARAMETER TargetMode
        The mode, 'SharePointOnline' (the default) or 'SharePointOnPrem', as a string.

        .OUTPUTS
        An object with TargetMode, DisplayName, CategoryName and CategorySlug (hashtables keyed by the
        category number 1 to 4) and MigrationWave (the default waves, as the settings give them).

        .EXAMPLE
        (Get-SPSTargetProfile -TargetMode 'SharePointOnPrem').CategoryName[3]
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Object]
        $TargetMode = 'SharePointOnline'
    )

    $definition = [ordered]@{
        SharePointOnline = @{
            DisplayName   = 'SharePoint Online migration'
            CategoryName  = @{ 1 = 'Simple'; 2 = 'Moderate'; 3 = 'Complex'; 4 = 'Blocking' }
            MigrationWave = @(
                @{ Wave = 1; Name = 'Quick wins'; Categories = @(1) }
                @{ Wave = 2; Name = 'Light remediation'; Categories = @(2) }
                @{ Wave = 3; Name = 'Rebuild'; Categories = @(3) }
                @{ Wave = 4; Name = 'Projects / blockers'; Categories = @(4) }
            )
        }
        SharePointOnPrem = @{
            DisplayName   = 'SharePoint on-premises modernization'
            CategoryName  = @{ 1 = 'Modern-ready'; 2 = 'Light remediation'; 3 = 'Rebuild (SPFx)'; 4 = 'Blocked' }
            MigrationWave = @(
                @{ Wave = 1; Name = 'Ready'; Categories = @(1) }
                @{ Wave = 2; Name = 'Light remediation'; Categories = @(2) }
                @{ Wave = 3; Name = 'Rebuild (SPFx)'; Categories = @(3) }
                @{ Wave = 4; Name = 'Blocked'; Categories = @(4) }
            )
        }
    }

    # A value that is not a string is refused as it is, not converted: an array of one name would pass as that name.
    $mode = $null
    if ($TargetMode -is [System.String]) {
        $mode = @($definition.Keys | Where-Object { $_ -ieq $TargetMode }) | Select-Object -First 1
    }
    if ($null -eq $mode) {
        throw "TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'."
    }

    $chosen = $definition[$mode]
    $slug = @{}
    foreach ($number in 1..4) {
        # A page of a split report is named after the category: lowercase, with letters and digits only.
        $slug[$number] = ($chosen.CategoryName[$number].ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    }

    [PSCustomObject]@{
        TargetMode    = $mode
        DisplayName   = $chosen.DisplayName
        CategoryName  = $chosen.CategoryName
        CategorySlug  = $slug
        MigrationWave = $chosen.MigrationWave
    }
}
