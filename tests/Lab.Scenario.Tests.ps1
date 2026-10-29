# The lab scripts write to a farm, so they cannot run here. These tests keep what they promise true:
# what each scenario expects must exist in the toolkit, so that the lab cannot drift from it.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    Import-Module -Name (Join-Path $repoRoot 'tools/lab/SPSInventoryLab.psm1') -Force
    $script:Scenario = @(Get-SPSLabScenario)
    $script:Catalog = & (Get-Module -Name SPSSiteInventory.Common) { Get-SPSAlertCatalog }

    # The fields of the inventory record, read from the code that builds it.
    $assessment = Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/Private/Invoke-SPSiteAssessment.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($assessment, [ref]$null, [ref]$null)
    $tables = $ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true)
    $script:RecordField = @()
    foreach ($table in $tables) {
        $keys = @($table.KeyValuePairs | ForEach-Object { [System.String]$_.Item1.Value })
        if ($keys -contains 'AssessmentStatus' -and $keys -contains 'Score' -and $keys -contains 'Workflow2010Count') {
            $script:RecordField = $keys
            break
        }
    }

    # Wave and WaveName are added to the record after the assessment, by Group-SPSMigrationWave.
    $waved = @(Group-SPSMigrationWave -InputObject @([PSCustomObject]@{ Category = 1; CategoryName = 'Simple' }) -MigrationWaves @())
    $script:RecordField += @($waved[0].PSObject.Properties.Name | Where-Object { $_ -in @('Wave', 'WaveName') })

    $script:Wiki = Get-Content -Path (Join-Path $repoRoot 'wiki/Lab-Testing.md') -Raw
    $script:ExampleThresholds = (Get-SPSInventorySetting -Path (Join-Path $repoRoot 'src/config/inventory-settings.example.psd1')).LargeContentThresholds
    $script:SourceOf = {
        param ($name)
        ($script:Scenario | Where-Object { $_.Name -eq $name }).Provision.ToString()
    }
}

