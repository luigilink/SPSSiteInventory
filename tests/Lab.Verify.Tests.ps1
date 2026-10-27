BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    Import-Module -Name (Join-Path $repoRoot 'tools/lab/SPSInventoryLab.psm1') -Force

    function Test-Expectation {
        param
        (
            [System.Collections.IDictionary] $Expectation,
            [System.Object] $Record,
            [System.String[]] $Alert
        )

        return & (Get-Module -Name SPSInventoryLab) {
            param ($e, $r, $a)
            Test-SPSLabExpectation -Expectation $e -Record $r -Alert $a
        } $Expectation $Record $Alert
    }

    function Get-Expectation {
        param ([System.String] $Property, [System.String] $Operator = 'eq', $Value, [System.Management.Automation.SwitchParameter] $Info, [System.String] $Alert)

        return & (Get-Module -Name SPSInventoryLab) {
            param ($p, $o, $v, $i, $a)
            if ($a) { Get-SPSLabExpectation -Alert $a -Info:$i } else { Get-SPSLabExpectation $p $o $v -Info:$i }
        } $Property $Operator $Value ([bool]$Info) $Alert
    }
}

Describe 'Test-SPSLabExpectation' {
    It 'compares numbers as numbers, whether they come from JSON as integers, doubles or text' {
        $record = [PSCustomObject]@{ SubsiteCount = 5; Score = 1.25; Text = '7' }

        (Test-Expectation (Get-Expectation SubsiteCount eq 5) $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation SubsiteCount ge 5) $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation SubsiteCount gt 5) $record).Status | Should -Be 'FAIL'
        (Test-Expectation (Get-Expectation SubsiteCount le 4) $record).Status | Should -Be 'FAIL'
        (Test-Expectation (Get-Expectation SubsiteCount lt 6) $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation SubsiteCount ne 5) $record).Status | Should -Be 'FAIL'
        (Test-Expectation (Get-Expectation Score ge 1.2) $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation Text eq 7) $record).Status | Should -Be 'PASS'
    }

    It 'compares booleans, and does not read a missing value as false' {
        $record = [PSCustomObject]@{ IsLockedSite = $true; HasNoAccessLock = $false; Nothing = $null }

        (Test-Expectation (Get-Expectation IsLockedSite eq $true) $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation HasNoAccessLock eq $false) $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation HasNoAccessLock eq $true) $record).Status | Should -Be 'FAIL'
        (Test-Expectation (Get-Expectation Nothing eq $false) $record).Status | Should -Be 'FAIL'
    }

    It 'compares text without regard to case, with wildcards and regular expressions' {
        $record = [PSCustomObject]@{ AssessmentStatus = 'Complete'; SubsiteExamples = 'a/b/c (level 3); a (level 1)' }

        (Test-Expectation (Get-Expectation AssessmentStatus eq 'complete') $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation AssessmentStatus ne 'Partial') $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation SubsiteExamples like 'a/b/c (level 3)*') $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation SubsiteExamples like 'c (level 3)*') $record).Status | Should -Be 'FAIL'
        (Test-Expectation (Get-Expectation SubsiteExamples match 'level 3\)') $record).Status | Should -Be 'PASS'
        (Test-Expectation (Get-Expectation AssessmentStatus ge 3) $record).Status | Should -Be 'FAIL'
    }

    It 'reports the expected and the actual value' {
        $result = Test-Expectation (Get-Expectation SubsiteCount eq 5) ([PSCustomObject]@{ SubsiteCount = 3 })

        $result.Check | Should -Be 'SubsiteCount eq 5'
        $result.Expected | Should -Be 5
        $result.Actual | Should -Be 3
        $result.Kind | Should -Be 'Must'
        $result.Status | Should -Be 'FAIL'
    }

    It 'does not fail an informational expectation: it reports INFO' {
        $record = [PSCustomObject]@{ CustomizedPageCount = 0 }

        $unmet = Test-Expectation (Get-Expectation CustomizedPageCount ge 1 -Info) $record
        $met = Test-Expectation (Get-Expectation CustomizedPageCount ge 0 -Info) $record

        $unmet.Status | Should -Be 'INFO'
        $unmet.Kind | Should -Be 'Info'
        $met.Status | Should -Be 'PASS'
    }

    It 'fails a property that is not in the record, and does not mistake it for a zero' {
        $record = [PSCustomObject]@{ SubsiteCount = 0 }

        (Test-Expectation (Get-Expectation Missing eq 0) $record).Status | Should -Be 'FAIL'
        (Test-Expectation (Get-Expectation Missing eq 0) $record).Actual | Should -Be '(not in the record)'
        (Test-Expectation (Get-Expectation Missing eq 0 -Info) $record).Status | Should -Be 'INFO'
    }

    It 'checks that an alert is raised, and skips the check when there is no alerts report' {
        $record = [PSCustomObject]@{ Url = 'x' }
        $alert = Get-Expectation -Alert 'Subsites'

        (Test-Expectation $alert $record @('Subsites', 'LargeLists')).Status | Should -Be 'PASS'
        (Test-Expectation $alert $record @('LargeLists')).Status | Should -Be 'FAIL'
        (Test-Expectation $alert $record @()).Status | Should -Be 'FAIL'
        (Test-Expectation $alert $record $null).Status | Should -Be 'SKIP'
        (Test-Expectation (Get-Expectation -Alert 'Subsites' -Info) $record @('LargeLists')).Status | Should -Be 'INFO'
        (Test-Expectation $alert $record @('Subsites')).Check | Should -Be 'Alert Subsites'
    }
}

