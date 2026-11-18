# LowerBoundSignals reaches the files of the report pack that hold a signal whose scan can reach a cap. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-Site {
        param ([string]$Name, [string]$LowerBound)
        [PSCustomObject]@{
            InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$Name"; Title = $Name; WebApp = 'Intranet'; WebAppUrl = 'https://intranet'
            AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Score = 0; Wave = 1; WaveName = 'Quick wins'
            SizeGB = 1; Template = 'STS#0'; Reasons = ''; FileVersionCount = 7; LowerBoundSignals = $LowerBound
        }
    }
}

Describe 'Export-SPSInventoryReport and the lower bounds' {
    It 'writes the column in the CSV, in the JSON of the inventory and in the datasets that hold a signal with a cap' {
        $sites = @((New-Site -Name 'finance' -LowerBound 'FileVersionCount; HtmlFileCount'), (New-Site -Name 'hr' -LowerBound ''))

        $output = Export-SPSInventoryReport -InputObject $sites -OutputFolder (Join-Path $TestDrive 'a') -BaseName 'Lb'

        $csv = @(Import-Csv -Path $output.CsvPath)
        $csv[0].LowerBoundSignals | Should -Be 'FileVersionCount; HtmlFileCount'
        $csv[1].LowerBoundSignals | Should -Be ''
        foreach ($path in @($output.JsonPath, $output.SitesJsonPath, $output.PublishingJsonPath, $output.PermissionsJsonPath, $output.LargeContentJsonPath, $output.CollaborationJsonPath)) {
            $rows = Get-Content -Path $path -Raw | ConvertFrom-Json
            $rows[0].LowerBoundSignals | Should -Be 'FileVersionCount; HtmlFileCount' -Because $path
            $rows[1].LowerBoundSignals | Should -Be '' -Because $path
        }
    }

    It 'leaves the column out of the datasets that hold no signal with a cap' {
        $output = Export-SPSInventoryReport -InputObject @((New-Site -Name 'finance' -LowerBound 'FileVersionCount')) -OutputFolder (Join-Path $TestDrive 'b') -BaseName 'Lb'

        foreach ($path in @($output.AuthJsonPath, $output.WorkflowsJsonPath, $output.AppsJsonPath, $output.IrmLocksJsonPath)) {
            $rows = Get-Content -Path $path -Raw | ConvertFrom-Json
            @($rows)[0].PSObject.Properties.Name | Should -Not -Contain 'LowerBoundSignals' -Because $path
        }
    }

    It 'writes an empty value for a record that has no such column' {
        $record = New-Site -Name 'old' -LowerBound ''
        $record.PSObject.Properties.Remove('LowerBoundSignals')

        $output = Export-SPSInventoryReport -InputObject @($record) -OutputFolder (Join-Path $TestDrive 'c') -BaseName 'Lb'

        $rows = Get-Content -Path $output.LargeContentJsonPath -Raw | ConvertFrom-Json
        @($rows)[0].PSObject.Properties.Name | Should -Contain 'LowerBoundSignals'
        @($rows)[0].LowerBoundSignals | Should -BeNullOrEmpty
    }
}
