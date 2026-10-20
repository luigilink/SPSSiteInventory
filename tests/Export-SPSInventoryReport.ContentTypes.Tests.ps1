BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
}

Describe 'Export-SPSInventoryReport content types' {
    It 'writes aligned site CSV, JSON, HTML and content-type CSV/JSON' {
        $sites = @([PSCustomObject]@{
            Url = 'https://intranet/sites/team'; WebApp = 'Intranet'
            HasFbaZone = $true; ContentTypeCount = 1
            ListContentTypeBindingCount = 1; ContentTypeInventoryComplete = $true
            Category = 4; CategoryName = 'Blocking'; Wave = 4; Score = 0
            Reasons = 'blocking: HasFbaZone'
        })
        $types = @([PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/team'; WebUrl = 'https://intranet/sites/team'
            Scope = 'List'; ListTitle = 'Legal, & Compliance'; ListUrl = '/sites/team/legal'
            ContentTypeId = '0x010100AA'; Name = 'Agreement'; Group = 'Contoso'
            ParentContentTypeId = '0x0101'; FieldCount = 2; FieldTypes = 'Text; DateTime'
            DocumentTemplateUrl = ''; Hidden = $false; ReadOnly = $false; Sealed = $false
        })

        $output = Export-SPSInventoryReport -InputObject $sites -ContentTypes $types -OutputFolder $TestDrive -BaseName 'Test'

        @(Import-Csv $output.CsvPath) | Should -HaveCount 1
        @(Get-Content $output.JsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 1
        (Import-Csv $output.CsvPath)[0].HasFbaZone | Should -Be 'True'
        @(Import-Csv $output.ContentTypesCsvPath) | Should -HaveCount 1
        (Import-Csv $output.ContentTypesCsvPath)[0].ListTitle | Should -Be 'Legal, & Compliance'
        @(Get-Content $output.ContentTypesJsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 1
        (Get-Content $output.HtmlPath -Raw) | Should -Match 'Legal, &amp; Compliance'
    }

    It 'writes a valid empty content-type report instead of dropping the files' {
        $output = Export-SPSInventoryReport -InputObject @() -ContentTypes @() -OutputFolder $TestDrive -BaseName 'Empty'

        (Get-Content $output.ContentTypesCsvPath -TotalCount 1) | Should -Match 'ContentTypeId'
        @(Import-Csv $output.ContentTypesCsvPath) | Should -HaveCount 0
        (Get-Content $output.ContentTypesJsonPath -Raw | ConvertFrom-Json) | Should -HaveCount 0
        (Get-Content $output.HtmlPath -Raw) | Should -Match 'Content types and list bindings'
    }

    It 'does not create content-type files when callers omit the optional parameter' {
        $sites = @([PSCustomObject]@{ Url = 'https://intranet/sites/team'; Category = 1 })

        $output = Export-SPSInventoryReport -InputObject $sites -OutputFolder $TestDrive -BaseName 'Legacy'

        $output.ContentTypesCsvPath | Should -BeNullOrEmpty
        @(Get-ChildItem $TestDrive 'Legacy-contenttypes-*') | Should -HaveCount 0
        (Get-Content $output.HtmlPath -Raw) | Should -Not -Match 'Content types and list bindings'
    }
}
