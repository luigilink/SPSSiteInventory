# Tests for the Secure Store report of Export-SPSInventoryReport: the files, the manifest, the alerts and the HTML section.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # Windows PowerShell 5.1 does not unroll a JSON array in a pipeline, so count with foreach.
    function Get-AlertCount {
        param ($Alerts, [string]$Type)
        $count = 0
        foreach ($alert in $Alerts) {
            if ($alert.AlertType -eq $Type) { $count++ }
        }
        return $count
    }

    function Get-RowCount {
        param ($Rows)
        $count = 0
        foreach ($row in $Rows) { $count++ }
        return $count
    }

    function Get-TestApplication {
        param ([string]$Name = 'SapTarget', [string]$FriendlyName = 'SAP, & Billing', [string]$ApplicationType = 'Group', [string]$WebApplicationUrls = 'https://intranet; https://extranet')
        [PSCustomObject]@{
            WebApplicationUrls      = $WebApplicationUrls
            SecureStoreProxyName    = 'Secure Store Service Proxy'
            SecureStoreProxyId      = '11111111-1111-1111-1111-111111111111'
            Name                    = $Name
            FriendlyName            = $FriendlyName
            ContactEmail            = 'owner@contoso.com'
            ApplicationType         = $ApplicationType
            CredentialManagementUrl = 'https://contoso.com/credentials'
            TicketTimeoutMinutes    = 2
        }
    }
}

