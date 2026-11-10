# Tests for the event receiver files of Export-SPSInventoryReport: the CSV and JSON files, the manifest, what it returns and the HTML section.
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

    function New-Row {
        param ([string]$Site = 'https://intranet/sites/team', [string]$Class = 'Contoso.Intranet.ItemReceiver', [int]$Receivers = 6, [int]$Lists = 2, [string]$Solution = '')
        [PSCustomObject]@{
            SiteUrl = $Site; Assembly = 'Contoso.Intranet, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'; AssemblyName = 'Contoso.Intranet'
            AssemblyVersion = '1.0.0.0'; PublicKeyToken = '0123456789abcdef'; Class = $Class; ReceiverCount = $Receivers; ListCount = $Lists
            EventTypes = 'ItemAdded; ItemUpdated'; FirstListUrl = '/sites/team/Lists/Tasks'; SolutionMatch = $(if ($Solution) { 'AssemblyNameAndKey' } else { 'NotChecked' })
            FarmSolutionName = $Solution; PackageName = $(if ($Solution) { 'Contoso.Intranet.wsp' } else { '' })
        }
    }

    $script:Site = [PSCustomObject]@{
        InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/team'; Title = 'Team'; WebApp = 'Intranet'
        AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
        EventReceivers = 6
    }
    $script:Columns = 'SiteUrl,Assembly,AssemblyName,AssemblyVersion,PublicKeyToken,Class,ReceiverCount,ListCount,EventTypes,FirstListUrl,SolutionMatch,FarmSolutionName,PackageName'
}

Describe 'Export-SPSInventoryReport event receivers' {
    It 'writes the CSV and the JSON file in the output folder, with the base name and the time stamp of the run, and returns their paths' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -EventReceiverClasses @((New-Row)) -OutputFolder (Join-Path $TestDrive 'a') -BaseName 'Rec'

        foreach ($path in @($output.EventReceiversCsvPath, $output.EventReceiversJsonPath)) {
            $path | Should -Exist
            (Split-Path -Path $path -Parent) | Should -Be (Join-Path $TestDrive 'a')
        }
        $stamp = (Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json).Timestamp
        (Split-Path -Path $output.EventReceiversCsvPath -Leaf) | Should -Be ('Rec-eventreceivers-{0}.csv' -f $stamp)
        (Split-Path -Path $output.EventReceiversJsonPath -Leaf) | Should -Be ('Rec-eventreceivers-{0}.json' -f $stamp)
    }

    It 'writes one row for each assembly and class, with the columns of the rows' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -EventReceiverClasses @((New-Row), (New-Row -Class 'Contoso.Intranet.Other' -Receivers 1 -Lists 1 -Solution 'contoso.intranet.wsp')) -OutputFolder (Join-Path $TestDrive 'b') -BaseName 'Rows'

        (Get-Content -Path $output.EventReceiversCsvPath -TotalCount 1) | Should -BeExactly ('"' + ($script:Columns -split ',' -join '","') + '"')
        $csv = @(Import-Csv -Path $output.EventReceiversCsvPath)
        $csv | Should -HaveCount 2
        $csv[0].Class | Should -Be 'Contoso.Intranet.ItemReceiver'
        $csv[0].ReceiverCount | Should -Be '6'
        $csv[0].EventTypes | Should -Be 'ItemAdded; ItemUpdated'
        $csv[0].SolutionMatch | Should -BeExactly 'NotChecked'
        $csv[1].FarmSolutionName | Should -Be 'contoso.intranet.wsp'
        $csv[1].PackageName | Should -Be 'Contoso.Intranet.wsp'
        $json = @(Read-JsonRow -Path $output.EventReceiversJsonPath)
        $json | Should -HaveCount 2
        $json[1].Class | Should -Be 'Contoso.Intranet.Other'
        $json[1].ReceiverCount | Should -Be 1
    }

    It 'writes a valid empty report, with the columns, when the parameter is given with no row' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -EventReceiverClasses @() -OutputFolder (Join-Path $TestDrive 'c') -BaseName 'Empty'

        (Get-Content -Path $output.EventReceiversCsvPath -Raw).Trim() | Should -BeExactly ('"' + ($script:Columns -split ',' -join '","') + '"')
        @(Read-JsonRow -Path $output.EventReceiversJsonPath) | Should -HaveCount 0
    }

    It 'lists the files in the manifest' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -EventReceiverClasses @((New-Row)) -OutputFolder (Join-Path $TestDrive 'd') -BaseName 'Manifest'

        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json

        $manifest.Files.EventReceiversCsv | Should -Be $output.EventReceiversCsvPath
        $manifest.Files.EventReceiversJson | Should -Be $output.EventReceiversJsonPath
        $manifest.ReportPackVersion | Should -Be '1.0'
    }

    It 'writes no file, and lists none, when the parameter is not given' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -OutputFolder (Join-Path $TestDrive 'e') -BaseName 'None'

        $output.EventReceiversCsvPath | Should -BeNullOrEmpty
        $output.EventReceiversJsonPath | Should -BeNullOrEmpty
        @(Get-ChildItem -Path (Join-Path $TestDrive 'e') -Filter '*eventreceivers*') | Should -HaveCount 0
        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Files.EventReceiversCsv | Should -BeNullOrEmpty
        $manifest.Files.EventReceiversJson | Should -BeNullOrEmpty
    }

    It 'neutralizes a cell that a spreadsheet could read as a formula' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -EventReceiverClasses @((New-Row -Class '=HYPERLINK("http://example.invalid")')) -OutputFolder (Join-Path $TestDrive 'f') -BaseName 'Formula'

        @(Import-Csv -Path $output.EventReceiversCsvPath)[0].Class | Should -Be '''=HYPERLINK("http://example.invalid")'
    }

    It 'adds the Custom event receivers section to the HTML report when there is a row, and not otherwise' {
        $with = Export-SPSInventoryReport -InputObject @($script:Site) -EventReceiverClasses @((New-Row)) -OutputFolder (Join-Path $TestDrive 'g') -BaseName 'With'
        $without = Export-SPSInventoryReport -InputObject @($script:Site) -EventReceiverClasses @() -OutputFolder (Join-Path $TestDrive 'h') -BaseName 'Without'
        $absent = Export-SPSInventoryReport -InputObject @($script:Site) -OutputFolder (Join-Path $TestDrive 'i') -BaseName 'Absent'

        (Get-Content -Path $with.HtmlPath -Raw) | Should -Match '<h2 id="custom-event-receivers">Custom event receivers</h2>'
        (Get-Content -Path $without.HtmlPath -Raw) | Should -Not -Match 'custom-event-receivers'
        (Get-Content -Path $absent.HtmlPath -Raw) | Should -Not -Match 'custom-event-receivers'
    }

    It 'does not touch the files of the other datasets, which are the same with or without the rows' {
        $without = Export-SPSInventoryReport -InputObject @($script:Site) -OutputFolder (Join-Path $TestDrive 'j') -BaseName 'Same'
        $with = Export-SPSInventoryReport -InputObject @($script:Site) -EventReceiverClasses @((New-Row)) -OutputFolder (Join-Path $TestDrive 'k') -BaseName 'Same'

        (Get-Content -Path $with.CsvPath -Raw) | Should -Be (Get-Content -Path $without.CsvPath -Raw)
        (Get-Content -Path $with.SitesJsonPath -Raw) | Should -Be (Get-Content -Path $without.SitesJsonPath -Raw)
    }
}
