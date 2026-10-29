# Behavior tests for Get-SPSInventorySiteSignal (pure, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Get-Signal {
        param ([object]$Record)
        @(& $script:Module { param ($Item) Get-SPSInventorySiteSignal -Record $Item } $Record)
    }

    # A record where nothing is raised: counts at 0, flags off, no review, no lock, complete inventory.
    function New-QuietRecord {
        [PSCustomObject]@{
            Url = 'https://intranet/sites/quiet'; Template = 'STS#0'
            TemplateCompatibility = 'Compatible'; IsUnsupportedSiteTemplate = $false; TemplateCompatibilityReason = 'Template matches.'
            TemplateLanguageReviewRequired = $false; TemplateLanguageReason = ''; TemplateLanguageTag = 'en-US'; TemplateLanguageLcid = 1033
            SiteLockState = 'Unlock'; IsLockedSite = $false; HasNoAccessLock = $false
            UsesFullTrustCode = $false; UsesCustomFarmFeature = $false; SandboxSolutions = 0; EventReceivers = 0; CustomMasterPage = $false
            CustomizedPageCount = 0; CustomizedPageExamples = ''; AppInstanceCount = 0; AppWebCount = 0; AppInstanceExamples = ''
            HasFbaZone = $false; Workflow2010Count = 0; Workflow2010RunningInstanceCount = 0; Workflow2013Count = 0; Workflow2013RunningInstanceCount = 0
            InfoPathFormCount = 0; IrmEnabledListCount = 0
            PublishingInfrastructureEnabled = $false; PublishingWebCount = 0; PublishingPageCount = 0; PublishingPageLayoutCount = 0; PublishingPageLayoutExamples = ''
            SubWebCount = 1; SubsiteCount = 0; MaxSubsiteDepth = 0; SubsiteExamples = ''
            ManagedMetadataListCount = 0; ManagedMetadataColumnCount = 0; ManagedMetadataTermSetCount = 0; ManagedMetadataExamples = ''
            ExternalListCount = 0; ExternalListExamples = ''; EmailEnabledListCount = 0; EmailEnabledListExamples = ''
            HtmlFileCount = 0; HtmlFileExamples = ''; BrowserFileHandling = 'Strict'; SharePointAlertCount = 0
            CustomPermissionLevelCount = 0; CustomPermissionLevelExamples = ''; UniquePermissionsCount = 0
            IsLargeSite = $false; LargeListCount = 0; LargeListExamples = ''; LargeListViewCount = 0; LargeListViewExamples = ''
            CheckedOutFileCount = 0; CheckedOutFileExamples = ''; FileVersionCount = 0; FileVersionExamples = ''
            SiteInventoryComplete = $true; CustomizationInventoryComplete = $true; ContentTypeInventoryComplete = $true
        }
    }

    function New-RecordWith {
        param ([hashtable]$Change)
        $record = New-QuietRecord
        foreach ($name in $Change.Keys) {
            $record | Add-Member -NotePropertyName $name -NotePropertyValue $Change[$name] -Force
        }
        $record
    }
}