Describe 'The lab scenarios' {
    It 'read the fields of the inventory record from the code, so that the check below means something' {
        $script:RecordField.Count | Should -BeGreaterThan 50
        $script:RecordField | Should -Contain 'SubsiteCount'
        $script:RecordField | Should -Contain 'AssessmentStatus'
    }

    It 'have unique names that make a valid URL' {
        $names = @($script:Scenario | ForEach-Object { $_.Name })

        @($names | Select-Object -Unique).Count | Should -Be $names.Count
        foreach ($name in $names) {
            $name | Should -Match '^[a-z][a-z0-9-]{1,30}$'
        }
    }

    It 'describe themselves, name a site template and build their content with a script block' {
        foreach ($scenario in $script:Scenario) {
            $scenario.Description | Should -Not -BeNullOrEmpty -Because "scenario $($scenario.Name)"
            $scenario.Template | Should -Match '^[A-Z]+#\d+$' -Because "scenario $($scenario.Name)"
            $scenario.Provision | Should -BeOfType [System.Management.Automation.ScriptBlock]
            @($scenario.Expect).Count | Should -BeGreaterThan 0 -Because "scenario $($scenario.Name)"
        }
    }

    It 'only expect properties that the inventory record has' {
        foreach ($scenario in $script:Scenario) {
            foreach ($expectation in @($scenario.Expect | Where-Object { $_.ContainsKey('Property') })) {
                $script:RecordField | Should -Contain $expectation.Property -Because "scenario $($scenario.Name) expects $($expectation.Property)"
            }
        }
    }

    It 'only expect alerts that are in the alert catalog' {
        foreach ($scenario in $script:Scenario) {
            foreach ($expectation in @($scenario.Expect | Where-Object { $_.ContainsKey('Alert') })) {
                $script:Catalog.Contains($expectation.Alert) | Should -BeTrue -Because "scenario $($scenario.Name) expects the alert $($expectation.Alert)"
            }
        }
    }

    It 'expect either a property with an operator and a value, or an alert, and say whether they are informational' {
        foreach ($scenario in $script:Scenario) {
            foreach ($expectation in @($scenario.Expect)) {
                $expectation.Info | Should -BeOfType [System.Boolean]
                if ($expectation.ContainsKey('Alert')) {
                    $expectation.Alert | Should -Not -BeNullOrEmpty
                }
                else {
                    $expectation.Operator | Should -BeIn @('eq', 'ne', 'ge', 'gt', 'le', 'lt', 'like', 'match')
                    $expectation.ContainsKey('Value') | Should -BeTrue
                }
            }
        }
    }

    It 'expect a clean, complete and Simple baseline' {
        $baseline = $script:Scenario | Where-Object { $_.Name -eq 'baseline' }
        $properties = @($baseline.Expect | ForEach-Object { $_.Property })

        $properties | Should -Contain 'AssessmentStatus'
        $properties | Should -Contain 'SubsiteCount'
        @($baseline.Expect | Where-Object { $_.Info }).Count | Should -Be 0
    }

    It 'build five subsites three levels deep and expect exactly that' {
        $subsites = $script:Scenario | Where-Object { $_.Name -eq 'subsites' }
        $expected = @{}
        foreach ($expectation in @($subsites.Expect | Where-Object { $_.ContainsKey('Property') })) {
            $expected[$expectation.Property] = $expectation.Value
        }

        $expected['SubsiteCount'] | Should -Be 5
        $expected['MaxSubsiteDepth'] | Should -Be 3
        $expected['SubWebCount'] | Should -Be 6
        $expected['SubsiteExamples'] | Should -Be 'a/b/c (level 3)*'
        (& $script:SourceOf 'subsites') | Should -Match "Webs\.Add\('a'"
        (& $script:SourceOf 'subsites') | Should -Match "\`$a\.Webs\.Add\('b'"
        (& $script:SourceOf 'subsites') | Should -Match "\`$b\.Webs\.Add\('c'"
    }

    It 'treat the three lock states differently: a NoAccess lock must be reported as a blocker, the others as a lock and not as a blocker' {
        foreach ($state in @('readonly', 'noadditions')) {
            $scenario = $script:Scenario | Where-Object { $_.Name -eq "lock-$state" }
            @($scenario.Expect | Where-Object { $_.Info }).Count | Should -Be 0 -Because $state
            @($scenario.Expect | Where-Object { $_.Property -eq 'HasNoAccessLock' }).Value | Should -BeFalse
            @($scenario.Expect | Where-Object { $_.Alert -eq 'LockedSite' }).Count | Should -Be 1
        }
        $noAccess = $script:Scenario | Where-Object { $_.Name -eq 'lock-noaccess' }
        @($noAccess.Expect | Where-Object { $_.Info }).Count | Should -Be 0
        @($noAccess.Expect | Where-Object { $_.Property -eq 'SiteLockState' }).Value | Should -Be 'NoAccess'
        @($noAccess.Expect | Where-Object { $_.Property -eq 'IsLockedSite' }).Value | Should -BeTrue
        @($noAccess.Expect | Where-Object { $_.Property -eq 'HasNoAccessLock' }).Value | Should -BeTrue
        @($noAccess.Expect | Where-Object { $_.Property -eq 'Category' }).Value | Should -Be 4
        @($noAccess.Expect | Where-Object { $_.Alert -eq 'NoAccessSite' }).Count | Should -Be 1
    }

    It 'expect the template and the language of a site that cannot be read to stay empty and raise no review alert' {
        $noAccess = $script:Scenario | Where-Object { $_.Name -eq 'lock-noaccess' }
        $property = @($noAccess.Expect | Where-Object { $_.ContainsKey('Property') })

        @($property | Where-Object { $_.Property -eq 'Template' }).Value | Should -Be ''
        @($property | Where-Object { $_.Property -eq 'TemplateLanguageLcid' }).Value | Should -BeNullOrEmpty
        @($property | Where-Object { $_.Property -eq 'TemplateLanguageLcid' }).Operator | Should -Be 'eq'
        @($property | Where-Object { $_.Property -eq 'TemplateCompatibility' }).Value | Should -Be 'NotCollected'
        @($property | Where-Object { $_.Property -eq 'SiteInventoryWarnings' }).Value | Should -BeLike '*Root web metadata could not be fully read*'
        $absent = @($noAccess.Expect | Where-Object { $_.ContainsKey('Alert') -and $_.Absent } | ForEach-Object { $_.Alert })
        $absent | Should -Be @('TemplateCompatibilityReview', 'TemplateLanguageReview')

        # What the inventory writes for such a site meets them, and what it wrote before (the template '#' and the language 0, with the alerts) does not.
        $written = [PSCustomObject]@{
            SiteLockState = 'NoAccess'; IsLockedSite = $true; HasNoAccessLock = $true; Category = 4; Template = ''; TemplateLanguageLcid = $null
            TemplateCompatibility = 'NotCollected'; SiteInventoryWarnings = 'Root web metadata could not be fully read (Title): Access to this Web site has been blocked.'
        }
        $before = [PSCustomObject]@{
            SiteLockState = 'NoAccess'; IsLockedSite = $true; HasNoAccessLock = $true; Category = 4; Template = '#'; TemplateLanguageLcid = 0
            TemplateCompatibility = 'Review'; SiteInventoryWarnings = 'Storage usage could not be read: x'
        }
        $raised = @('NoAccessSite')
        $beforeRaised = @('NoAccessSite', 'TemplateCompatibilityReview', 'TemplateLanguageReview')
        foreach ($expectation in @($noAccess.Expect)) {
            (Test-SPSLabExpectation -Expectation $expectation -Record $written -Alert $raised).Status | Should -Be 'PASS' -Because ($expectation | ConvertTo-Json -Compress)
        }
        $failed = @($noAccess.Expect | Where-Object { (Test-SPSLabExpectation -Expectation $_ -Record $before -Alert $beforeRaised).Status -eq 'FAIL' })
        @($failed | ForEach-Object { if ($_.ContainsKey('Alert')) { 'No alert ' + $_.Alert } else { $_.Property } }) | Should -Be @('Template', 'TemplateLanguageLcid', 'TemplateCompatibility', 'SiteInventoryWarnings', 'No alert TemplateCompatibilityReview', 'No alert TemplateLanguageReview')
    }

    It 'build a Simple site collection with a partial assessment and expect it in the Needs review wave, not in the quick wins' {
        $scenario = $script:Scenario | Where-Object { $_.Name -eq 'partial-simple' }

        @($scenario.Expect | Where-Object { $_.Info }).Count | Should -Be 0
        @($scenario.Expect | Where-Object { $_.Property -eq 'AssessmentStatus' }).Value | Should -Be 'Partial'
        @($scenario.Expect | Where-Object { $_.Property -eq 'Category' }).Value | Should -Be 1
        @($scenario.Expect | Where-Object { $_.Property -eq 'Wave' }).Value | Should -Be 0
        @($scenario.Expect | Where-Object { $_.Property -eq 'WaveName' }).Value | Should -Be 'Needs review'
        @($scenario.Expect | Where-Object { $_.Alert -eq 'AssessmentPartial' }).Count | Should -Be 1

        $needsReview = [PSCustomObject]@{ AssessmentStatus = 'Partial'; SharePointAlertCount = 3; Category = 1; Wave = 0; WaveName = 'Needs review' }
        $quickWin = [PSCustomObject]@{ AssessmentStatus = 'Partial'; SharePointAlertCount = 3; Category = 1; Wave = 1; WaveName = 'Quick wins' }
        foreach ($expectation in @($scenario.Expect | Where-Object { $_.ContainsKey('Property') })) {
            (Test-SPSLabExpectation -Expectation $expectation -Record $needsReview -Alert @('AssessmentPartial')).Status | Should -Be 'PASS' -Because $expectation.Property
        }
        # The old behavior, a partial Simple site in the quick wins, must fail the scenario.
        $failed = @($scenario.Expect | Where-Object { $_.ContainsKey('Property') } | Where-Object { (Test-SPSLabExpectation -Expectation $_ -Record $quickWin -Alert @('AssessmentPartial')).Status -eq 'FAIL' } | ForEach-Object { $_.Property })
        $failed | Should -Be @('Wave', 'WaveName')
    }

    It 'give the partial-simple scenario one alert more than the lab lets the inventory export, and the alerts scenario no more than that' {
        $cap = (Get-SPSLabThreshold).MaxAlertRowsPerSite
        $partialAlerts = [regex]::Matches((& $script:SourceOf 'partial-simple'), '\.Alerts\.Add\(').Count
        $alertsAlerts = [regex]::Matches((& $script:SourceOf 'alerts'), '\.Alerts\.Add\(').Count

        $partialAlerts | Should -BeGreaterThan $cap -Because 'the alert rows left out by the cap are what makes the assessment partial'
        $alertsAlerts | Should -BeLessOrEqual $cap -Because 'the alerts scenario must stay complete'
    }

    It 'build the large-content scenario from the lab thresholds, so that it triggers whatever they are' {
        $source = & $script:SourceOf 'large-content'

        $source | Should -Match 'Threshold\.FileVersionCount'
        $source | Should -Match 'Threshold\.LargeListItemCount'
        $source | Should -Match 'Threshold\.LargeListViewRowLimit'
        $source | Should -Match 'CheckOut\(\)'
    }

    It 'say that they are skipped, not failed, when the farm lacks what they need' {
        foreach ($name in @('workflow-2010', 'email-enabled', 'irm', 'html-files', 'custom-master', 'customized-page', 'event-receiver')) {
            (& $script:SourceOf $name) | Should -Match "SKIP:" -Because $name
        }
    }

    It 'only expect to be informational what depends on the account or the farm' {
        foreach ($name in @('customized-page', 'email-enabled', 'irm')) {
            $scenario = $script:Scenario | Where-Object { $_.Name -eq $name }
            @($scenario.Expect | Where-Object { -not $_.Info }).Count | Should -Be 0 -Because $name
        }
    }

    It 'read the classic customization signals in the columns of the inventory, not in the reasons of the score' {
        foreach ($scenario in $script:Scenario) {
            @($scenario.Expect | Where-Object { $_.Property -eq 'Reasons' }) | Should -HaveCount 0 -Because "scenario $($scenario.Name)"
        }
        $receiver = $script:Scenario | Where-Object { $_.Name -eq 'event-receiver' }
        $master = $script:Scenario | Where-Object { $_.Name -eq 'custom-master' }
        $receiver.Expect | Should -HaveCount 1
        $receiver.Expect[0].Property | Should -Be 'EventReceivers'
        $receiver.Expect[0].Operator | Should -Be 'ge'
        $receiver.Expect[0].Value | Should -Be 1
        $master.Expect | Should -HaveCount 1
        $master.Expect[0].Property | Should -Be 'CustomMasterPage'
        $master.Expect[0].Operator | Should -Be 'eq'
        $master.Expect[0].Value | Should -BeTrue
    }

    It 'meet the expectations on the columns with the values that the inventory writes' {
        $receiver = $script:Scenario | Where-Object { $_.Name -eq 'event-receiver' }
        $master = $script:Scenario | Where-Object { $_.Name -eq 'custom-master' }

        (Test-SPSLabExpectation -Expectation $receiver.Expect[0] -Record ([PSCustomObject]@{ EventReceivers = 2 }) -Alert @()).Status | Should -Be 'PASS'
        (Test-SPSLabExpectation -Expectation $receiver.Expect[0] -Record ([PSCustomObject]@{ EventReceivers = 0 }) -Alert @()).Status | Should -Be 'FAIL'
        (Test-SPSLabExpectation -Expectation $receiver.Expect[0] -Record ([PSCustomObject]@{ EventReceivers = $null }) -Alert @()).Status | Should -Be 'FAIL'
        (Test-SPSLabExpectation -Expectation $master.Expect[0] -Record ([PSCustomObject]@{ CustomMasterPage = $true }) -Alert @()).Status | Should -Be 'PASS'
        (Test-SPSLabExpectation -Expectation $master.Expect[0] -Record ([PSCustomObject]@{ CustomMasterPage = $false }) -Alert @()).Status | Should -Be 'FAIL'
        (Test-SPSLabExpectation -Expectation $master.Expect[0] -Record ([PSCustomObject]@{ CustomMasterPage = 'True' }) -Alert @()).Status | Should -Be 'PASS'
    }

    It 'are all documented in the lab testing wiki page, with their description' {
        foreach ($scenario in $script:Scenario) {
            $script:Wiki | Should -Match ('\| `{0}` \|' -f [regex]::Escape($scenario.Name)) -Because "scenario $($scenario.Name) must be documented"
            $script:Wiki.Contains($scenario.Description) | Should -BeTrue -Because "the wiki must carry the description of $($scenario.Name)"
        }
    }

    It 'return only the scenarios that are asked for' {
        $some = @(Get-SPSLabScenario -Name 'subsites', 'infopath')

        @($some | ForEach-Object { $_.Name }) | Should -Be @('subsites', 'infopath')
        @(Get-SPSLabScenario -Name 'nothing') | Should -HaveCount 0
        @(Get-SPSLabScenario -Name $null).Count | Should -Be $script:Scenario.Count
    }
}

