function Export-SPSInventoryReport {
    <#
        .SYNOPSIS
        Exports the scored inventory to CSV and JSON.

        .DESCRIPTION
        Writes the consolidated inventory (one record per site, including the complexity
        category and score) to a CSV file for review in Excel and to a JSON file for
        downstream automation (for example feeding the migration wave planning). Both
        files are written to the output folder, which is created when missing.

        A self-contained HTML report is planned for a later version; for V1 the CSV/JSON
        pair keeps the tool scriptable and diff-friendly.

        Returns a PSCustomObject with the two output paths.

        .PARAMETER InputObject
        The scored inventory records to export.

        .PARAMETER OutputFolder
        Folder where the CSV and JSON files are written.

        .PARAMETER BaseName
        Base file name (without extension). Defaults to 'SPSSiteInventory'. A timestamp
        is appended to keep successive runs side by side.

        .EXAMPLE
        Export-SPSInventoryReport -InputObject $scored -OutputFolder C:\Inventory
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object[]]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFolder,

        [Parameter()]
        [System.String]
        $BaseName = 'SPSSiteInventory'
    )

    if (-not (Test-Path -Path $OutputFolder)) {
        $null = New-Item -Path $OutputFolder -ItemType Directory -Force
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $csvPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-{1}.csv' -f $BaseName, $timestamp)
    $jsonPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-{1}.json' -f $BaseName, $timestamp)

    $InputObject | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $InputObject | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

    return [PSCustomObject]@{
        CsvPath  = $csvPath
        JsonPath = $jsonPath
    }
}