Describe 'Get-SPSInventorySiteSignal' {
    It 'returns nothing for a site collection that raises no signal' {
        @(Get-Signal -Record (New-QuietRecord)).Count | Should -Be 0
    }

    It 'returns nothing for a missing record or a record with no fields' {
        @(Get-Signal -Record $null).Count | Should -Be 0
        @(Get-Signal -Record ([PSCustomObject]@{ Url = 'https://intranet/sites/bare' })).Count | Should -Be 0
    }

    It 'returns a Label, a Value and a Detail for each signal' {
        $signal = @(Get-Signal -Record (New-RecordWith @{ LargeListCount = 2; LargeListExamples = 'Documents (7000); Records (5100)' }))

        $signal.Count | Should -Be 1
        $signal[0].Label | Should -Be 'Large lists'
        $signal[0].Value | Should -Be '2'
        $signal[0].Detail | Should -Be 'Documents (7000); Records (5100)'
    }

    It 'raises <Label> when <Field> is set' -ForEach @(
        @{ Field = 'UsesFullTrustCode'; Value = $true; Label = 'Full-trust code'; Expected = 'Yes' }
        @{ Field = 'UsesCustomFarmFeature'; Value = $true; Label = 'Custom farm feature'; Expected = 'Yes' }
        @{ Field = 'SandboxSolutions'; Value = 3; Label = 'Sandbox solutions'; Expected = '3' }
        @{ Field = 'EventReceivers'; Value = 2; Label = 'Custom event receivers'; Expected = '2' }
        @{ Field = 'CustomMasterPage'; Value = $true; Label = 'Custom master page'; Expected = 'Yes' }
        @{ Field = 'CustomizedPageCount'; Value = 4; Label = 'Customized pages'; Expected = '4' }
        @{ Field = 'AlternateCssUrlCount'; Value = 2; Label = 'Alternate CSS URL (webs)'; Expected = '2' }
        @{ Field = 'XsltListViewCount'; Value = 3; Label = 'XSLT list views'; Expected = '3' }
        @{ Field = 'ScriptWebPartCount'; Value = 4; Label = 'Script web parts'; Expected = '4' }
        @{ Field = 'ClassicExperienceOptOutCount'; Value = 1; Label = 'Opted out of modern lists'; Expected = '1' }
        @{ Field = 'ClassicExperienceListCount'; Value = 5; Label = 'Lists forced to classic'; Expected = '5' }
        @{ Field = 'AppInstanceCount'; Value = 1; Label = 'App instances'; Expected = '1' }
        @{ Field = 'AppWebCount'; Value = 2; Label = 'App webs'; Expected = '2' }
        @{ Field = 'InfoPathFormCount'; Value = 5; Label = 'InfoPath forms'; Expected = '5' }
        @{ Field = 'IrmEnabledListCount'; Value = 6; Label = 'IRM-enabled lists'; Expected = '6' }
        @{ Field = 'PublishingInfrastructureEnabled'; Value = $true; Label = 'Publishing infrastructure'; Expected = 'Yes' }
        @{ Field = 'PublishingWebCount'; Value = 2; Label = 'Publishing webs'; Expected = '2' }
        @{ Field = 'PublishingPageCount'; Value = 40; Label = 'Publishing pages'; Expected = '40' }
        @{ Field = 'PublishingPageLayoutCount'; Value = 3; Label = 'Page layouts in use'; Expected = '3' }
        @{ Field = 'ExternalListCount'; Value = 2; Label = 'External lists'; Expected = '2' }
        @{ Field = 'EmailEnabledListCount'; Value = 1; Label = 'E-mail enabled lists'; Expected = '1' }
        @{ Field = 'HtmlFileCount'; Value = 4; Label = 'HTML files'; Expected = '4' }
        @{ Field = 'SharePointAlertCount'; Value = 1234; Label = 'SharePoint alerts'; Expected = '1234' }
        @{ Field = 'CustomPermissionLevelCount'; Value = 2; Label = 'Custom permission levels'; Expected = '2' }
        @{ Field = 'UniquePermissionsCount'; Value = 9; Label = 'Unique permission assignments'; Expected = '9' }
        @{ Field = 'IsLargeSite'; Value = $true; Label = 'Large site'; Expected = 'Yes' }
        @{ Field = 'LargeListCount'; Value = 2; Label = 'Large lists'; Expected = '2' }
        @{ Field = 'LargeListViewCount'; Value = 1; Label = 'Large-list views'; Expected = '1' }
        @{ Field = 'CheckedOutFileCount'; Value = 3; Label = 'Checked-out files'; Expected = '3' }
        @{ Field = 'FileVersionCount'; Value = 2; Label = 'High-version files'; Expected = '2' }
        @{ Field = 'LargeExcelFileCount'; Value = 3; Label = 'Large Excel files'; Expected = '3' }
        @{ Field = 'AudienceTargetedItemCount'; Value = 12; Label = 'Audience-targeted items'; Expected = '12' }
        @{ Field = 'SiteNotebookCount'; Value = 1; Label = 'Site notebooks'; Expected = '1' }
        @{ Field = 'CustomizedProfilePageCount'; Value = 1; Label = 'Customized profile page'; Expected = '1' }
        @{ Field = 'BrowserFileHandling'; Value = 'Permissive'; Label = 'Browser file handling'; Expected = 'Permissive' }
    ) {
        $signal = @(Get-Signal -Record (New-RecordWith @{ $Field = $Value }))

        $signal.Count | Should -Be 1
        $signal[0].Label | Should -Be $Label
        $signal[0].Value | Should -Be $Expected
    }

    It 'does not raise <Label> when <Field> is at its default' -ForEach @(
        @{ Field = 'UsesFullTrustCode'; Value = $false; Label = 'Full-trust code' }
        @{ Field = 'SandboxSolutions'; Value = 0; Label = 'Sandbox solutions' }
        @{ Field = 'CustomMasterPage'; Value = 'False'; Label = 'Custom master page' }
        @{ Field = 'EventReceivers'; Value = $null; Label = 'Custom event receivers' }
        @{ Field = 'BrowserFileHandling'; Value = 'Strict'; Label = 'Browser file handling' }
        @{ Field = 'LargeListCount'; Value = '0'; Label = 'Large lists' }
        @{ Field = 'SiteLockState'; Value = 'Unlock'; Label = 'Site lock' }
        @{ Field = 'TemplateCompatibility'; Value = 'Compatible'; Label = 'Template compatibility' }
    ) {
        $signal = @(Get-Signal -Record (New-RecordWith @{ $Field = $Value }))

        $signal.Label | Should -Not -Contain $Label
    }

    It 'gives the examples that go with a count as its Detail' -ForEach @(
        @{ Count = 'CustomizedPageCount'; Examples = 'CustomizedPageExamples'; Label = 'Customized pages' }
        @{ Count = 'AlternateCssUrlCount'; Examples = 'AlternateCssUrlExamples'; Label = 'Alternate CSS URL (webs)' }
        @{ Count = 'XsltListViewCount'; Examples = 'XsltListViewExamples'; Label = 'XSLT list views' }
        @{ Count = 'ScriptWebPartCount'; Examples = 'ScriptWebPartExamples'; Label = 'Script web parts' }
        @{ Count = 'ClassicExperienceOptOutCount'; Examples = 'ClassicExperienceOptOutExamples'; Label = 'Opted out of modern lists' }
        @{ Count = 'ClassicExperienceListCount'; Examples = 'ClassicExperienceListExamples'; Label = 'Lists forced to classic' }
        @{ Count = 'AppInstanceCount'; Examples = 'AppInstanceExamples'; Label = 'App instances' }
        @{ Count = 'PublishingPageLayoutCount'; Examples = 'PublishingPageLayoutExamples'; Label = 'Page layouts in use' }
        @{ Count = 'ExternalListCount'; Examples = 'ExternalListExamples'; Label = 'External lists' }
        @{ Count = 'EmailEnabledListCount'; Examples = 'EmailEnabledListExamples'; Label = 'E-mail enabled lists' }
        @{ Count = 'HtmlFileCount'; Examples = 'HtmlFileExamples'; Label = 'HTML files' }
        @{ Count = 'CustomPermissionLevelCount'; Examples = 'CustomPermissionLevelExamples'; Label = 'Custom permission levels' }
        @{ Count = 'LargeListCount'; Examples = 'LargeListExamples'; Label = 'Large lists' }
        @{ Count = 'LargeListViewCount'; Examples = 'LargeListViewExamples'; Label = 'Large-list views' }
        @{ Count = 'CheckedOutFileCount'; Examples = 'CheckedOutFileExamples'; Label = 'Checked-out files' }
        @{ Count = 'FileVersionCount'; Examples = 'FileVersionExamples'; Label = 'High-version files' }
        @{ Count = 'LargeExcelFileCount'; Examples = 'LargeExcelFileExamples'; Label = 'Large Excel files' }
        @{ Count = 'AudienceTargetedItemCount'; Examples = 'AudienceTargetedExamples'; Label = 'Audience-targeted items' }
        @{ Count = 'SiteNotebookCount'; Examples = 'SiteNotebookExamples'; Label = 'Site notebooks' }
        @{ Count = 'CustomizedProfilePageCount'; Examples = 'CustomizedProfilePageExamples'; Label = 'Customized profile page' }
    ) {
        $signal = @(Get-Signal -Record (New-RecordWith @{ $Count = 2; $Examples = 'first (1); second (2)' }))

        $signal.Count | Should -Be 1
        $signal[0].Label | Should -Be $Label
        $signal[0].Detail | Should -Be 'first (1); second (2)'
    }

    It 'says why a template is unsupported or needs a review' {
        $unsupported = @(Get-Signal -Record (New-RecordWith @{ IsUnsupportedSiteTemplate = $true; Template = 'SPSMSITEHOST#0'; TemplateCompatibility = 'Unsupported'; TemplateCompatibilityReason = 'My Site host templates are not migrated.' }))
        $unsupported.Count | Should -Be 1
        $unsupported[0].Label | Should -Be 'Unsupported template'
        $unsupported[0].Value | Should -Be 'SPSMSITEHOST#0'
        $unsupported[0].Detail | Should -Be 'My Site host templates are not migrated.'

        $review = @(Get-Signal -Record (New-RecordWith @{ TemplateCompatibility = 'Review'; TemplateCompatibilityReason = 'Template needs validation.' }))
        $review.Count | Should -Be 1
        $review[0].Label | Should -Be 'Template compatibility'
        $review[0].Value | Should -Be 'Review'
        $review[0].Detail | Should -Be 'Template needs validation.'
    }

    It 'shows the template language to review, by tag or else by LCID' {
        $tagged = @(Get-Signal -Record (New-RecordWith @{ TemplateLanguageReviewRequired = $true; TemplateLanguageReason = 'Not mapped.' }))
        $tagged[0].Label | Should -Be 'Template language review'
        $tagged[0].Value | Should -Be 'en-US'
        $tagged[0].Detail | Should -Be 'Not mapped.'

        $untagged = @(Get-Signal -Record (New-RecordWith @{ TemplateLanguageReviewRequired = $true; TemplateLanguageTag = ''; TemplateLanguageLcid = 999999 }))
        $untagged[0].Value | Should -Be 'LCID 999999'
    }

    It 'shows each kind of lock, including an unknown one, and falls back to the lock flags' {
        foreach ($state in @('NoAdditions', 'ReadOnly', 'NoAccess', 'Unknown')) {
            $signal = @(Get-Signal -Record (New-RecordWith @{ SiteLockState = $state }))
            $signal.Count | Should -Be 1
            $signal[0].Label | Should -Be 'Site lock'
            $signal[0].Value | Should -Be $state
        }

        $noAccess = @(Get-Signal -Record (New-RecordWith @{ SiteLockState = ''; HasNoAccessLock = $true; IsLockedSite = $true }))
        $noAccess[0].Value | Should -Be 'NoAccess'
        $locked = @(Get-Signal -Record (New-RecordWith @{ SiteLockState = $null; IsLockedSite = $true }))
        $locked[0].Value | Should -Be 'Locked'
    }

    It 'tells FBA configured from FBA unknown, and says nothing when FBA is off' {
        (@(Get-Signal -Record (New-RecordWith @{ HasFbaZone = $true }))[0]).Value | Should -Be 'Yes'

        $unknown = @(Get-Signal -Record (New-RecordWith @{ HasFbaZone = $null }))
        $unknown.Count | Should -Be 1
        $unknown[0].Label | Should -Be 'FBA configured'
        $unknown[0].Value | Should -Be 'Unknown'

        # A record with no HasFbaZone field was not assessed for FBA: nothing to say.
        $record = New-QuietRecord
        $record.PSObject.Properties.Remove('HasFbaZone')
        @(Get-Signal -Record $record).Count | Should -Be 0
    }

    It 'gives the workflows and their running instances in one line each' {
        $signal = @(Get-Signal -Record (New-RecordWith @{ Workflow2010Count = 3; Workflow2010RunningInstanceCount = 2; Workflow2013RunningInstanceCount = 5 }))

        $signal.Count | Should -Be 2
        $signal[0].Label | Should -Be 'Workflow 2010'
        $signal[0].Value | Should -Be '3 workflow(s), 2 running instance(s)'
        $signal[1].Label | Should -Be 'Workflow 2013'
        $signal[1].Value | Should -Be '5 running instance(s)'
    }

    It 'gives the managed metadata lists, columns and term sets in one line' {
        $signal = @(Get-Signal -Record (New-RecordWith @{ ManagedMetadataListCount = 2; ManagedMetadataColumnCount = 3; ManagedMetadataTermSetCount = 1; ManagedMetadataExamples = 'Contracts (Department)' }))

        $signal.Count | Should -Be 1
        $signal[0].Label | Should -Be 'Managed metadata'
        $signal[0].Value | Should -Be '2 list(s), 3 column(s), 1 term set(s)'
        $signal[0].Detail | Should -Be 'Contracts (Department)'
    }

    It 'gives the number of subsites with their depth, not the number of webs' {
        $signal = @(Get-Signal -Record (New-RecordWith @{ SubWebCount = 4; SubsiteCount = 3; MaxSubsiteDepth = 2; SubsiteExamples = 'a/b (level 2); a (level 1)' }))

        $signal.Count | Should -Be 1
        $signal[0].Label | Should -Be 'Subsites'
        $signal[0].Value | Should -Be '3 (depth 2)'
        $signal[0].Detail | Should -Be 'a/b (level 2); a (level 1)'
    }

    It 'flags each inventory that is incomplete, because its figures are then lower bounds' {
        $signal = @(Get-Signal -Record (New-RecordWith @{ SiteInventoryComplete = $false; CustomizationInventoryComplete = $false; ContentTypeInventoryComplete = $false }))

        $signal.Label | Should -Be @('Site inventory incomplete', 'Customization inventory incomplete', 'Content type inventory incomplete')
        # An inventory whose completeness is not known is not reported as incomplete.
        @(Get-Signal -Record (New-RecordWith @{ SiteInventoryComplete = $null })).Count | Should -Be 0
    }

    It 'treats the text True and False like the booleans and ignores a count that is not a number' {
        @(Get-Signal -Record (New-RecordWith @{ CustomMasterPage = 'True' })).Count | Should -Be 1
        @(Get-Signal -Record (New-RecordWith @{ CustomMasterPage = 'false' })).Count | Should -Be 0
        @(Get-Signal -Record (New-RecordWith @{ SandboxSolutions = '' })).Count | Should -Be 0
        @(Get-Signal -Record (New-RecordWith @{ SandboxSolutions = '2' })).Count | Should -Be 1
    }

    It 'formats the numbers the same way in every culture' {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
            $signal = @(Get-Signal -Record (New-RecordWith @{ SharePointAlertCount = 12345; UniquePermissionsCount = 7.5 }))
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }

        ($signal | Where-Object Label -eq 'SharePoint alerts').Value | Should -Be '12345'
    }

    It 'keeps the signals in a fixed order, template and lock first, inventory completeness last' {
        $record = New-RecordWith @{
            TemplateCompatibility = 'Review'; SiteLockState = 'ReadOnly'; UsesFullTrustCode = $true; HasFbaZone = $true
            PublishingPageCount = 4; LargeListCount = 1; SiteInventoryComplete = $false
        }

        $labels = @((Get-Signal -Record $record).Label)

        $labels | Should -Be @('Template compatibility', 'Site lock', 'Full-trust code', 'FBA configured', 'Publishing pages', 'Large lists', 'Site inventory incomplete')
    }

    It 'lists the signals of the modern experience with the code and customization ones, before the identity ones' {
        $record = New-RecordWith @{
            CustomMasterPage = $true; AlternateCssUrlCount = 1; XsltListViewCount = 2; ScriptWebPartCount = 3
            ClassicExperienceOptOutCount = 1; ClassicExperienceListCount = 2; CustomizedPageCount = 4; HasFbaZone = $true
        }

        $labels = @((Get-Signal -Record $record).Label)

        $labels | Should -Be @('Custom master page', 'Alternate CSS URL (webs)', 'XSLT list views', 'Script web parts', 'Opted out of modern lists', 'Lists forced to classic', 'Customized pages', 'FBA configured')
    }
}