Describe 'The scenarios of the modern-readiness signals' {
    BeforeAll {
        $script:ModernScenario = @('alternate-css', 'xslt-view', 'script-web-part', 'modern-opt-out', 'forced-classic')
        $script:Passing = @{
            'alternate-css'   = [PSCustomObject]@{ AlternateCssUrlCount = 1; AlternateCssUrlExamples = 'https://lab.contoso.local/sites/spslab-alternate-css (/sites/spslab-alternate-css/LabStyles/lab.css)'; ModernBlockerCount = 1 }
            'xslt-view'       = [PSCustomObject]@{ XsltListViewCount = 1; XsltListViewExamples = 'LabXslList/LabXslView'; ModernBlockerCount = 1 }
            'script-web-part' = [PSCustomObject]@{ ScriptWebPartCount = 2; ScriptWebPartExamples = '/sites/spslab-script-web-part/SitePages/Home.aspx (Script Editor); /sites/spslab-script-web-part/SitePages/Home.aspx (Content Editor)'; ModernBlockerCount = 1 }
            'modern-opt-out'  = [PSCustomObject]@{ ClassicExperienceOptOutCount = 2; ClassicExperienceOptOutExamples = 'https://lab.contoso.local/sites/spslab-modern-opt-out (site collection); https://lab.contoso.local/sites/spslab-modern-opt-out (web)'; ModernBlockerCount = 1 }
            'forced-classic'  = [PSCustomObject]@{ ClassicExperienceListCount = 1; ClassicExperienceListExamples = 'LabClassic (/sites/spslab-forced-classic/Lists/LabClassic)'; ModernBlockerCount = 1 }
        }
    }

    It 'exist, and are all expected to be met, none only informational' {
        foreach ($name in $script:ModernScenario) {
            $scenario = $script:Scenario | Where-Object { $_.Name -eq $name }
            $scenario | Should -Not -BeNullOrEmpty -Because $name
            @($scenario.Expect | Where-Object { $_.Info }).Count | Should -Be 0 -Because $name
        }
    }

    It 'are skipped, not failed, when the SharePoint of the farm lacks what they need' {
        foreach ($name in @('xslt-view', 'script-web-part', 'modern-opt-out', 'forced-classic')) {
            (& $script:SourceOf $name) | Should -Match 'SKIP:' -Because $name
        }
    }

    It 'skip only for what the farm lacks: an error of an activation or of an addition fails the scenario' {
        $optOut = & $script:SourceOf 'modern-opt-out'
        $optOut | Should -Match 'Get-SPFeature -Identity \$featureId'
        $optOut | Should -Match 'SKIP: the feature'
        $optOut | Should -Not -Match 'catch'
        (& $script:SourceOf 'script-web-part') | Should -Not -Match 'catch'
    }

    It 'build what their expectations need' {
        (& $script:SourceOf 'alternate-css') | Should -Match 'AlternateCssUrl'
        (& $script:SourceOf 'xslt-view') | Should -Match 'XslLink'
        $script = & $script:SourceOf 'script-web-part'
        $script | Should -Match 'ScriptEditorWebPart'
        $script | Should -Match 'ContentEditorWebPart'
        $script | Should -Match 'GetLimitedWebPartManager'
        $optOut = & $script:SourceOf 'modern-opt-out'
        $optOut | Should -Match 'E3540C7D-6BEA-403C-A224-1A12EAFEE4C4'
        $optOut | Should -Match '52E14B6F-B1BB-4969-B89B-C4FAA56745EF'
        (& $script:SourceOf 'forced-classic') | Should -Match 'ListExperienceOptions'
    }

    It 'dispose of the web part manager and of its web' {
        $script = & $script:SourceOf 'script-web-part'
        $script | Should -Match 'Web\.Dispose\(\)'
        $script | Should -Match 'Manager\.Dispose\(\)|\$manager\.Dispose\(\)'
    }

    It 'expect none of those signals of the baseline site, so that a default of SharePoint taken for a customization fails there' {
        $baseline = $script:Scenario | Where-Object { $_.Name -eq 'baseline' }
        foreach ($property in @('AlternateCssUrlCount', 'XsltListViewCount', 'ScriptWebPartCount', 'ClassicExperienceOptOutCount', 'ClassicExperienceListCount', 'ModernBlockerCount')) {
            $expectation = @($baseline.Expect | Where-Object { $_.Property -eq $property })
            $expectation | Should -HaveCount 1 -Because $property
            $expectation[0].Operator | Should -Be 'eq'
            $expectation[0].Value | Should -Be 0
            $expectation[0].Info | Should -BeFalse
        }
    }

    It 'meet their expectations with the values that the inventory writes' {
        foreach ($name in $script:ModernScenario) {
            $scenario = $script:Scenario | Where-Object { $_.Name -eq $name }
            foreach ($expectation in @($scenario.Expect)) {
                (Test-SPSLabExpectation -Expectation $expectation -Record $script:Passing[$name] -Alert @()).Status | Should -Be 'PASS' -Because "$name expects $($expectation.Property)"
            }
        }
    }

    It 'fail when the inventory reports nothing, as it does when a collector is broken' {
        $empty = [PSCustomObject]@{
            AlternateCssUrlCount = 0; AlternateCssUrlExamples = ''; XsltListViewCount = 0; XsltListViewExamples = ''
            ScriptWebPartCount = 0; ScriptWebPartExamples = ''; ClassicExperienceOptOutCount = 0; ClassicExperienceOptOutExamples = ''
            ClassicExperienceListCount = 0; ClassicExperienceListExamples = ''; ModernBlockerCount = 0
        }
        foreach ($name in $script:ModernScenario) {
            $scenario = $script:Scenario | Where-Object { $_.Name -eq $name }
            $statuses = @($scenario.Expect | ForEach-Object { (Test-SPSLabExpectation -Expectation $_ -Record $empty -Alert @()).Status })
            $statuses | Should -Not -Contain 'PASS' -Because $name
        }
    }
}

