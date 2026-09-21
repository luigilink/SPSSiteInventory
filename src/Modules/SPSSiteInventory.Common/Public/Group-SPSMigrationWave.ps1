function Group-SPSMigrationWave {
    <#
        .SYNOPSIS
        Assigns a migration wave to each scored site from a category-to-wave mapping.

        .DESCRIPTION
        Group-SPSMigrationWave is a pure function (no SharePoint calls) so it can be unit
        tested without a farm. It takes the scored inventory records (each exposing a
        Category from 1 to 4) and a MigrationWaves mapping, and returns the same records
        with two properties added right after CategoryName: Wave (the wave number) and
        WaveName.

        In a SharePoint Server to SharePoint Online migration the migrated unit is the site
        collection, so waves are planned per site by complexity - not by content database,
        which is an on-premises storage concern with no equivalent in SharePoint Online.

        The mapping is configuration-driven: each wave lists the categories it contains, so
        an organization can choose a one-wave-per-category plan (the shipped default) or
        group several categories into a single wave (for example every non-blocking site in
        wave 1 and the blockers in wave 2) without any code change.

        A site whose category is not covered by the mapping is assigned Wave 0 /
        'Unassigned' so it is surfaced rather than silently dropped.

        .PARAMETER InputObject
        The scored inventory records to assign to waves.

        .PARAMETER MigrationWaves
        The wave mapping (from the settings). An array of entries, each with a Wave number,
        a Name and a Categories list, for example:
            @{ Wave = 1; Name = 'Quick wins'; Categories = @(1) }

        .EXAMPLE
        $waved = Group-SPSMigrationWave -InputObject $scored -MigrationWaves $settings.MigrationWaves
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $MigrationWaves
    )

    # Build a category -> wave lookup. Later entries win on duplicate categories.
    $lookup = @{}
    foreach ($wave in @($MigrationWaves)) {
        if ($null -eq $wave) { continue }
        $waveNumber = [int]$wave.Wave
        $waveName = [string]$wave.Name
        foreach ($category in @($wave.Categories)) {
            $lookup[[int]$category] = [PSCustomObject]@{ Wave = $waveNumber; Name = $waveName }
        }
    }

    $result = foreach ($record in @($InputObject)) {
        $category = if ($null -ne $record.Category) { [int]$record.Category } else { 0 }

        $waveNumber = 0
        $waveName = 'Unassigned'
        if ($lookup.ContainsKey($category)) {
            $waveNumber = $lookup[$category].Wave
            $waveName = $lookup[$category].Name
        }

        # Rebuild the record preserving column order, inserting Wave / WaveName right
        # after CategoryName (or at the end when that column is absent). Any pre-existing
        # Wave / WaveName is skipped so re-running with a different mapping actually
        # reassigns the site instead of keeping the stale values.
        $ordered = [ordered]@{}
        $inserted = $false
        foreach ($property in $record.PSObject.Properties) {
            if ($property.Name -eq 'Wave' -or $property.Name -eq 'WaveName') { continue }
            $ordered[$property.Name] = $property.Value
            if ($property.Name -eq 'CategoryName') {
                $ordered['Wave'] = $waveNumber
                $ordered['WaveName'] = $waveName
                $inserted = $true
            }
        }
        if (-not $inserted) {
            $ordered['Wave'] = $waveNumber
            $ordered['WaveName'] = $waveName
        }

        [PSCustomObject]$ordered
    }

    return @($result)
}
