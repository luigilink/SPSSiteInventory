# The audience targeting and site notebook signals reach the files of the report pack, the alerts and the risk indicators of the
# HTML report. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # Windows PowerShell 5.1 does not unroll a JSON array in a pipeline, so the rows are read with foreach.
    function Read-JsonRow {
        param ([string]$Path)
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($row in (Get-Content -Path $Path -Raw | ConvertFrom-Json)) { $rows.Add($row) }
        return $rows.ToArray()
    }

    function New-Site {
        param ([string]$Name, [int]$Items = 0, [int]$Lists = 0, [string]$ItemExamples = '', [int]$Notebooks = 0, [string]$NotebookExamples = '')
        [PSCustomObject]@{
            InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$Name"; Title = $Name; WebApp = 'Intranet'; WebAppUrl = 'https://intranet'
            AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Score = 0; Wave = 1; WaveName = 'Quick wins'
            SizeGB = 1; Template = 'STS#0'; Reasons = ''
            AudienceTargetedListCount = $Lists; AudienceTargetedItemCount = $Items; AudienceTargetedExamples = $ItemExamples
            SiteNotebookCount = $Notebooks; SiteNotebookExamples = $NotebookExamples
        }
    }
}

Describe 'Export-SPSInventoryReport and the collaboration signals' {
    It 'writes the counts and the examples in the CSV, the JSON and the collaboration dataset, and lists the dataset in the manifest' {
        $sites = @(
            (New-Site -Name 'sales' -Items 12 -Lists 2 -ItemExamples '/sites/sales/Lists/News (7 item(s): Sales, Marketing)' -Notebooks 1 -NotebookExamples '/sites/sales/SiteAssets/Sales Notebook')
            (New-Site -Name 'hr')
        )

        $output = Export-SPSInventoryReport -InputObject $sites -OutputFolder (Join-Path $TestDrive 'collab') -BaseName 'Collab'

        $csv = @(Import-Csv -Path $output.CsvPath)
        $csv[0].AudienceTargetedItemCount | Should -Be '12'
        $csv[0].AudienceTargetedListCount | Should -Be '2'
        $csv[0].AudienceTargetedExamples | Should -Be '/sites/sales/Lists/News (7 item(s): Sales, Marketing)'
        $csv[0].SiteNotebookCount | Should -Be '1'
        $csv[0].SiteNotebookExamples | Should -Be '/sites/sales/SiteAssets/Sales Notebook'
        $dataset = @(Read-JsonRow -Path $output.CollaborationJsonPath)
        $dataset | Should -HaveCount 2
        $dataset[0].Url | Should -Be 'https://intranet/sites/sales'
        $dataset[0].AudienceTargetedItemCount | Should -Be 12
        $dataset[0].AudienceTargetedListCount | Should -Be 2
        $dataset[0].AudienceTargetedExamples | Should -Match 'Sales, Marketing'
        $dataset[0].SiteNotebookCount | Should -Be 1
        $dataset[0].SiteNotebookExamples | Should -Match 'Sales Notebook'
        $dataset[1].AudienceTargetedItemCount | Should -Be 0
        $dataset[1].SiteNotebookCount | Should -Be 0
        (Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json).Files.CollaborationJson | Should -Be $output.CollaborationJsonPath
        (Get-Content -Path $output.JsonPath -Raw | ConvertFrom-Json)[0].SiteNotebookCount | Should -Be 1
    }

    It 'writes the dataset for a failed assessment, where the signals are not known' {
        $failed = New-Site -Name 'failed'
        $failed.AssessmentStatus = 'Failed'
        $failed.AudienceTargetedItemCount = $null
        $failed.SiteNotebookCount = $null

        $output = Export-SPSInventoryReport -InputObject @($failed) -OutputFolder (Join-Path $TestDrive 'failed') -BaseName 'Failed'

        $dataset = @(Read-JsonRow -Path $output.CollaborationJsonPath)
        $dataset | Should -HaveCount 1
        $dataset[0].AssessmentStatus | Should -Be 'Failed'
        $dataset[0].AudienceTargetedItemCount | Should -BeNullOrEmpty
        $dataset[0].SiteNotebookCount | Should -BeNullOrEmpty
    }

    It 'raises the AudienceTargeting alert (Medium) and the SiteNotebook alert (Low), with the original text first in the default mode and the migration-only words in the other' {
        $sites = @((New-Site -Name 'sales' -Items 12 -Lists 2 -Notebooks 1))

        $online = Export-SPSInventoryReport -InputObject $sites -OutputFolder (Join-Path $TestDrive 'online') -BaseName 'Online'
        $onPrem = Export-SPSInventoryReport -InputObject $sites -OutputFolder (Join-Path $TestDrive 'onprem') -BaseName 'OnPrem' -TargetMode 'SharePointOnPrem'

        $onlineAlerts = @(Read-JsonRow -Path $online.AlertsJsonPath)
        $onPremAlerts = @(Read-JsonRow -Path $onPrem.AlertsJsonPath)
        $audience = @($onlineAlerts | Where-Object AlertType -eq 'AudienceTargeting')
        $notebook = @($onlineAlerts | Where-Object AlertType -eq 'SiteNotebook')
        $audience | Should -HaveCount 1
        $audience[0].Severity | Should -Be 'Medium'
        $audience[0].Value | Should -Be 12
        $audience[0].Message | Should -Match '^List items that target audiences were detected'
        $notebook | Should -HaveCount 1
        $notebook[0].Severity | Should -Be 'Low'
        $notebook[0].Value | Should -Be 1
        $notebook[0].Message | Should -Match '^Site notebooks were detected'
        foreach ($type in @('AudienceTargeting', 'SiteNotebook')) {
            $alert = @($onPremAlerts | Where-Object AlertType -eq $type)
            $alert | Should -HaveCount 1
            $alert[0].Severity | Should -Be 'Low'
            $alert[0].Message | Should -Match '^Migration to SharePoint Online only\. '
        }
    }

    It 'adds a risk indicator for each signal to the HTML report' {
        $sites = @((New-Site -Name 'sales' -Items 12 -Lists 2 -Notebooks 1), (New-Site -Name 'hr'))

        $html = Get-Content -Path (Export-SPSInventoryReport -InputObject $sites -OutputFolder (Join-Path $TestDrive 'html') -BaseName 'Html').HtmlPath -Raw

        $html | Should -Match 'data-ind="audience-targeting"'
        $html | Should -Match 'data-ind="site-notebook"'
        $html | Should -Match 'Sites with audience-targeted items'
        $html | Should -Match 'Sites with a site notebook'
    }

    It 'raises no alert for a site collection without audience-targeted items or notebooks' {
        $output = Export-SPSInventoryReport -InputObject @((New-Site -Name 'quiet')) -OutputFolder (Join-Path $TestDrive 'quiet') -BaseName 'Quiet'

        $alerts = @(Read-JsonRow -Path $output.AlertsJsonPath)
        @($alerts | Where-Object { $_.AlertType -in @('AudienceTargeting', 'SiteNotebook') }) | Should -HaveCount 0
    }
}
