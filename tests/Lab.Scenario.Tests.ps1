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

    It 'treat the three lock states differently: a NoAccess lock is only informational, the others must be reported as a lock and not as a blocker' {
        foreach ($state in @('readonly', 'noadditions')) {
            $scenario = $script:Scenario | Where-Object { $_.Name -eq "lock-$state" }
            @($scenario.Expect | Where-Object { $_.Info }).Count | Should -Be 0 -Because $state
            @($scenario.Expect | Where-Object { $_.Property -eq 'HasNoAccessLock' }).Value | Should -BeFalse
            @($scenario.Expect | Where-Object { $_.Alert -eq 'LockedSite' }).Count | Should -Be 1
        }
        $noAccess = $script:Scenario | Where-Object { $_.Name -eq 'lock-noaccess' }
        @($noAccess.Expect | Where-Object { -not $_.Info }).Count | Should -Be 0
        @($noAccess.Expect | Where-Object { $_.Alert -eq 'NoAccessSite' }).Count | Should -Be 1
    }

    It 'build the large-content scenario from the lab thresholds, so that it triggers whatever they are' {
        $source = & $script:SourceOf 'large-content'

        $source | Should -Match 'Threshold\.FileVersionCount'
        $source | Should -Match 'Threshold\.LargeListItemCount'
        $source | Should -Match 'Threshold\.LargeListViewRowLimit'
        $source | Should -Match 'CheckOut\(\)'
    }

    It 'say that they are skipped, not failed, when the farm lacks what they need' {
        foreach ($name in @('workflow-2010', 'email-enabled', 'irm', 'html-files', 'custom-master', 'customized-page')) {
            (& $script:SourceOf $name) | Should -Match "SKIP:" -Because $name
        }
    }

    It 'only expect to be informational what depends on the account or the farm' {
        foreach ($name in @('customized-page', 'email-enabled', 'irm')) {
            $scenario = $script:Scenario | Where-Object { $_.Name -eq $name }
            @($scenario.Expect | Where-Object { -not $_.Info }).Count | Should -Be 0 -Because $name
        }
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