Describe 'Export-SPSInventoryReport Secure Store' {
    It 'writes the Secure Store CSV and JSON, the manifest entries and one alert per target application' {
        $applications = @((Get-TestApplication), (Get-TestApplication -Name 'CrmTarget' -FriendlyName 'CRM' -ApplicationType 'Individual' -WebApplicationUrls 'https://intranet'))

        $output = Export-SPSInventoryReport -InputObject @() -SecureStoreApplications $applications -OutputFolder $TestDrive -BaseName 'SecureStore'

        $csvRows = @(Import-Csv $output.SecureStoreCsvPath)
        $csvRows | Should -HaveCount 2
        $csvRows[0].Name | Should -Be 'SapTarget'
        $csvRows[0].FriendlyName | Should -Be 'SAP, & Billing'
        $csvRows[0].WebApplicationUrls | Should -Be 'https://intranet; https://extranet'
        $csvRows[0].SecureStoreProxyName | Should -Be 'Secure Store Service Proxy'
        $csvRows[0].SecureStoreProxyId | Should -Be '11111111-1111-1111-1111-111111111111'
        $csvRows[0].ContactEmail | Should -Be 'owner@contoso.com'
        $csvRows[0].ApplicationType | Should -Be 'Group'
        $csvRows[0].CredentialManagementUrl | Should -Be 'https://contoso.com/credentials'
        $csvRows[0].TicketTimeoutMinutes | Should -Be '2'
        $csvRows[1].ApplicationType | Should -Be 'Individual'
        (Get-Content $output.SecureStoreCsvPath -TotalCount 1) | Should -Be '"WebApplicationUrls","SecureStoreProxyName","SecureStoreProxyId","Name","FriendlyName","ContactEmail","ApplicationType","CredentialManagementUrl","TicketTimeoutMinutes"'
        Get-RowCount -Rows (Get-Content $output.SecureStoreJsonPath -Raw | ConvertFrom-Json) | Should -Be 2
        $manifest = Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Files.SecureStoreCsv | Should -Be $output.SecureStoreCsvPath
        $manifest.Files.SecureStoreJson | Should -Be $output.SecureStoreJsonPath
        $manifest.Summary.SecureStoreInventoryComplete | Should -BeTrue
        $alerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json
        Get-AlertCount -Alerts $alerts -Type 'SecureStoreApplication' | Should -Be 2
        $first = @($alerts | Where-Object { $_.AlertType -eq 'SecureStoreApplication' })[0]
        $first.Url | Should -Be 'https://intranet'
        $first.Value | Should -Be 'SapTarget'
        $first.Severity | Should -Be 'Low'
        $first.Message | Should -Match 'not migrated to SharePoint Online'
        $first.Remediation | Should -Match 'Group Restricted'
        Get-AlertCount -Alerts $alerts -Type 'SecureStoreInventoryPartial' | Should -Be 0
        $html = Get-Content $output.HtmlPath -Raw
        $html | Should -Match 'id="secure-store-applications"'
        $html | Should -Match '<a href="#secure-store-applications">Secure Store</a>'
        $html | Should -Match 'SAP, &amp; Billing'
        $html | Should -Match '<strong>2</strong> Secure Store target application\(s\)'
        $html | Should -Not -Match 'Partial collection'
    }

    It 'keeps the contact e-mail address out of the HTML report, and in the CSV and JSON files' {
        $output = Export-SPSInventoryReport -InputObject @() -SecureStoreApplications @((Get-TestApplication)) -OutputFolder $TestDrive -BaseName 'SecureStorePrivacy'

        (Get-Content $output.HtmlPath -Raw) | Should -Not -Match 'owner@contoso\.com'
        (Get-Content $output.SecureStoreCsvPath -Raw) | Should -Match 'owner@contoso\.com'
        (Get-Content $output.SecureStoreJsonPath -Raw) | Should -Match 'owner@contoso\.com'
    }

    It 'writes a valid empty Secure Store report instead of dropping the files' {
        $output = Export-SPSInventoryReport -InputObject @() -SecureStoreApplications @() -OutputFolder $TestDrive -BaseName 'EmptySecureStore'

        (Get-Content $output.SecureStoreCsvPath -TotalCount 1) | Should -Match 'FriendlyName'
        @(Import-Csv $output.SecureStoreCsvPath) | Should -HaveCount 0
        Get-RowCount -Rows (Get-Content $output.SecureStoreJsonPath -Raw | ConvertFrom-Json) | Should -Be 0
        $alerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json
        Get-AlertCount -Alerts $alerts -Type 'SecureStoreApplication' | Should -Be 0
        (Get-Content $output.HtmlPath -Raw) | Should -Match '<strong>0</strong> Secure Store target application'
    }

    It 'flags a partial Secure Store inventory in the alerts, the manifest and the HTML report' {
        $output = Export-SPSInventoryReport -InputObject @() -SecureStoreApplications @() -SecureStoreInventoryComplete $false -OutputFolder $TestDrive -BaseName 'PartialSecureStore'

        $alerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json
        Get-AlertCount -Alerts $alerts -Type 'SecureStoreInventoryPartial' | Should -Be 1
        @($alerts | Where-Object { $_.AlertType -eq 'SecureStoreInventoryPartial' })[0].Severity | Should -Be 'Medium'
        (Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json).Summary.SecureStoreInventoryComplete | Should -BeFalse
        (Get-Content $output.HtmlPath -Raw) | Should -Match 'Partial collection:</strong> some web applications or target applications could not be read'
    }

    It 'ignores the completeness flag when no Secure Store rows were collected' {
        $output = Export-SPSInventoryReport -InputObject @() -SecureStoreInventoryComplete $false -OutputFolder $TestDrive -BaseName 'NoSecureStoreFlag'

        $alerts = Get-Content $output.AlertsJsonPath -Raw | ConvertFrom-Json
        Get-AlertCount -Alerts $alerts -Type 'SecureStoreInventoryPartial' | Should -Be 0
        (Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json).Summary.SecureStoreInventoryComplete | Should -BeNullOrEmpty
    }

    It 'does not create Secure Store files when callers omit the parameter' {
        $sites = @([PSCustomObject]@{ Url = 'https://intranet/sites/team'; Category = 1 })

        $output = Export-SPSInventoryReport -InputObject $sites -OutputFolder $TestDrive -BaseName 'NoSecureStoreFiles'

        $output.SecureStoreCsvPath | Should -BeNullOrEmpty
        $output.SecureStoreJsonPath | Should -BeNullOrEmpty
        @(Get-ChildItem $TestDrive 'NoSecureStoreFiles-securestore-*') | Should -HaveCount 0
        $manifest = Get-Content $output.ManifestJsonPath -Raw | ConvertFrom-Json
        $manifest.Files.SecureStoreJson | Should -BeNullOrEmpty
        (Get-Content $output.HtmlPath -Raw) | Should -Not -Match 'id="secure-store-applications"'
    }

    It 'neutralizes spreadsheet formulas in the CSV, and keeps the JSON as it is' {
        $evil = '=HYPERLINK("https://example.invalid","click")'
        $application = Get-TestApplication -FriendlyName $evil

        $output = Export-SPSInventoryReport -InputObject @() -SecureStoreApplications @($application) -OutputFolder $TestDrive -BaseName 'CsvSecureStore'

        @(Import-Csv -Path $output.SecureStoreCsvPath)[0].FriendlyName | Should -BeExactly ("'" + $evil)
        @(Get-Content $output.SecureStoreJsonPath -Raw | ConvertFrom-Json)[0].FriendlyName | Should -BeExactly $evil
    }

    It 'limits the rows of the HTML table and says where all of them are' {
        $applications = @(1..5 | ForEach-Object { Get-TestApplication -Name ('Target{0}' -f $_) })

        $html = ConvertTo-SPSInventoryHtml -InputObject @() -SecureStoreApplications $applications -MaxDetailRow 2

        $html | Should -Match 'Showing the first 2 of 5 rows. The Secure Store CSV and JSON files hold all the rows.'
        $html | Should -Match 'Target1'
        $html | Should -Match 'Target2'
        $html | Should -Not -Match 'Target3'
    }
}