Describe 'The event-receiver scenario' {
    BeforeAll {
        # The receiver type of SharePoint, as a stand-in: the scenario only needs the enumeration to exist.
        if (-not ('Microsoft.SharePoint.SPEventReceiverType' -as [type])) {
            Add-Type -TypeDefinition 'namespace Microsoft.SharePoint { public enum SPEventReceiverType { ItemDeleting = 4 } }'
        }
        $script:Receiver = $script:Scenario | Where-Object { $_.Name -eq 'event-receiver' }

        function global:New-LabReceiverContext {
            param ($Failure)
            $global:LabReceiverFailure = $Failure
            $events = [PSCustomObject]@{}
            $events | Add-Member -MemberType ScriptMethod -Name Add -Value {
                param ($Type, $Assembly, $Class)
                $global:LabReceiverCall = '{0}|{1}|{2}' -f $Type, $Assembly, $Class
                if ($null -ne $global:LabReceiverFailure) { throw $global:LabReceiverFailure }
            }
            $list = [PSCustomObject]@{ EventReceivers = $events }
            $global:LabReceiverList = $list
            return [PSCustomObject]@{ Web = [PSCustomObject]@{} }
        }
    }

    BeforeEach {
        $global:LabReceiverCall = $null
        Mock -ModuleName SPSInventoryLab Add-SPSLabList { $global:LabReceiverList }
    }

    AfterAll {
        Remove-Item -Path 'function:global:New-LabReceiverContext' -ErrorAction SilentlyContinue
        Remove-Variable -Name LabReceiverFailure, LabReceiverCall, LabReceiverList -Scope Global -ErrorAction SilentlyContinue
    }

    It 'registers the receiver when the assembly can be loaded' {
        $context = New-LabReceiverContext -Failure $null

        { & $script:Receiver.Provision $context } | Should -Not -Throw

        $global:LabReceiverCall | Should -BeLike 'ItemDeleting|Contoso.Lab.Receivers, *|Contoso.Lab.Receivers.ItemReceiver'
    }

    It 'is skipped, with the reason, when SharePoint cannot load the assembly (<Name>)' -ForEach @(
        @{ Name = 'a call that wraps a FileNotFoundException'; Failure = [System.Management.Automation.MethodInvocationException]::new('Exception calling "Add" with "3" argument(s): "Could not load file or assembly ''Contoso.Lab.Receivers''."', [System.IO.FileNotFoundException]::new('The system cannot find the file specified.')) }
        @{ Name = 'a call that wraps a FileLoadException'; Failure = [System.Management.Automation.MethodInvocationException]::new('Exception calling "Add" with "3" argument(s): "The assembly cannot be used."', [System.IO.FileLoadException]::new('The located assembly''s manifest definition does not match.')) }
        @{ Name = 'a FileNotFoundException'; Failure = [System.IO.FileNotFoundException]::new('Contoso.Lab.Receivers') }
        @{ Name = 'a message that says the assembly could not be loaded'; Failure = [System.InvalidOperationException]::new('Could not load file or assembly ''Contoso.Lab.Receivers, Version=1.0.0.0'' or one of its dependencies.') }
    ) {
        $context = New-LabReceiverContext -Failure $Failure

        { & $script:Receiver.Provision $context } | Should -Throw 'SKIP: SharePoint loads the assembly to register an event receiver: deploy one to test this signal*'
    }

    It 'stays a failure for any other error (<Name>)' -ForEach @(
        @{ Name = 'access denied'; Failure = [System.UnauthorizedAccessException]::new('Access is denied.') }
        @{ Name = 'a wrapped invalid operation'; Failure = [System.Management.Automation.MethodInvocationException]::new('Exception calling "Add" with "3" argument(s): "The list is read only."', [System.InvalidOperationException]::new('The list is read only.')) }
    ) {
        $context = New-LabReceiverContext -Failure $Failure
        $message = $null

        try { & $script:Receiver.Provision $context } catch { $message = $_.Exception.Message }

        $message | Should -Not -BeNullOrEmpty
        $message | Should -Not -BeLike 'SKIP:*'
    }
}

