# Tests for the profile property mapping report of Export-SPSInventoryReport: the files, the manifest, the alerts and the HTML section.
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
        param (
            [string]$Connection = 'contoso-local', [string]$Property = 'CostCenter', [string]$Attribute = 'costCenter', [string]$Direction = 'Import',
            $Synchronized = $false, $BuiltIn = $false, $Usage = 7, [string]$WebApplications = 'https://intranet; https://extranet'
        )
        [PSCustomObject]@{
            WebApplicationUrls = $WebApplications; UserProfileProxyName = 'User Profile Service Proxy'; UserProfileProxyId = '11111111-1111-1111-1111-111111111111'
            ConnectionName = $Connection; ConnectionType = 'ActiveDirectoryImport'; PropertyName = $Property; PropertyDisplayName = ($Property + ' display')
            PropertyMapping = $Attribute; Direction = $Direction; PropertyLength = 50; PropertyUsage = $Usage
            SynchronizedInSharePointOnline = $Synchronized; BuiltInProperty = $BuiltIn
        }
    }
}

Describe 'Export-SPSInventoryReport profile property mappings' {
    It 'writes the CSV and the JSON, the manifest entries, and one alert per connection that has custom mappings, with their number' {
        $rows = @(
            (New-Row -Connection 'contoso-local' -Property 'CostCenter' -Attribute 'costCenter')
            (New-Row -Connection 'contoso-local' -Property 'Badge' -Attribute 'badgeNumber')
            (New-Row -Connection 'contoso-local' -Property 'FirstName' -Attribute 'givenName' -Synchronized $true -BuiltIn $true)
            (New-Row -Connection 'contoso-local' -Property 'PhoneticFirstName' -Attribute 'msDS-PhoneticFirstName' -BuiltIn $true)
            (New-Row -Connection 'crm' -Property 'Region' -Attribute 'region' -Direction 'Export' -WebApplications 'https://extranet')
        )

        $output = Export-SPSInventoryReport -InputObject @() -ProfilePropertyMappings $rows -OutputFolder $TestDrive -BaseName 'Profile'

        $csv = @(Import-Csv $output.ProfileMappingsCsvPath)
        $csv | Should -HaveCount 5
        (Get-Content $output.ProfileMappingsCsvPath -TotalCount 1) | Should -Be '"WebApplicationUrls","UserProfileProxyName","UserProfileProxyId","ConnectionName","ConnectionType","PropertyName","PropertyDisplayName","PropertyMapping","Direction","PropertyLength","PropertyUsage","SynchronizedInSharePointOnline","BuiltInProperty"'
        $csv[0].PropertyName | Should -Be 'CostCenter'
        $csv[0].PropertyMapping | Should -Be 'costCenter'
        $csv[0].Direction | Should -Be 'Import'
        $csv[0].PropertyUsage | Should -Be '7'
        $csv[4].Direction | Should -Be 'Export'
        @(Read-JsonRow -Path $output.ProfileMappingsJsonPath) | Should -HaveCount 5
        $manifest = Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Files.ProfileMappingsCsv | Should -Be $output.ProfileMappingsCsvPath
        $manifest.Files.ProfileMappingsJson | Should -Be $output.ProfileMappingsJsonPath
        $manifest.Summary.ProfileInventoryComplete | Should -BeTrue
        $alerts = @(Read-JsonRow -Path $output.AlertsJsonPath | Where-Object { $_.AlertType -eq 'ProfilePropertyMapping' })
        $alerts | Should -HaveCount 2
        $contoso = @($alerts | Where-Object { $_.Value -like 'contoso-local*' })
        $crm = @($alerts | Where-Object { $_.Value -like 'crm*' })
        $contoso[0].Value | Should -Be 'contoso-local: 2 mapping(s)'
        $contoso[0].Url | Should -Be 'https://intranet'
        $contoso[0].Severity | Should -Be 'Low'
        $contoso[0].Message | Should -Match 'SharePoint Online does not have'
        $crm[0].Value | Should -Be 'crm: 1 mapping(s)'
        $crm[0].Url | Should -Be 'https://extranet'
        @(Read-JsonRow -Path $output.AlertsJsonPath | Where-Object { $_.AlertType -eq 'ProfilePropertyMappingInventoryPartial' }) | Should -HaveCount 0
    }

    It 'raises no alert for the mappings that SharePoint Online fills or that SharePoint ships, and an alert for those whose shipped status is unknown' {
        $synchronized = @((New-Row -Property 'FirstName' -Synchronized $true -BuiltIn $true), (New-Row -Property 'Custom' -Synchronized $true -BuiltIn $false))
        $shipped = @((New-Row -Property 'PhoneticFirstName' -BuiltIn $true))
        $unknown = @((New-Row -Property 'Unknown' -BuiltIn $null))

        $none = Export-SPSInventoryReport -InputObject @() -ProfilePropertyMappings @($synchronized + $shipped) -OutputFolder $TestDrive -BaseName 'NoCustom'
        $maybe = Export-SPSInventoryReport -InputObject @() -ProfilePropertyMappings $unknown -OutputFolder $TestDrive -BaseName 'Unknown'

        @(Read-JsonRow -Path $none.AlertsJsonPath | Where-Object { $_.AlertType -eq 'ProfilePropertyMapping' }) | Should -HaveCount 0
        @(Read-JsonRow -Path $maybe.AlertsJsonPath | Where-Object { $_.AlertType -eq 'ProfilePropertyMapping' }) | Should -HaveCount 1
    }

    It 'words the alert as a migration-only one in the on-premises mode' {
        $output = Export-SPSInventoryReport -InputObject @() -ProfilePropertyMappings @((New-Row)) -OutputFolder $TestDrive -BaseName 'OnPrem' -TargetMode 'SharePointOnPrem'

        $alert = @(Read-JsonRow -Path $output.AlertsJsonPath | Where-Object { $_.AlertType -eq 'ProfilePropertyMapping' })[0]

        $alert.Severity | Should -Be 'Low'
        $alert.Message | Should -Match '^Migration to SharePoint Online only\. '
    }

    It 'shows the mappings that need a decision first in the HTML report, and says how many there are' {
        $rows = @(
            (New-Row -Property 'FirstName' -Attribute 'givenName' -Synchronized $true -BuiltIn $true)
            (New-Row -Property 'CostCenter' -Attribute 'costCenter')
            (New-Row -Property 'PhoneticFirstName' -Attribute 'msDS-PhoneticFirstName' -BuiltIn $true)
        )

        $html = Get-Content -Path (Export-SPSInventoryReport -InputObject @() -ProfilePropertyMappings $rows -OutputFolder $TestDrive -BaseName 'Html').HtmlPath -Raw

        $html | Should -Match 'id="profile-property-mappings"'
        $html | Should -Match '<a href="#profile-property-mappings">Profile property mappings</a>'
        $html | Should -Match '<strong>3</strong> profile property mapping\(s\), <strong>1</strong> of them for a property that SharePoint Online does not fill'
        $html.IndexOf('costCenter') | Should -BeLessThan $html.IndexOf('givenName')
        $html.IndexOf('givenName') | Should -BeGreaterThan 0
        $html.IndexOf('msDS-PhoneticFirstName') | Should -BeGreaterThan $html.IndexOf('costCenter')
        $html | Should -Match '<td>Yes</td>'
        $html | Should -Match '<td>No</td>'
        $html | Should -Not -Match 'Partial collection'
    }

    It 'writes the empty cell of an unknown shipped status, not No' {
        $html = Get-Content -Path (Export-SPSInventoryReport -InputObject @() -ProfilePropertyMappings @((New-Row -BuiltIn $null)) -OutputFolder $TestDrive -BaseName 'Unknown').HtmlPath -Raw

        $html | Should -Match '<td>No</td>\s*<td></td>\s*</tr>'
    }

    It 'writes a valid empty report instead of dropping the files' {
        $output = Export-SPSInventoryReport -InputObject @() -ProfilePropertyMappings @() -OutputFolder $TestDrive -BaseName 'Empty'

        (Get-Content $output.ProfileMappingsCsvPath -TotalCount 1) | Should -Match 'ConnectionName'
        @(Import-Csv $output.ProfileMappingsCsvPath) | Should -HaveCount 0
        @(Read-JsonRow -Path $output.ProfileMappingsJsonPath) | Should -HaveCount 0
        (Get-Content $output.HtmlPath -Raw) | Should -Match '<strong>0</strong> profile property mapping\(s\), <strong>0</strong> of them'
    }

    It 'flags a partial inventory in the alerts, the manifest and the HTML report' {
        $output = Export-SPSInventoryReport -InputObject @() -ProfilePropertyMappings @() -ProfileInventoryComplete $false -OutputFolder $TestDrive -BaseName 'Partial'

        $alerts = @(Read-JsonRow -Path $output.AlertsJsonPath | Where-Object { $_.AlertType -eq 'ProfilePropertyMappingInventoryPartial' })
        $alerts | Should -HaveCount 1
        $alerts[0].Severity | Should -Be 'Medium'
        (Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json).Summary.ProfileInventoryComplete | Should -BeFalse
        (Get-Content $output.HtmlPath -Raw) | Should -Match 'Partial collection:</strong> some web applications, connections or mappings could not be read'
    }

    It 'ignores the completeness flag when no rows were supplied' {
        $output = Export-SPSInventoryReport -InputObject @() -ProfileInventoryComplete $false -OutputFolder $TestDrive -BaseName 'NoFlag'

        @(Read-JsonRow -Path $output.AlertsJsonPath | Where-Object { $_.AlertType -eq 'ProfilePropertyMappingInventoryPartial' }) | Should -HaveCount 0
        (Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json).Summary.ProfileInventoryComplete | Should -BeNullOrEmpty
    }

    It 'does not create profile mapping files when callers omit the parameter' {
        $output = Export-SPSInventoryReport -InputObject @([PSCustomObject]@{ Url = 'https://intranet/sites/team'; Category = 1 }) -OutputFolder $TestDrive -BaseName 'NoFiles'

        $output.ProfileMappingsCsvPath | Should -BeNullOrEmpty
        $output.ProfileMappingsJsonPath | Should -BeNullOrEmpty
        @(Get-ChildItem $TestDrive 'NoFiles-profilemappings-*') | Should -HaveCount 0
        (Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json).Files.ProfileMappingsJson | Should -BeNullOrEmpty
        (Get-Content $output.HtmlPath -Raw) | Should -Not -Match 'id="profile-property-mappings"'
    }

    It 'neutralizes spreadsheet formulas in the CSV, and keeps the JSON as it is' {
        $evil = '=HYPERLINK("https://example.invalid","click")'

        $output = Export-SPSInventoryReport -InputObject @() -ProfilePropertyMappings @((New-Row -Attribute $evil)) -OutputFolder $TestDrive -BaseName 'Csv'

        @(Import-Csv -Path $output.ProfileMappingsCsvPath)[0].PropertyMapping | Should -BeExactly ("'" + $evil)
        @(Read-JsonRow -Path $output.ProfileMappingsJsonPath)[0].PropertyMapping | Should -BeExactly $evil
    }

    It 'limits the rows of the HTML table, keeping the mappings that need a decision, and says where all of them are' {
        $rows = @(1..4 | ForEach-Object { New-Row -Property "Synced$_" -Synchronized $true -BuiltIn $true -Attribute "synced$_" }) + @((New-Row -Property 'Custom' -Attribute 'customAttribute'))

        $html = ConvertTo-SPSInventoryHtml -InputObject @() -ProfilePropertyMappings $rows -MaxDetailRow 2

        $html | Should -Match 'Showing the first 2 of 5 rows. The profile property mappings CSV and JSON files hold all the rows.'
        $html | Should -Match 'customAttribute'
        $html | Should -Match 'synced1'
        $html | Should -Not -Match 'synced3'
    }
}
