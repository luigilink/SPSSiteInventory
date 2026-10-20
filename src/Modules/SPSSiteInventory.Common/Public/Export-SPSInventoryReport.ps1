function Export-SPSInventoryReport {
    <#
        .SYNOPSIS
        Exports the scored inventory to CSV and JSON.

        .DESCRIPTION
        Writes the consolidated inventory (one record per site, including the complexity
        category and score) to three files in the output folder (created when missing):

        - a CSV file for review in Excel;
        - a JSON file for downstream automation (for example feeding migration wave
          planning);
        - a self-contained HTML report (Aptos style, category summary box) for sharing
          with stakeholders without any external tooling.

        Returns a PSCustomObject with the three output paths.

        .PARAMETER InputObject
        The scored inventory records to export.

        .PARAMETER OutputFolder
        Folder where the CSV, JSON and HTML files are written.

        .PARAMETER BaseName
        Base file name (without extension). Defaults to 'SPSSiteInventory'. A timestamp
        is appended to keep successive runs side by side.

        .PARAMETER EnvName
        Optional environment identifier shown in the HTML report header (for example
        'PROD').

        .PARAMETER SolutionMap
        Optional farm-solution (WSP) records (from Get-SPSFarmSolutionMap). When provided,
        the HTML report includes a "Farm solutions (WSP)" section.

        .PARAMETER ContentTypes
        Optional content-type definitions and list bindings collected with the site
        signals. When supplied, adds a content-type HTML section and dedicated
        -contenttypes CSV/JSON files, including valid empty reports.

        .EXAMPLE
        Export-SPSInventoryReport -InputObject $scored -OutputFolder C:\Inventory
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFolder,

        [Parameter()]
        [System.String]
        $BaseName = 'SPSSiteInventory',

        [Parameter()]
        [System.String]
        $EnvName = '',

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [System.Object[]]
        $SolutionMap = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $ContentTypes = @()
    )

    if (-not (Test-Path -Path $OutputFolder)) {
        $null = New-Item -Path $OutputFolder -ItemType Directory -Force
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $csvPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-{1}.csv' -f $BaseName, $timestamp)
    $jsonPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-{1}.json' -f $BaseName, $timestamp)
    $htmlPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-{1}.html' -f $BaseName, $timestamp)

    $InputObject | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    ConvertTo-Json -InputObject @($InputObject) -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

    $htmlParams = @{
        InputObject = @($InputObject)
        EnvName = $EnvName
        SolutionMap = @($SolutionMap)
    }
    $contentTypesCsvPath = $null
    $contentTypesJsonPath = $null
    if ($PSBoundParameters.ContainsKey('ContentTypes')) {
        $htmlParams['ContentTypes'] = @($ContentTypes)
        $contentTypesCsvPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-contenttypes-{1}.csv' -f $BaseName, $timestamp)
        $contentTypesJsonPath = Join-Path -Path $OutputFolder -ChildPath ('{0}-contenttypes-{1}.json' -f $BaseName, $timestamp)
        $columns = @(
            'SiteUrl', 'WebUrl', 'Scope', 'ListTitle', 'ListUrl', 'ContentTypeId', 'Name',
            'Group', 'ParentContentTypeId', 'FieldCount', 'FieldTypes',
            'DocumentTemplateUrl', 'Hidden', 'ReadOnly', 'Sealed'
        )
        if ($ContentTypes.Count -gt 0) {
            $ContentTypes | Select-Object -Property $columns |
                Export-Csv -Path $contentTypesCsvPath -NoTypeInformation -Encoding UTF8
        }
        else {
            Set-Content -Path $contentTypesCsvPath -Value ('"' + ($columns -join '","') + '"') -Encoding UTF8
        }
        ConvertTo-Json -InputObject @($ContentTypes) -Depth 6 |
            Set-Content -Path $contentTypesJsonPath -Encoding UTF8
    }

    $html = ConvertTo-SPSInventoryHtml @htmlParams
    $html | Set-Content -Path $htmlPath -Encoding UTF8

    return [PSCustomObject]@{
        CsvPath  = $csvPath
        JsonPath = $jsonPath
        HtmlPath = $htmlPath
        ContentTypesCsvPath = $contentTypesCsvPath
        ContentTypesJsonPath = $contentTypesJsonPath
    }
}
