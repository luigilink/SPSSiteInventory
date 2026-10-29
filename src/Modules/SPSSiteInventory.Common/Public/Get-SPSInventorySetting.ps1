function Get-SPSInventorySetting {
    <#
        .SYNOPSIS
        Loads and validates an SPSSiteInventory settings file (.psd1).

        .DESCRIPTION
        Reads a PowerShell data file (see inventory-settings.example.psd1) and returns it
        as a hashtable. The function fails fast with a clear message when the file is
        missing or when the mandatory Scoring section is absent, so the orchestrator does
        not run with an incomplete configuration. The optional SharePointAlerts section is
        validated too: it must be a hashtable and IncludeUserLogin must be $true or $false.
        So is the optional Scope section: IncludePersonalSites and IncludeSiteMasters must
        be $true or $false. And the optional Report section: HtmlSplitThreshold must be a
        whole number from 0 to 10000000 and HtmlRowsPerPage one from 50 to 5000. And the optional
        top-level TargetMode, which must be 'SharePointOnline' (the default, also when the setting
        is missing) or 'SharePointOnPrem': the setting says whether the inventory prepares a
        migration to SharePoint Online or the modernization of the farm where it runs. A misspelled
        value is refused, because it would otherwise run as the default without anybody having
        chosen it.

        .PARAMETER Path
        Full path to the settings .psd1 file.

        .EXAMPLE
        $settings = Get-SPSInventorySetting -Path .\config\inventory-settings.psd1
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Inventory settings file not found: '$Path'. Copy inventory-settings.example.psd1 and adjust it."
    }

    $settings = Import-PowerShellDataFile -Path $Path -ErrorAction Stop

    if (-not $settings.ContainsKey('Scoring')) {
        throw "Inventory settings file '$Path' is missing the mandatory 'Scoring' section."
    }

    if ($settings.ContainsKey('TargetMode')) {
        try {
            $null = Get-SPSTargetProfile -TargetMode $settings['TargetMode']
        }
        catch {
            throw "Inventory settings file '$Path': $($_.Exception.Message)"
        }
    }

    if ($settings.ContainsKey('SharePointAlerts')) {
        if ($settings['SharePointAlerts'] -isnot [System.Collections.IDictionary]) {
            throw "Inventory settings file '$Path': the 'SharePointAlerts' section must be a hashtable."
        }
        try {
            $null = Get-SPSSharePointAlertOption -Settings $settings['SharePointAlerts']
        }
        catch {
            throw "Inventory settings file '$Path': $($_.Exception.Message)"
        }
    }

    if ($settings.ContainsKey('Scope')) {
        if ($settings['Scope'] -isnot [System.Collections.IDictionary]) {
            throw "Inventory settings file '$Path': the 'Scope' section must be a hashtable."
        }
        try {
            $null = Get-SPSScopeOption -Settings $settings['Scope']
        }
        catch {
            throw "Inventory settings file '$Path': $($_.Exception.Message)"
        }
    }

    if ($settings.ContainsKey('Report')) {
        if ($settings['Report'] -isnot [System.Collections.IDictionary]) {
            throw "Inventory settings file '$Path': the 'Report' section must be a hashtable."
        }
        try {
            $null = Get-SPSReportOption -Settings $settings['Report']
        }
        catch {
            throw "Inventory settings file '$Path': $($_.Exception.Message)"
        }
    }

    return $settings
}
