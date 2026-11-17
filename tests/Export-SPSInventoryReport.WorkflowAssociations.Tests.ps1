# Tests for the workflow association files of Export-SPSInventoryReport: the CSV and JSON files, the manifest, what it returns and the HTML section.
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
        param ([string]$Name = 'Approval', [string]$Scope = 'List', [string]$List = 'Documents', [int]$Running = 3, [bool]$Counted = $true)
        [PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team'; Scope = $Scope; ListTitle = $List
            ListUrl = $(if ($List) { '/sites/team/Shared Documents' } else { '' }); WorkflowName = $Name; Counted = $Counted; RunningInstances = $Running
        }
    }

    $script:Site = [PSCustomObject]@{
        InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/team'; Title = 'Team'; WebApp = 'Intranet'
        AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
        Workflow2010Count = 1; Workflow2010RunningInstanceCount = 3; Workflow2010Examples = 'Approval (list Documents, https://intranet/sites/team): 3 running instance(s)'
    }
    $script:Columns = 'SiteUrl,WebUrl,Scope,ListTitle,ListUrl,WorkflowName,Counted,RunningInstances'
}

Describe 'Export-SPSInventoryReport workflow associations' {
    It 'puts the new parameter after the ones that it already had, because none has a position and they are positional in the order of declaration' {
        $common = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm')
        $name = @((Get-Command -Name Export-SPSInventoryReport).Parameters.Keys | Where-Object { $common -notcontains $_ })
        $before = @(
            'InputObject', 'OutputFolder', 'BaseName', 'EnvName', 'SolutionMap', 'ContentTypes', 'ManagedMetadataLists', 'ExternalLists', 'SharePointAlerts',
            'BcsApplications', 'BcsInventoryComplete', 'SecureStoreApplications', 'SecureStoreInventoryComplete', 'ProfilePropertyMappings', 'ProfileInventoryComplete',
            'SolutionJsonPath', 'ExcludedPersonalSiteCount', 'ExcludedSiteMasterCount', 'HtmlSplitThreshold', 'HtmlRowsPerPage', 'TargetMode', 'SolutionPackages', 'EventReceiverClasses'
        )

        @($name[0..($before.Count - 1)]) | Should -BeExactly $before
        $name[$before.Count] | Should -BeExactly 'WorkflowAssociations'
    }

    It 'writes the CSV and the JSON file in the output folder, with the base name and the time stamp of the run, and returns their paths' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -WorkflowAssociations @((New-Row)) -OutputFolder (Join-Path $TestDrive 'a') -BaseName 'Wf'

        foreach ($path in @($output.WorkflowAssociationsCsvPath, $output.WorkflowAssociationsJsonPath)) {
            $path | Should -Exist
            (Split-Path -Path $path -Parent) | Should -Be (Join-Path $TestDrive 'a')
        }
        $stamp = (Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json).Timestamp
        (Split-Path -Path $output.WorkflowAssociationsCsvPath -Leaf) | Should -BeExactly ('Wf-workflow-associations-{0}.csv' -f $stamp)
        (Split-Path -Path $output.WorkflowAssociationsJsonPath -Leaf) | Should -BeExactly ('Wf-workflow-associations-{0}.json' -f $stamp)
    }

    It 'writes one row for each association, with the columns of the rows' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -WorkflowAssociations @((New-Row), (New-Row -Name 'Publication' -Scope 'Web' -List '' -Running 0 -Counted $false)) -OutputFolder (Join-Path $TestDrive 'b') -BaseName 'Rows'

        (Get-Content -Path $output.WorkflowAssociationsCsvPath -TotalCount 1) | Should -BeExactly ('"' + ($script:Columns -split ',' -join '","') + '"')
        $csv = @(Import-Csv -Path $output.WorkflowAssociationsCsvPath)
        $csv | Should -HaveCount 2
        $csv[0].WorkflowName | Should -Be 'Approval'
        $csv[0].Scope | Should -BeExactly 'List'
        $csv[0].ListTitle | Should -Be 'Documents'
        $csv[0].ListUrl | Should -Be '/sites/team/Shared Documents'
        $csv[0].Counted | Should -BeExactly 'True'
        $csv[0].RunningInstances | Should -Be '3'
        $csv[1].Scope | Should -BeExactly 'Web'
        $csv[1].ListTitle | Should -Be ''
        $csv[1].Counted | Should -BeExactly 'False'
        $json = @(Read-JsonRow -Path $output.WorkflowAssociationsJsonPath)
        $json | Should -HaveCount 2
        $json[1].WorkflowName | Should -Be 'Publication'
        $json[1].Counted | Should -BeFalse
        $json[0].RunningInstances | Should -Be 3
    }

    It 'writes a valid empty report, with the columns, when the parameter is given with no row' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -WorkflowAssociations @() -OutputFolder (Join-Path $TestDrive 'c') -BaseName 'Empty'

        (Get-Content -Path $output.WorkflowAssociationsCsvPath -Raw).Trim() | Should -BeExactly ('"' + ($script:Columns -split ',' -join '","') + '"')
        @(Read-JsonRow -Path $output.WorkflowAssociationsJsonPath) | Should -HaveCount 0
    }

    It 'lists the files in the manifest' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -WorkflowAssociations @((New-Row)) -OutputFolder (Join-Path $TestDrive 'd') -BaseName 'Manifest'

        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json

        $manifest.Files.WorkflowAssociationsCsv | Should -Be $output.WorkflowAssociationsCsvPath
        $manifest.Files.WorkflowAssociationsJson | Should -Be $output.WorkflowAssociationsJsonPath
        (Get-Content -Path $output.ManifestJsonPath -Raw) | Should -MatchExactly '"WorkflowAssociationsCsv"'
        (Get-Content -Path $output.ManifestJsonPath -Raw) | Should -MatchExactly '"WorkflowAssociationsJson"'
    }

    It 'writes no file, and lists none, when the parameter is not given' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -OutputFolder (Join-Path $TestDrive 'e') -BaseName 'None'

        $output.WorkflowAssociationsCsvPath | Should -BeNullOrEmpty
        $output.WorkflowAssociationsJsonPath | Should -BeNullOrEmpty
        @(Get-ChildItem -Path (Join-Path $TestDrive 'e') -Filter '*workflow-associations*') | Should -HaveCount 0
        $manifest = Get-Content -Path $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Files.WorkflowAssociationsCsv | Should -BeNullOrEmpty
        $manifest.Files.WorkflowAssociationsJson | Should -BeNullOrEmpty
    }

    It 'neutralizes a cell that a spreadsheet could read as a formula' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -WorkflowAssociations @((New-Row -Name '=HYPERLINK("http://example.invalid")')) -OutputFolder (Join-Path $TestDrive 'f') -BaseName 'Formula'

        @(Import-Csv -Path $output.WorkflowAssociationsCsvPath)[0].WorkflowName | Should -Be "'=HYPERLINK(""http://example.invalid"")"
    }

    It 'adds the Workflow associations section to the HTML report when there is a row, and not otherwise' {
        $with = Export-SPSInventoryReport -InputObject @($script:Site) -WorkflowAssociations @((New-Row)) -OutputFolder (Join-Path $TestDrive 'g') -BaseName 'With'
        $without = Export-SPSInventoryReport -InputObject @($script:Site) -WorkflowAssociations @() -OutputFolder (Join-Path $TestDrive 'h') -BaseName 'Without'
        $absent = Export-SPSInventoryReport -InputObject @($script:Site) -OutputFolder (Join-Path $TestDrive 'i') -BaseName 'Absent'

        (Get-Content -Path $with.HtmlPath -Raw) | Should -Match '<h2 id="workflow-associations">Workflow associations</h2>'
        (Get-Content -Path $without.HtmlPath -Raw) | Should -Not -Match 'id="workflow-associations"'
        (Get-Content -Path $absent.HtmlPath -Raw) | Should -Not -Match 'id="workflow-associations"'
    }

    It 'gives the examples to the workflow dataset of the report pack' {
        $output = Export-SPSInventoryReport -InputObject @($script:Site) -OutputFolder (Join-Path $TestDrive 'j') -BaseName 'Dataset'

        $record = @(Read-JsonRow -Path $output.WorkflowsJsonPath)[0]

        $record.Workflow2010Examples | Should -Be 'Approval (list Documents, https://intranet/sites/team): 3 running instance(s)'
        (Get-Content -Path $output.WorkflowsJsonPath -Raw) | Should -MatchExactly '"Workflow2010Examples"'
    }

    It 'does not touch the files of the other datasets, which are the same with or without the rows' {
        $without = Export-SPSInventoryReport -InputObject @($script:Site) -OutputFolder (Join-Path $TestDrive 'k') -BaseName 'Same'
        $with = Export-SPSInventoryReport -InputObject @($script:Site) -WorkflowAssociations @((New-Row)) -OutputFolder (Join-Path $TestDrive 'l') -BaseName 'Same'

        (Get-Content -Path $with.CsvPath -Raw) | Should -Be (Get-Content -Path $without.CsvPath -Raw)
        (Get-Content -Path $with.SitesJsonPath -Raw) | Should -Be (Get-Content -Path $without.SitesJsonPath -Raw)
    }
}