Describe 'Test-SPSLabResult' {
    BeforeAll {
        function Write-Json {
            param ([System.String] $Name, $Value, [System.DateTime] $Time = (Get-Date))

            $path = Join-Path -Path $TestDrive -ChildPath $Name
            $folder = Split-Path -Path $path -Parent
            if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -Path $folder -ItemType Directory -Force }
            ConvertTo-Json -InputObject $Value -Depth 6 | Set-Content -Path $path -Encoding UTF8
            (Get-Item -LiteralPath $path).LastWriteTime = $Time
            return $path
        }

        function New-Entry {
            param ([System.String] $Name, [System.String] $Status = 'Created', [System.String] $Detail = '')

            return [PSCustomObject]@{ Name = $Name; Url = "https://lab/sites/spslab-$Name"; Status = $Status; Detail = $Detail }
        }

        function New-Record {
            param ([System.String] $Name, [hashtable] $Value = @{})

            $record = [ordered]@{ Url = "https://lab/sites/spslab-$Name"; AssessmentStatus = 'Complete'; AssessmentWarnings = '' }
            foreach ($key in $Value.Keys) { $record[$key] = $Value[$key] }
            return [PSCustomObject]$record
        }

        $script:Manifest = [PSCustomObject]@{
            ManifestVersion = 1; WebApplicationUrl = 'https://lab'; Prefix = 'spslab'; Owner = 'CONTOSO\jc'
            Scenario        = @(
                New-Entry 'baseline'
                New-Entry 'subsites'
                New-Entry 'infopath'
                New-Entry 'workflow-2010' 'Skipped' 'no 2010 engine'
                New-Entry 'irm' 'Failed' 'boom'
                New-Entry 'alerts' 'NotCreated' 'Not confirmed.'
                New-Entry 'permissions'
            )
        }
        $script:ManifestPath = Write-Json 'lab/lab-manifest.json' $script:Manifest
        $baselineValue = @{ SubsiteCount = 0; MaxSubsiteDepth = 0; SubWebCount = 1; SiteLockState = 'Unlock'; IsLockedSite = $false; InfoPathFormCount = 0; Workflow2010Count = 0; SharePointAlertCount = 0; UsesFullTrustCode = $false; Category = 1 }
        $script:Records = @(
            (New-Record 'baseline' $baselineValue)
            (New-Record 'subsites' @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3); a/b (level 2)' })
            (New-Record 'infopath' @{ InfoPathFormCount = 1; Category = 3 } )
        )
        $script:Alerts = @(
            [PSCustomObject]@{ AlertType = 'Subsites'; Url = 'https://lab/sites/spslab-subsites' }
            [PSCustomObject]@{ AlertType = 'InfoPath'; Url = 'https://lab/sites/spslab-infopath' }
            [PSCustomObject]@{ AlertType = 'Subsites'; Url = 'https://lab/sites/spslab-other' }
        )
        $null = Write-Json 'lab/Reports/SPSSiteInventory-LAB-sites-20261027-100000.json' $script:Records
        $null = Write-Json 'lab/Reports/SPSSiteInventory-LAB-alerts-20261027-100000.json' $script:Alerts
        $script:Result = @(Test-SPSLabResult -ManifestPath $script:ManifestPath -ReportFolder (Join-Path -Path $TestDrive -ChildPath 'lab/Reports'))

        function Get-Result {
            param ([System.String] $Scenario, [System.String] $Check)

            return @($script:Result | Where-Object { $_.Scenario -eq $Scenario -and $_.Check -eq $Check })[0]
        }
    }

    It 'passes what the inventory reports as expected' {
        (Get-Result 'subsites' 'SubsiteCount eq 5').Status | Should -Be 'PASS'
        (Get-Result 'subsites' 'MaxSubsiteDepth eq 3').Status | Should -Be 'PASS'
        (Get-Result 'subsites' 'SubsiteExamples like a/b/c (level 3)*').Status | Should -Be 'PASS'
        (Get-Result 'baseline' 'AssessmentStatus eq Complete').Status | Should -Be 'PASS'
    }

    It 'reads the alerts of the site only, not those of another site' {
        (Get-Result 'subsites' 'Alert Subsites').Status | Should -Be 'PASS'
        (Get-Result 'infopath' 'Alert InfoPath').Status | Should -Be 'PASS'
    }

    It 'does not count an alert that another site raised' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'otheralert'
        $null = Write-Json 'otheralert/Reports/SPSSiteInventory-LAB-sites-1.json' @((New-Record 'subsites' @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3)' }))
        $null = Write-Json 'otheralert/Reports/SPSSiteInventory-LAB-alerts-1.json' @([PSCustomObject]@{ AlertType = 'Subsites'; Url = 'https://lab/sites/spslab-other' })
        $manifestPath = Write-Json 'otheralert/lab-manifest.json' ([PSCustomObject]@{ Scenario = @((New-Entry 'subsites')) })

        $result = @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder (Join-Path -Path $folder -ChildPath 'Reports'))

        @($result | Where-Object { $_.Check -eq 'Alert Subsites' })[0].Status | Should -Be 'FAIL'
    }

    It 'fails what the inventory does not report as expected, with the actual value' {
        $result = Get-Result 'infopath' 'Category eq 4'

        $result.Status | Should -Be 'FAIL'
        $result.Actual | Should -Be 3
        $result.Expected | Should -Be 4
        $result.Scenario | Should -Be 'infopath'
        $result.Url | Should -Be 'https://lab/sites/spslab-infopath'
    }

    It 'skips a scenario that was skipped on the farm, and fails one that could not be built' {
        $skipped = Get-Result 'workflow-2010' 'Scenario built'
        $failed = Get-Result 'irm' 'Scenario built'
        $declined = Get-Result 'alerts' 'Scenario built'

        $skipped.Status | Should -Be 'SKIP'
        $skipped.Actual | Should -Be 'Skipped: no 2010 engine'
        $failed.Status | Should -Be 'FAIL'
        $failed.Actual | Should -Be 'Failed: boom'
        $declined.Status | Should -Be 'SKIP'
        @($script:Result | Where-Object { $_.Scenario -eq 'workflow-2010' }).Count | Should -Be 1
    }

    It 'fails a scenario whose site is not in the inventory' {
        $result = Get-Result 'permissions' 'Site in the inventory'

        $result.Status | Should -Be 'FAIL'
        @($script:Result | Where-Object { $_.Scenario -eq 'permissions' }).Count | Should -Be 1
    }

    It 'lists the assessment of every lab site, and reports a partial one as informational' {
        (Get-Result 'baseline' 'Assessment').Status | Should -Be 'PASS'
        (Get-Result 'baseline' 'Assessment').Kind | Should -Be 'Info'

        $partial = New-Record 'subsites' @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3)'; AssessmentStatus = 'Partial'; AssessmentWarnings = 'Lists could not be read.' }
        $folder = Join-Path -Path $TestDrive -ChildPath 'partial'
        $null = Write-Json 'partial/Reports/SPSSiteInventory-LAB-sites-1.json' @($partial)
        $manifest = [PSCustomObject]@{ Scenario = @((New-Entry 'subsites')) }
        $manifestPath = Write-Json 'partial/lab-manifest.json' $manifest

        $result = @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder (Join-Path -Path $folder -ChildPath 'Reports'))
        $assessment = @($result | Where-Object { $_.Check -eq 'Assessment' })[0]

        $assessment.Status | Should -Be 'INFO'
        $assessment.Actual | Should -Be 'Partial: Lists could not be read.'
    }

    It 'skips the alert checks when there is no alerts report, and still checks the record' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'noalerts'
        $null = Write-Json 'noalerts/Reports/SPSSiteInventory-LAB-sites-1.json' @((New-Record 'subsites' @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3)' }))
        $manifestPath = Write-Json 'noalerts/lab-manifest.json' ([PSCustomObject]@{ Scenario = @((New-Entry 'subsites')) })

        $result = @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder (Join-Path -Path $folder -ChildPath 'Reports'))

        @($result | Where-Object { $_.Check -eq 'Alert Subsites' })[0].Status | Should -Be 'SKIP'
        @($result | Where-Object { $_.Check -eq 'SubsiteCount eq 5' })[0].Status | Should -Be 'PASS'
    }

    It 'reads a report that holds a single record, as written when only one site was scanned' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'single'
        $null = Write-Json 'single/Reports/SPSSiteInventory-LAB-sites-1.json' (New-Record 'subsites' @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3)' })
        $manifestPath = Write-Json 'single/lab-manifest.json' ([PSCustomObject]@{ Scenario = @((New-Entry 'subsites')) })

        $result = @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder (Join-Path -Path $folder -ChildPath 'Reports'))

        @($result | Where-Object { $_.Check -eq 'SubsiteCount eq 5' })[0].Status | Should -Be 'PASS'
    }

    It 'uses the newest sites report of the folder' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'newest'
        $stale = New-Record 'subsites' @{ SubsiteCount = 0; MaxSubsiteDepth = 0; SubWebCount = 1; SubsiteExamples = '' }
        $fresh = New-Record 'subsites' @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3)' }
        $null = Write-Json 'newest/Reports/SPSSiteInventory-LAB-sites-old.json' @($stale) (Get-Date).AddHours(-2)
        $null = Write-Json 'newest/Reports/SPSSiteInventory-LAB-sites-new.json' @($fresh) (Get-Date)
        $manifestPath = Write-Json 'newest/lab-manifest.json' ([PSCustomObject]@{ Scenario = @((New-Entry 'subsites')) })

        $result = @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder (Join-Path -Path $folder -ChildPath 'Reports'))

        @($result | Where-Object { $_.Check -eq 'SubsiteCount eq 5' })[0].Status | Should -Be 'PASS'
    }

    It 'throws, saying what to do, when there is no sites report' {
        $empty = Join-Path -Path $TestDrive -ChildPath 'empty'
        $null = New-Item -Path $empty -ItemType Directory -Force

        { Test-SPSLabResult -ManifestPath $script:ManifestPath -ReportFolder $empty } | Should -Throw '*run the inventory first*'
    }

    It 'checks only the scenarios that are asked for, and fails when none of them is in the manifest' {
        $one = @(Test-SPSLabResult -ManifestPath $script:ManifestPath -ReportFolder (Join-Path -Path $TestDrive -ChildPath 'lab/Reports') -Scenario 'subsites')
        $two = @(Test-SPSLabResult -ManifestPath $script:ManifestPath -ReportFolder (Join-Path -Path $TestDrive -ChildPath 'lab/Reports') -Scenario 'SUBSITES', 'baseline')

        @($one | ForEach-Object { $_.Scenario } | Select-Object -Unique) | Should -Be @('subsites')
        @($one | Where-Object { $_.Status -eq 'FAIL' }) | Should -HaveCount 0
        @($two | ForEach-Object { $_.Scenario } | Select-Object -Unique) | Should -Be @('baseline', 'subsites')
        { Test-SPSLabResult -ManifestPath $script:ManifestPath -ReportFolder (Join-Path -Path $TestDrive -ChildPath 'lab/Reports') -Scenario 'nothing' } | Should -Throw "*None of the scenarios 'nothing' is in the lab manifest*"
    }

    It 'reads the alerts report of the same run as the sites report, never that of another run' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'tworuns'
        $record = New-Record 'subsites' @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3)' }
        # The old run raised the alert. The new run wrote its sites report, then failed before it wrote its alerts report.
        $null = Write-Json 'tworuns/Reports/SPSSiteInventory-LAB-sites-20261027-0900.json' @($record) (Get-Date).AddHours(-2)
        $null = Write-Json 'tworuns/Reports/SPSSiteInventory-LAB-alerts-20261027-0900.json' @([PSCustomObject]@{ AlertType = 'Subsites'; Url = 'https://lab/sites/spslab-subsites' }) (Get-Date).AddHours(-2)
        $null = Write-Json 'tworuns/Reports/SPSSiteInventory-LAB-sites-20261027-1100.json' @($record) (Get-Date)
        $manifestPath = Write-Json 'tworuns/lab-manifest.json' ([PSCustomObject]@{ Scenario = @((New-Entry 'subsites')) })

        $result = @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder (Join-Path -Path $folder -ChildPath 'Reports'))

        @($result | Where-Object { $_.Check -eq 'Alert Subsites' })[0].Status | Should -Be 'SKIP'
    }

    It 'takes the alerts report of the sites report that it uses, when both runs wrote one' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'bothruns'
        $record = New-Record 'subsites' @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3)' }
        $null = Write-Json 'bothruns/Reports/SPSSiteInventory-LAB-sites-20261027-0900.json' @($record) (Get-Date).AddHours(-2)
        $null = Write-Json 'bothruns/Reports/SPSSiteInventory-LAB-alerts-20261027-0900.json' @([PSCustomObject]@{ AlertType = 'Subsites'; Url = 'https://lab/sites/spslab-subsites' }) (Get-Date).AddHours(-2)
        $null = Write-Json 'bothruns/Reports/SPSSiteInventory-LAB-sites-20261027-1100.json' @($record) (Get-Date)
        $null = Write-Json 'bothruns/Reports/SPSSiteInventory-LAB-alerts-20261027-1100.json' @([PSCustomObject]@{ AlertType = 'LargeLists'; Url = 'https://lab/sites/spslab-subsites' }) (Get-Date)
        $manifestPath = Write-Json 'bothruns/lab-manifest.json' ([PSCustomObject]@{ Scenario = @((New-Entry 'subsites')) })

        $result = @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder (Join-Path -Path $folder -ChildPath 'Reports'))

        @($result | Where-Object { $_.Check -eq 'Alert Subsites' })[0].Status | Should -Be 'FAIL'
    }

    It 'fails the alert checks, instead of skipping them, when the alerts report exists and is empty' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'emptyalerts'
        $null = Write-Json 'emptyalerts/Reports/SPSSiteInventory-LAB-sites-20261027-1000.json' @((New-Record 'subsites' @{ SubsiteCount = 5; MaxSubsiteDepth = 3; SubWebCount = 6; SubsiteExamples = 'a/b/c (level 3)' }))
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'Reports/SPSSiteInventory-LAB-alerts-20261027-1000.json') -Value '[]' -Encoding UTF8
        $manifestPath = Write-Json 'emptyalerts/lab-manifest.json' ([PSCustomObject]@{ Scenario = @((New-Entry 'subsites')) })

        $result = @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder (Join-Path -Path $folder -ChildPath 'Reports'))

        $alert = @($result | Where-Object { $_.Check -eq 'Alert Subsites' })[0]
        $alert.Status | Should -Be 'FAIL'
        $alert.Actual | Should -Be 'not raised'
    }

    It 'says what to do when there is no manifest' {
        { Test-SPSLabResult -ManifestPath (Join-Path -Path $TestDrive -ChildPath 'no-manifest.json') -ReportFolder $TestDrive } | Should -Throw '*run the Provision step first*'
    }

    It 'ignores a scenario that the lab no longer knows' {
        $manifestPath = Write-Json 'unknown/lab-manifest.json' ([PSCustomObject]@{ Scenario = @((New-Entry 'gone')) })

        @(Test-SPSLabResult -ManifestPath $manifestPath -ReportFolder (Join-Path -Path $TestDrive -ChildPath 'lab/Reports')) | Should -HaveCount 0
    }
}

