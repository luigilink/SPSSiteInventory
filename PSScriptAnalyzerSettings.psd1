@{
    # PSScriptAnalyzer settings for SPSSiteInventory.
    # Run locally with:
    #   Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
    Severity = @('Error', 'Warning')

    # PSUseSingularNouns is intentionally disabled. A few functions deliberately use a
    # plural noun because they act on a collection, mirroring built-in cmdlets such as
    # Compare-Object / Group-Object:
    #   - Compare-SPSJsonSnapshots (compares two snapshots)
    #   - Get-SPSUniqueUsers       (returns the unique user collection)
    ExcludeRules = @(
        'PSUseSingularNouns'
    )
}
