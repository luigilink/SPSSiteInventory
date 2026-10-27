# Behavior tests for Get-SPSAlertCatalog (pure data, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Get-SPSAlertCatalog is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Catalog = & $script:Module { Get-SPSAlertCatalog }
    $script:WikiAlerts = Get-Content -Path (Join-Path $repoRoot 'wiki/Alerts.md') -Raw
}

Describe 'Get-SPSAlertCatalog' {
    It 'returns the same entries in the same order on every call' {
        $second = & $script:Module { Get-SPSAlertCatalog }

        ($second.Keys -join ',') | Should -Be ($script:Catalog.Keys -join ',')
        $script:Catalog.Count | Should -BeGreaterThan 30
    }

    It 'gives every alert a known severity, a message and a remediation' {
        foreach ($key in $script:Catalog.Keys) {
            $entry = $script:Catalog[$key]

            $entry.Severity | Should -BeIn @('High', 'Medium') -Because "alert $key"
            [string]::IsNullOrWhiteSpace($entry.Message) | Should -BeFalse -Because "alert $key needs a message"
            [string]::IsNullOrWhiteSpace($entry.Remediation) | Should -BeFalse -Because "alert $key needs a remediation"
            $entry.Remediation | Should -Match '[.]$' -Because "alert $key remediation should be a sentence"
        }
    }

    It 'gives every alert its own remediation text' {
        $remediations = @($script:Catalog.Keys | ForEach-Object { $script:Catalog[$_].Remediation })

        @($remediations | Select-Object -Unique).Count | Should -Be $remediations.Count
    }

    It 'only references Microsoft Learn pages over https, or nothing' {
        foreach ($key in $script:Catalog.Keys) {
            $reference = $script:Catalog[$key].Reference
            if ($reference) {
                $reference | Should -Match '^https://learn\.microsoft\.com/en-us/' -Because "alert $key"
            }
        }
    }

    It 'does not recommend BCS capabilities that SharePoint Online retired' {
        foreach ($key in $script:Catalog.Keys) {
            $script:Catalog[$key].Remediation | Should -Not -Match 'hybrid BCS|redeploy' -Because "alert $key"
        }
        $script:Catalog['ExternalLists'].Remediation | Should -Match 'Power Apps'
        $script:Catalog['BcsApplication'].Remediation | Should -Match 'Power Apps'
    }

    It 'is documented in the alerts wiki page, with the same remediation' {
        foreach ($key in $script:Catalog.Keys) {
            $script:WikiAlerts | Should -Match ('\| `{0}` \|' -f $key) -Because "alert $key must be documented"
            $script:WikiAlerts.Contains($script:Catalog[$key].Remediation) | Should -BeTrue -Because "the wiki must carry the remediation of $key"
        }
    }
}