Describe 'Write-SPSLabReport' {
    BeforeAll {
        $script:Items = @(
            [PSCustomObject]@{ Scenario = 'subsites'; Url = 'https://lab/sites/spslab-subsites'; Check = 'SubsiteCount eq 5'; Expected = 5; Actual = 5; Kind = 'Must'; Status = 'PASS' }
            [PSCustomObject]@{ Scenario = 'subsites'; Url = 'https://lab/sites/spslab-subsites'; Check = 'MaxSubsiteDepth eq 3'; Expected = 3; Actual = 2; Kind = 'Must'; Status = 'FAIL' }
            [PSCustomObject]@{ Scenario = 'irm'; Url = 'https://lab/sites/spslab-irm'; Check = 'IrmEnabledListCount ge 1'; Expected = 1; Actual = 0; Kind = 'Info'; Status = 'INFO' }
            [PSCustomObject]@{ Scenario = 'irm'; Url = 'https://lab/sites/spslab-irm'; Check = 'Scenario built'; Expected = 'created'; Actual = 'Skipped: no IRM'; Kind = 'Must'; Status = 'SKIP' }
        )
        $output = @(Write-SPSLabReport -Result $script:Items 6>&1)
        $script:Lines = @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { [PSCustomObject]@{ Text = [System.String]$_.MessageData.Message; Color = [System.String]$_.MessageData.ForegroundColor } })
        $script:Count = @($output | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })[0]
    }

    It 'shows each status with its own mark and color, and the actual value of what is not a pass' {
        ($script:Lines | Where-Object { $_.Text -eq '[PASS]  SubsiteCount eq 5' }).Color | Should -Be 'Green'
        ($script:Lines | Where-Object { $_.Text -eq '[FAIL]  MaxSubsiteDepth eq 3 - actual: 2' }).Color | Should -Be 'Red'
        ($script:Lines | Where-Object { $_.Text -eq '[INFO]  IrmEnabledListCount ge 1 - actual: 0' }).Color | Should -Be 'Yellow'
        ($script:Lines | Where-Object { $_.Text -eq '[SKIP]  Scenario built - actual: Skipped: no IRM' }).Color | Should -Be 'DarkGray'
    }

    It 'groups the checks by scenario, with the URL of the site' {
        $headings = @($script:Lines | Where-Object { $_.Text -like '== *' } | ForEach-Object { $_.Text })

        $headings | Should -Be @('== subsites (https://lab/sites/spslab-subsites) ==', '== irm (https://lab/sites/spslab-irm) ==')
    }

    It 'returns the counts and a summary line' {
        $script:Count.Pass | Should -Be 1
        $script:Count.Fail | Should -Be 1
        $script:Count.Info | Should -Be 1
        $script:Count.Skip | Should -Be 1
        ($script:Lines | Where-Object { $_.Text -like 'Summary:*' }).Text | Should -Be 'Summary: 1 passed, 1 failed, 1 informational, 1 skipped'
    }
}