Describe 'Test-SPSLabAssemblyLoadFailure' {
    It 'recognizes a FileNotFoundException, a FileLoadException and the message of a failed load, at any depth' {
        $inner = [System.IO.FileLoadException]::new('The assembly cannot be used.')
        $outer = [System.Exception]::new('outer', [System.InvalidOperationException]::new('middle', $inner))

        foreach ($exception in @([System.IO.FileNotFoundException]::new('x'), $inner, $outer, [System.Exception]::new('Could not load file or assembly ''x''.'))) {
            $record = [System.Management.Automation.ErrorRecord]::new($exception, 'Id', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            & (Get-Module -Name SPSInventoryLab) { param ($Record) Test-SPSLabAssemblyLoadFailure -ErrorRecord $Record } $record | Should -BeTrue
        }
    }

    It 'does not recognize another error' {
        foreach ($exception in @([System.UnauthorizedAccessException]::new('Access is denied.'), [System.IO.IOException]::new('The file is locked.'), [System.ArgumentException]::new('Bad value.'))) {
            $record = [System.Management.Automation.ErrorRecord]::new($exception, 'Id', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            & (Get-Module -Name SPSInventoryLab) { param ($Record) Test-SPSLabAssemblyLoadFailure -ErrorRecord $Record } $record | Should -BeFalse
        }
    }
}

Describe 'Get-SPSLabThreshold' {
    It 'only changes thresholds that the example configuration has, to values above zero' {
        foreach ($threshold in (Get-SPSLabThreshold).GetEnumerator()) {
            $script:ExampleThresholds.Contains($threshold.Key) | Should -BeTrue -Because $threshold.Key
            $threshold.Value | Should -BeGreaterThan 0
            $threshold.Value | Should -BeLessOrEqual $script:ExampleThresholds[$threshold.Key] -Because "$($threshold.Key) must not be higher than in production, or the lab proves nothing"
        }
    }

    It 'keeps the large-list threshold above what the system lists of a new site reach' {
        (Get-SPSLabThreshold).LargeListItemCount | Should -BeGreaterOrEqual 100
    }
}
