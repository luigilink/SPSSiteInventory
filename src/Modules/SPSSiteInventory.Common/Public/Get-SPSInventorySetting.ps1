function Get-SPSInventorySetting {
    <#
        .SYNOPSIS
        Loads and validates an SPSSiteInventory settings file (.psd1).

        .DESCRIPTION
        Reads a PowerShell data file (see inventory-settings.example.psd1) and returns it
        as a hashtable. The function fails fast with a clear message when the file is
        missing or when the mandatory Scoring section is absent, so the orchestrator does
        not run with an incomplete configuration.

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

    return $settings
}
