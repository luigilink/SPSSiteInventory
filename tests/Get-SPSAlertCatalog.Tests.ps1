# Behavior tests for Get-SPSAlertCatalog (pure data, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # Get-SPSAlertCatalog is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Catalog = & $script:Module { Get-SPSAlertCatalog }
    $script:OnPrem = & $script:Module { Get-SPSAlertCatalog -TargetMode 'SharePointOnPrem' }
    $script:WikiAlerts = Get-Content -Path (Join-Path $repoRoot 'wiki/Alerts.md') -Raw
    $script:WikiOnPrem = @($script:WikiAlerts -split '(?m)^## ' | Where-Object { $_ -like 'Alerts in the SharePointOnPrem mode*' })[0]
    # The alerts that are only about a migration to SharePoint Online are the ones that the derived catalog prefixes.
    $script:MigrationOnly = @($script:OnPrem.Keys | Where-Object { $script:OnPrem[$_].Message.StartsWith('Migration to SharePoint Online only. ') })
    $script:Worded = @($script:OnPrem.Keys | Where-Object { $_ -notin $script:MigrationOnly -and $script:OnPrem[$_].Remediation -ne $script:Catalog[$_].Remediation })
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

    It 'treats the SharePoint 2013 workflows as retired in SharePoint Online, like the 2010 ones' {
        $entry = $script:Catalog['Workflow2013']

        $entry.Severity | Should -Be 'High'
        $entry.Severity | Should -Be $script:Catalog['Workflow2010'].Severity
        $entry.Remediation | Should -Match 'engine was retired in SharePoint Online on 2 April 2026'
        $entry.Remediation | Should -Match 'Power Automate'
        $entry.Remediation | Should -Match 'Complete the workflows in flight before the migration'
        $entry.Reference | Should -Match 'migrate-from-classic-workflows-to-power-automate-flows'
        $script:Catalog['Workflow2013Running'].Severity | Should -Be 'High'
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

    It 'does not tell users to set up their SharePoint alerts again in SharePoint Online, where they are retired' {
        $entry = $script:Catalog['AlertSubscriptions']

        $entry.Severity | Should -Be 'Medium'
        $entry.Severity | Should -Be $script:Catalog['EmailEnabledLists'].Severity
        $entry.Message | Should -Match 'retired SharePoint Alerts from July 2026'
        $entry.Remediation | Should -Match 'retired SharePoint Alerts from July 2026'
        $entry.Remediation | Should -Match 'cannot be recreated there and existing ones stop working'
        $entry.Remediation | Should -Match 'SharePoint rule or a Power Automate flow'
        $entry.Remediation | Should -Match 'template for each classic alert scenario'
        $entry.Remediation | Should -Match 'only applies to a target that still supports them'
        $entry.Remediation | Should -Not -Match 'set up their alerts again'
        $entry.Message | Should -Not -Match 'migration tools do not migrate them\.$'
        $entry.Reference | Should -Match 'troubleshoot/sharepoint/sites/no-alert-notifications$'
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

    It 'gives restructuring guidance for subsites without treating them as a problem SharePoint Online cannot handle' {
        $entry = $script:Catalog['Subsites']

        $entry.Severity | Should -Be 'Low'
        $entry.Message | Should -Match 'SharePoint Online supports them'
        $entry.Message | Should -Match 'hub sites'
        $entry.Remediation | Should -Match 'becomes a site collection of its own'
        $entry.Remediation | Should -Match 'part of the URL of its content'
        $entry.Remediation | Should -Match 'SubsiteCount, MaxSubsiteDepth and SubsiteExamples'
        $entry.Remediation | Should -Not -Match 'cannot be migrated|must be removed|retired'
        $entry.Reference | Should -Be 'https://learn.microsoft.com/en-us/sharepoint/planning-hub-sites'
    }

    It 'tells the reader that a partial Simple site collection waits in the Needs review wave' {
        $script:Catalog['AssessmentPartial'].Remediation | Should -Match 'Simple site collection is held in the Needs review wave until it is read in full'
    }

    It 'is documented in the alerts wiki page, with the same remediation' {
        foreach ($key in $script:Catalog.Keys) {
            $script:WikiAlerts | Should -Match ('\| `{0}` \|' -f $key) -Because "alert $key must be documented"
            $script:WikiAlerts.Contains($script:Catalog[$key].Remediation) | Should -BeTrue -Because "the wiki must carry the remediation of $key"
        }
    }

    It 'has an alert for each signal of the modern experience, worded for the modern experience, in the default mode too' {
        foreach ($key in @('AlternateCssUrl', 'XsltListViews', 'ScriptWebParts', 'ModernExperienceOptOut', 'ClassicExperienceLists')) {
            $script:Catalog.Contains($key) | Should -BeTrue -Because $key
        }
        $script:Catalog['AlternateCssUrl'].Message | Should -Match 'modern pages do not apply it'
        $script:Catalog['AlternateCssUrl'].Remediation | Should -Match 'site theme'
        $script:Catalog['AlternateCssUrl'].Remediation | Should -Match 'AlternateCssUrlExamples'
        $script:Catalog['XsltListViews'].Message | Should -Match 'modern list ignores it'
        $script:Catalog['XsltListViews'].Remediation | Should -Match 'view formatting'
        $script:Catalog['XsltListViews'].Remediation | Should -Match 'XslLink or the Xsl'
        $script:Catalog['ScriptWebParts'].Message | Should -Match 'do not exist on a modern page'
        $script:Catalog['ScriptWebParts'].Remediation | Should -Match 'SharePoint Framework'
        $script:Catalog['ModernExperienceOptOut'].Remediation | Should -Match 'E3540C7D-6BEA-403C-A224-1A12EAFEE4C4'
        $script:Catalog['ModernExperienceOptOut'].Remediation | Should -Match '52E14B6F-B1BB-4969-B89B-C4FAA56745EF'
        $script:Catalog['ClassicExperienceLists'].Remediation | Should -Match '"List experience"'
    }

    It 'gives the alerts of the modern experience the severity that the weights of the signals say: a plan, or information' {
        foreach ($key in @('AlternateCssUrl', 'XsltListViews', 'ScriptWebParts')) {
            $script:Catalog[$key].Severity | Should -Be 'Medium' -Because $key
        }
        foreach ($key in @('ModernExperienceOptOut', 'ClassicExperienceLists')) {
            $script:Catalog[$key].Severity | Should -Be 'Low' -Because $key
        }
    }

    It 'tells the users about the workbooks that SharePoint Online does not open in the browser, as information' {
        $entry = $script:Catalog['LargeExcelFiles']

        $entry.Severity | Should -Be 'Low'
        $entry.Message | Should -Match 'does not open a workbook above its size limit in the browser'
        $entry.Remediation | Should -Match 'Tell the users'
        $entry.Remediation | Should -Match 'larger than 10 MB'
        $entry.Remediation | Should -Match 'LargeExcelFileExamples'
        $entry.Reference | Should -Match 'migration-assessment-scan-large-excel-files$'
    }

    It 'rejects a target mode that is not one of the two' {
        { & $script:Module { Get-SPSAlertCatalog -TargetMode 'Online' } } | Should -Throw "*TargetMode must be 'SharePointOnline' or 'SharePointOnPrem'*"
        { & $script:Module { Get-SPSAlertCatalog -TargetMode '' } } | Should -Throw "*TargetMode must be*"
        { & $script:Module { Get-SPSAlertCatalog -TargetMode $null } } | Should -Throw "*TargetMode must be*"
    }

    It 'is the default catalog for SharePointOnline, with or without the mode, whatever the case' {
        $explicit = & $script:Module { Get-SPSAlertCatalog -TargetMode 'sharepointonline' }

        [object]::ReferenceEquals($explicit, $script:Catalog) | Should -BeTrue
    }
}

Describe 'Get-SPSAlertCatalog for the SharePointOnPrem mode' {
    It 'has the same alerts, in the same order, as the default catalog, and builds them once' {
        ($script:OnPrem.Keys -join ',') | Should -Be ($script:Catalog.Keys -join ',')
        $again = & $script:Module { Get-SPSAlertCatalog -TargetMode 'SharePointOnPrem' }
        [object]::ReferenceEquals($again, $script:OnPrem) | Should -BeTrue
        $caseInsensitive = & $script:Module { Get-SPSAlertCatalog -TargetMode 'sharepointonprem' }
        [object]::ReferenceEquals($caseInsensitive, $script:OnPrem) | Should -BeTrue
    }

    It 'does not change the default catalog' {
        $script:Catalog['ExternalLists'].Severity | Should -Be 'High'
        $script:Catalog['ExternalLists'].Message | Should -Not -Match '^Migration to SharePoint Online only'
        $script:Catalog['FullTrustCode'].Severity | Should -Be 'High'
        $script:Catalog['Workflow2013'].Severity | Should -Be 'High'
    }

    It 'gives every alert a known severity, a message and a remediation, and its own remediation text' {
        foreach ($key in $script:OnPrem.Keys) {
            $entry = $script:OnPrem[$key]

            $entry.Severity | Should -BeIn @('High', 'Medium', 'Low') -Because "alert $key"
            [string]::IsNullOrWhiteSpace($entry.Message) | Should -BeFalse -Because "alert $key needs a message"
            $entry.Remediation | Should -Match '[.]$' -Because "alert $key remediation should be a sentence"
            if ($entry.Reference) {
                $entry.Reference | Should -Match '^https://learn\.microsoft\.com/en-us/' -Because "alert $key"
            }
        }
        $remediations = @($script:OnPrem.Keys | ForEach-Object { $script:OnPrem[$_].Remediation })
        @($remediations | Select-Object -Unique).Count | Should -Be $remediations.Count
    }

    It 'makes the alerts that are only about a migration to SharePoint Online Low, and says so before the original text' {
        $script:MigrationOnly.Count | Should -Be 18
        foreach ($key in $script:MigrationOnly) {
            $entry = $script:OnPrem[$key]

            $entry.Severity | Should -Be 'Low' -Because $key
            $entry.Message | Should -Be ('Migration to SharePoint Online only. ' + $script:Catalog[$key].Message) -Because $key
            $entry.Remediation | Should -Be ('Nothing to do to modernize this farm. If you migrate to SharePoint Online, this applies. ' + $script:Catalog[$key].Remediation) -Because $key
            $entry.Reference | Should -Be $script:Catalog[$key].Reference -Because $key
        }
        foreach ($key in @('ExternalLists', 'FbaConfigured', 'IrmEnabledLists', 'BcsApplication', 'UnsupportedSiteTemplate', 'AlertSubscriptions', 'LargeExcelFiles')) {
            $script:MigrationOnly | Should -Contain $key
        }
    }

    It 'keeps the words that it puts before a message apart, for the migration-only alerts only, so that a specific message can take them too' {
        foreach ($key in $script:OnPrem.Keys) {
            if ($script:MigrationOnly -contains $key) {
                $script:OnPrem[$key].MessagePrefix | Should -Be 'Migration to SharePoint Online only. ' -Because $key
                $script:OnPrem[$key].Message.StartsWith($script:OnPrem[$key].MessagePrefix) | Should -BeTrue -Because $key
            }
            else {
                $script:OnPrem[$key].ContainsKey('MessagePrefix') | Should -BeFalse -Because $key
            }
        }
        foreach ($key in $script:Catalog.Keys) {
            $script:Catalog[$key].ContainsKey('MessagePrefix') | Should -BeFalse -Because $key
        }
    }

    It 'does not tell a farm to use hub sites, which SharePoint Server does not have, and says that they are not available' {
        foreach ($key in $script:OnPrem.Keys) {
            ($script:OnPrem[$key].Message + ' ' + $script:OnPrem[$key].Remediation) | Should -Not -Match 'connected by (a )?hub site' -Because $key
        }
        $entry = $script:OnPrem['Subsites']

        $entry.Message | Should -Not -Match 'hub'
        $entry.Remediation | Should -Match 'hub sites are not available in SharePoint Server'
        $entry.Remediation | Should -Match 'linked from the navigation'
        $entry.Reference | Should -Be 'https://learn.microsoft.com/en-us/sharepoint/sites/sites-and-site-collections-overview'
        $script:Catalog['Subsites'].Remediation | Should -Match 'connected to the others by a hub site'
    }

    It 'keeps the alerts that matter for the modernization out of the migration-only ones' {
        foreach ($key in @('InfoPath', 'Workflow2010', 'FullTrustCode', 'PublishingSite', 'CustomizedPages', 'AlternateCssUrl', 'XsltListViews', 'ScriptWebParts', 'LargeLists', 'LargeListViews', 'Subsites', 'AssessmentFailed', 'AssessmentPartial', 'WebApplicationEnumerationFailed', 'BcsInventoryPartial')) {
            $script:MigrationOnly | Should -Not -Contain $key
        }
    }

    It 'words the alerts that matter for the modernization for the farm, not for SharePoint Online' {
        $script:Worded.Count | Should -Be 17
        foreach ($key in $script:Worded) {
            $script:OnPrem[$key].Message | Should -Not -Match 'SharePoint Online|migrat' -Because "the message of $key"
            $script:OnPrem[$key].Remediation | Should -Not -Match 'SharePoint Online|migrat' -Because "the remediation of $key"
        }
    }

    It 'gives the severities that the example configuration of the mode implies' {
        $expected = [ordered]@{
            Workflow2010 = 'High'; Workflow2010Running = 'High'; InfoPath = 'High'
            Workflow2013 = 'Medium'; Workflow2013Running = 'Medium'; FullTrustCode = 'Medium'; NoAccessSite = 'Medium'
            ModernExperienceOptOut = 'Medium'; AlternateCssUrl = 'Medium'; XsltListViews = 'Medium'; ScriptWebParts = 'Medium'
            PublishingSite = 'Medium'; PublishingPages = 'Medium'; CustomizedPages = 'Medium'; AppInstances = 'Medium'; AppWebs = 'Medium'
            LargeLists = 'Medium'; LargeListViews = 'Medium'; AssessmentPartial = 'Medium'
            LockedSite = 'Low'; ClassicExperienceLists = 'Low'; Subsites = 'Low'
            AssessmentFailed = 'High'; WebApplicationEnumerationFailed = 'High'; BcsInventoryPartial = 'Medium'
        }
        foreach ($key in $expected.Keys) {
            $script:OnPrem[$key].Severity | Should -Be $expected[$key] -Because $key
        }
    }

    It 'dates the end of support of what SharePoint Server Subscription Edition deprecates, and cites the page that says it' {
        foreach ($key in @('Workflow2010', 'InfoPath')) {
            $script:OnPrem[$key].Message | Should -Match 'deprecated in SharePoint Server Subscription Edition'
            $script:OnPrem[$key].Message | Should -Match '14 July 2026'
            $script:OnPrem[$key].Reference | Should -Match 'what-s-deprecated-or-removed-from-sharepoint-server-subscription-edition$'
        }
        $script:OnPrem['Workflow2010Running'].Remediation | Should -Match 'no longer supported since 14 July 2026'
    }

    It 'does not call the SharePoint 2013 workflows retired: Microsoft Workflow Manager is deprecated, SharePoint Workflow Manager replaces it' {
        foreach ($key in @('Workflow2013', 'Workflow2013Running')) {
            $script:OnPrem[$key].Message + $script:OnPrem[$key].Remediation | Should -Not -Match 'retired' -Because $key
        }
        $script:OnPrem['Workflow2013'].Message | Should -Match 'Microsoft Workflow Manager is deprecated'
        $script:OnPrem['Workflow2013'].Remediation | Should -Match 'SharePoint Workflow Manager'
        $script:OnPrem['Workflow2013'].Remediation | Should -Match 'Power Automate'
    }

    It 'sends the full-trust code and the add-ins to the SharePoint Framework, and lets them run until then' {
        $script:OnPrem['FullTrustCode'].Remediation | Should -Match 'SharePoint Framework solutions'
        $script:OnPrem['FullTrustCode'].Remediation | Should -Match 'keeps working on the farm until then'
        $script:OnPrem['FullTrustCode'].Message | Should -Match 'runs on this farm'
        $script:OnPrem['AppInstances'].Message | Should -Match 'keep running on this farm'
        $script:OnPrem['AppInstances'].Remediation | Should -Match 'Subscription Edition supports'
    }

    It 'tells a partial Modern-ready site collection from a Simple one' {
        $script:OnPrem['AssessmentPartial'].Remediation | Should -Match 'Modern-ready site collection is held in the Needs review wave'
        $script:OnPrem['AssessmentPartial'].Remediation | Should -Not -Match 'Simple'
    }

    It 'rejects a catalog that lacks an alert that it words, instead of losing its words' {
        $short = [ordered]@{}
        foreach ($key in $script:Catalog.Keys | Where-Object { $_ -ne 'Workflow2010' }) { $short[$key] = $script:Catalog[$key] }

        { & $script:Module { param ($Catalog) Get-SPSOnPremAlertCatalog -Catalog $Catalog } $short } | Should -Throw "*'Workflow2010' is worded for the on-premises mode but is not in the alert catalog*"
    }

    It 'is documented in the alerts wiki page: the migration-only alerts by name, the others with their words' {
        $script:WikiOnPrem | Should -Not -BeNullOrEmpty
        foreach ($key in $script:MigrationOnly) {
            $script:WikiOnPrem | Should -Match ('`{0}`' -f $key) -Because "the wiki lists $key as migration-only"
        }
        foreach ($key in $script:Worded) {
            $script:WikiOnPrem | Should -Match ('\| `{0}` \| {1} \|' -f $key, $script:OnPrem[$key].Severity) -Because "alert $key"
            $script:WikiOnPrem.Contains($script:OnPrem[$key].Message) | Should -BeTrue -Because "the wiki must carry the on-premises message of $key"
            $script:WikiOnPrem.Contains($script:OnPrem[$key].Remediation) | Should -BeTrue -Because "the wiki must carry the on-premises remediation of $key"
        }
        $script:WikiOnPrem | Should -Match '`ModernExperienceOptOut`\*\* is `Medium` instead of `Low`'
    }
}
