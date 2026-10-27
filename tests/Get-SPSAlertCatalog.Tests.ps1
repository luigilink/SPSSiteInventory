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

            $entry.Severity | Should -BeIn @('High', 'Medium', 'Low') -Because "alert $key"
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

    It 'does not tell users to restart workflows in SharePoint Online, where both workflow engines are retired' {
        foreach ($key in @('Workflow2010Running', 'Workflow2013Running')) {
            $entry = $script:Catalog[$key]

            $entry.Remediation | Should -Match 'finish the running workflows on the source' -Because "alert $key"
            $entry.Remediation | Should -Match 'engine (is |was )retired in SharePoint Online' -Because "alert $key"
            $entry.Remediation | Should -Match 'cannot be restarted there' -Because "alert $key"
            $entry.Remediation | Should -Match 'Power Automate' -Because "alert $key"
            $entry.Remediation | Should -Not -Match 'users must restart' -Because "alert $key"
            $entry.Reference | Should -Match 'migrate-from-classic-workflows-to-power-automate-flows' -Because "alert $key"
        }
        $script:Catalog['Workflow2013Running'].Remediation | Should -Match '2 April 2026'
    }

    It 'does not tell users to reinstall add-ins in SharePoint Online, where the add-in model is retired' {
        foreach ($key in @('AppInstances', 'AppWebs')) {
            $entry = $script:Catalog[$key]

            $entry.Remediation | Should -Match 'cannot be reinstalled' -Because "alert $key"
            $entry.Remediation | Should -Not -Match 'reinstalled cleanly|Reinstall or replace' -Because "alert $key"
            $entry.Reference | Should -Match 'sp-add-ins/retirement-announcement-for-add-ins' -Because "alert $key"
        }
        $script:Catalog['AppInstances'].Remediation | Should -Match 'SharePoint Framework'
        $script:Catalog['AppInstances'].Remediation | Should -Match 'only applies to a target that still supports them'
        $script:Catalog['AppWebs'].Remediation | Should -Match 'preserve'
    }

    It 'replaces InfoPath browser forms instead of offering to repair them for SharePoint Online' {
        $remediation = $script:Catalog['InfoPath'].Remediation

        $remediation | Should -Match 'supported replacement for every InfoPath form'
        $remediation | Should -Match 'Power Apps'
        $remediation | Should -Match 'InfoPath Forms Services is retired in SharePoint Online'
        $remediation | Should -Match 'does not make a form work there'
    }

    It 'tells a read-only or no-additions lock from a no-access lock' {
        $noAccess = $script:Catalog['NoAccessSite']
        $locked = $script:Catalog['LockedSite']

        $noAccess.Severity | Should -Be 'High'
        $noAccess.Message | Should -Match 'NoAccess'
        $noAccess.Remediation | Should -Match 'NoAccess lock makes the site unreadable'
        $noAccess.Remediation | Should -Match 'unlock the sites that must migrate'
        $noAccess.Reference | Should -Match 'migration-assessment-scan-locked-sites'
        $locked.Severity | Should -Be 'Medium'
        $locked.Message | Should -Match 'NoAdditions or ReadOnly'
        $locked.Message | Should -Match 'still be read and migrated'
        $locked.Remediation | Should -Match 'NoAdditions lock prevents adding content'
        $locked.Remediation | Should -Match 'ReadOnly lock prevents adding, updating and deleting it'
        $locked.Remediation | Should -Match 'both still allow reading'
        $locked.Remediation | Should -Match 'only if your migration method requires it'
        $locked.Remediation | Should -Not -Match 'unreadable'
        $locked.Remediation | Should -Not -Match 'a locked site cannot be read'
        $locked.Reference | Should -Match 'powershell/module/microsoft\.sharepoint\.powershell/set-spsite\?view=sharepoint-ps$'
    }

    It 'is documented in the alerts wiki page, with the same remediation' {
        foreach ($key in $script:Catalog.Keys) {
            $script:WikiAlerts | Should -Match ('\| `{0}` \|' -f $key) -Because "alert $key must be documented"
            $script:WikiAlerts.Contains($script:Catalog[$key].Remediation) | Should -BeTrue -Because "the wiki must carry the remediation of $key"
        }
    }
}
