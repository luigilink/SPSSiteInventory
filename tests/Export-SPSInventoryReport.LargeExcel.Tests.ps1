# The large Excel files signal reaches the files of the report pack and the alerts. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-Site {
        param ([string]$Name, [int]$Count, [string]$Examples)
        [PSCustomObject]@{
            InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$Name"; Title = $Name; WebApp = 'Intranet'; WebAppUrl = 'https://intranet'
            AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Score = 0; Wave = 1; WaveName = 'Quick wins'
            SizeGB = 1; Template = 'STS#0'; Reasons = ''; LargeExcelFileCount = $Count; LargeExcelFileExamples = $Examples
        }
    }
}

Describe 'Export-SPSInventoryReport and the large Excel files' {
    It 'writes the count and the examples in the CSV, the JSON and the large-content dataset' {
        $sites = @((New-Site -Name 'finance' -Count 2 -Examples '/sites/finance/Docs/budget.xlsx (12.5 MB); /sites/finance/Docs/model.xlsx (40 MB)'), (New-Site -Name 'hr' -Count 0 -Examples ''))

        $output = Export-SPSInventoryReport -InputObject $sites -OutputFolder (Join-Path $TestDrive 'excel') -BaseName 'Excel'

        $csv = @(Import-Csv -Path $output.CsvPath)
        $csv[0].LargeExcelFileCount | Should -Be '2'
        $csv[0].LargeExcelFileExamples | Should -Be '/sites/finance/Docs/budget.xlsx (12.5 MB); /sites/finance/Docs/model.xlsx (40 MB)'
        $dataset = Get-Content -Path $output.LargeContentJsonPath -Raw | ConvertFrom-Json
        $dataset[0].LargeExcelFileCount | Should -Be 2
        $dataset[0].LargeExcelFileExamples | Should -Match 'budget\.xlsx \(12\.5 MB\)'
        $dataset[1].LargeExcelFileCount | Should -Be 0
        $main = Get-Content -Path $output.JsonPath -Raw | ConvertFrom-Json
        $main[0].LargeExcelFileCount | Should -Be 2
    }

    It 'raises the LargeExcelFiles alert, Low in both modes, with the original text first in the default mode' {
        $sites = @((New-Site -Name 'finance' -Count 1 -Examples '/sites/finance/Docs/budget.xlsx (12.5 MB)'))

        $online = Export-SPSInventoryReport -InputObject $sites -OutputFolder (Join-Path $TestDrive 'online') -BaseName 'Online'
        $onPrem = Export-SPSInventoryReport -InputObject $sites -OutputFolder (Join-Path $TestDrive 'onprem') -BaseName 'OnPrem' -TargetMode 'SharePointOnPrem'

        $onlineAlert = (Get-Content -Path $online.AlertsJsonPath -Raw | ConvertFrom-Json) | Where-Object AlertType -eq 'LargeExcelFiles'
        $onPremAlert = (Get-Content -Path $onPrem.AlertsJsonPath -Raw | ConvertFrom-Json) | Where-Object AlertType -eq 'LargeExcelFiles'
        $onlineAlert.Severity | Should -Be 'Low'
        $onlineAlert.Value | Should -Be 1
        $onlineAlert.Message | Should -Match '^Large Excel workbooks were detected'
        $onPremAlert.Severity | Should -Be 'Low'
        $onPremAlert.Message | Should -Match '^Migration to SharePoint Online only\. Large Excel workbooks were detected'
        (Get-Content -Path $online.HtmlPath -Raw) | Should -Match 'data-ind="large-excel"'
    }

    It 'raises no alert for a site collection without large workbooks' {
        $output = Export-SPSInventoryReport -InputObject @((New-Site -Name 'quiet' -Count 0 -Examples '')) -OutputFolder (Join-Path $TestDrive 'quiet') -BaseName 'Quiet'

        $alerts = Get-Content -Path $output.AlertsJsonPath -Raw | ConvertFrom-Json
        @($alerts | Where-Object AlertType -eq 'LargeExcelFiles') | Should -HaveCount 0
    }
}
