function ConvertTo-SPSCsvSafeRecord {
    <#
        .SYNOPSIS
        Neutralizes spreadsheet formulas in the text cells of a record before it is written to a CSV file.

        .DESCRIPTION
        The CSV reports are meant to be opened in a spreadsheet, and text typed by the users of the
        farm reaches them: site, list and content type titles, alert titles and filters, and so on. A
        spreadsheet reads a cell that starts with =, +, - or @, or with a tab, a carriage return or a
        line feed (some programs trim them and read what follows), as a formula; some locales also
        read the full-width forms of = + - and @ (U+FF1D, U+FF0B, U+FF0D and U+FF20) that way. A user
        could therefore craft a value, such as a HYPERLINK or a DDE formula, that runs on the machine
        of the administrator who opens the file (CSV injection, CWE-1236). The characters are the ones
        the OWASP CSV injection guidance lists.

        Each property of the record whose value is a string that starts with one of those characters
        gets a single quote in front, as the OWASP guidance recommends: the spreadsheet then reads the
        cell as text. Values that are not strings (numbers, including negative ones, booleans, dates
        and GUIDs) are left alone, so a spreadsheet still reads a number as a number; a string is
        always checked, because text typed by a user cannot be told from a number.

        OWASP states that no CSV sanitization is safe for every spreadsheet. In particular, Excel can
        drop the quote when a file is saved as CSV and opened again, which would turn such a cell back
        into a formula: these files are for reading, and the JSON files hold the data. Export-Csv
        writes every field between double quotes and doubles the quotes in the text, so a comma or a
        quote typed by a user stays inside its cell for a spreadsheet that reads the file as the
        comma-separated CSV it is.

        The record is copied, with the same property names in the same order: the original, which also
        feeds the JSON files, is not changed, and neither is a cell that does not start with one of the
        characters, so the function can be applied twice without adding a second quote. The header row
        is not touched because its names come from the toolkit, not from users.

        Private because it is an implementation detail of the exporters.

        .PARAMETER InputObject
        The record to protect. Pass the records through the pipeline.

        .EXAMPLE
        $rows | Select-Object -Property $columns | ConvertTo-SPSCsvSafeRecord | Export-Csv -Path $path -NoTypeInformation
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [System.Object]
        $InputObject
    )

    begin {
        $formulaStart = '^[=+\-@\t\r\n\uFF1D\uFF0B\uFF0D\uFF20]'
    }

    process {
        foreach ($record in @($InputObject)) {
            if ($null -eq $record) {
                continue
            }

            $safe = [ordered]@{}
            foreach ($property in $record.PSObject.Properties) {
                $value = $property.Value
                if ($value -is [System.String] -and [System.Text.RegularExpressions.Regex]::IsMatch($value, $formulaStart)) {
                    $value = "'" + $value
                }
                $safe[$property.Name] = $value
            }
            [PSCustomObject]$safe
        }
    }
}
