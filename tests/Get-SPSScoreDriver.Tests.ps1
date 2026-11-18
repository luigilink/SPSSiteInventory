# Get-SPSScoreDriver tells which signals make the score of an inventory, from the Reasons of its records. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function New-Site {
        param ([string]$Name, [object]$Reasons = '', [double]$Score = 0, [int]$Category = 3, [string]$CategoryName = 'Complex', [string]$Status = 'Complete', [string]$Scope = 'SiteCollection')
        [PSCustomObject]@{
            InventoryScope = $Scope; Url = "https://intranet/sites/$Name"; AssessmentStatus = $Status
            Category = $Category; CategoryName = $CategoryName; Score = $Score; Reasons = $Reasons
        }
    }

    function Get-Driver {
        param ([object[]]$Record)
        & $script:Module { param ($Rows) Get-SPSScoreDriver -InputObject $Rows } $Record
    }
}

Describe 'Get-SPSScoreDriver by signal' {
    It 'adds up what each signal contributed, with its share, the site collections that have it and those where it weighs most, the largest first' {
        $result = Get-Driver -Record @(
            (New-Site -Name 'a' -Score 153 -Reasons 'EventReceivers=100 (+150); Workflow2010Count=1 (+3)')
            (New-Site -Name 'b' -Score 15 -Reasons 'EventReceivers=10 (+15)')
            (New-Site -Name 'c' -Score 6.1 -Reasons 'Workflow2010Count=2 (+6); CustomPermissionLevelCount=1 (+0.1)')
        )

        $result.Assessed | Should -Be 3
        $result.Scored | Should -Be 3
        $result.TotalScore | Should -Be 174.1
        @($result.Signal | ForEach-Object { $_.Name }) | Should -Be @('EventReceivers', 'Workflow2010Count', 'CustomPermissionLevelCount')
        $receivers, $workflow, $permission = @($result.Signal)
        $receivers.SiteCount | Should -Be 2
        $receivers.Total | Should -Be 165
        $receivers.Share | Should -BeGreaterThan 0.9477
        $receivers.Share | Should -BeLessThan 0.9478
        $receivers.TopSiteCount | Should -Be 2
        $workflow.SiteCount | Should -Be 2
        $workflow.Total | Should -Be 9
        $workflow.TopSiteCount | Should -Be 1
        $permission.SiteCount | Should -Be 1
        $permission.TopSiteCount | Should -Be 0
        (@($result.Signal | ForEach-Object { $_.Share }) | Measure-Object -Sum).Sum | Should -BeGreaterThan 0.9999
    }

    It 'gives a tie between two signals of a site collection to the first name, whatever the order of the reasons' {
        # Six names, because the order of a hashtable changes from one process to the next: with two, a missing tie-break gives the right answer one run in two.
        $result = Get-Driver -Record @((New-Site -Name 'a' -Score 12 -Reasons 'Fox=1 (+2); Echo=1 (+2); Delta=1 (+2); Charlie=1 (+2); Bravo=1 (+2); Alpha=1 (+2)'))

        @($result.Signal | ForEach-Object { $_.Name }) | Should -Be @('Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Fox')
        @($result.Signal | Where-Object { $_.TopSiteCount -eq 1 } | ForEach-Object { $_.Name }) | Should -Be @('Alpha')
        @($result.Category[0].Signal | ForEach-Object { $_.Name }) | Should -Be @('Alpha', 'Bravo', 'Charlie')
    }

    It 'leaves out a failed assessment, a web application row and a record without a category, and the text of the reasons that is not a contribution' {
        $result = Get-Driver -Record @(
            (New-Site -Name 'ok' -Score 5 -Reasons 'Signal=1 (+5); Site inventory partial: List=Docs (+ cannot be read); Other=1 (+7) was left out; the count is a lower bound')
            (New-Site -Name 'failed' -Score 0 -Category 0 -Status 'Failed' -Reasons 'Signal=1 (+500)')
            (New-Site -Name 'failed-with-category' -Score 9 -Status 'Failed' -Reasons 'Signal=1 (+900)')
            (New-Site -Name 'app' -Scope 'WebApplication' -Score 7 -Reasons 'Signal=1 (+700)')
            (New-Site -Name 'none' -Category 0 -Reasons 'Signal=1 (+90)')
        )

        $result.Assessed | Should -Be 1
        $result.Scored | Should -Be 1
        $result.TotalScore | Should -Be 5
        @($result.Signal) | Should -HaveCount 1
        $result.Signal[0].Name | Should -BeExactly 'Signal'
        $result.Signal[0].Total | Should -Be 5
    }

    It 'counts a site collection that has no weighted signal as assessed and not as scored' {
        $result = Get-Driver -Record @((New-Site -Name 'plain' -Score 0 -Category 1 -CategoryName 'Simple' -Reasons ''), (New-Site -Name 'raising' -Score 2 -Reasons 'Signal=2 (+2)'))

        $result.Assessed | Should -Be 2
        $result.Scored | Should -Be 1
    }

    It 'does not count a contribution that the reasons rounded to zero as a signal, and counts the site collection as unresolved' {
        # Four pages at 0.001 and 0.2 GB at 0.02 make a score of 0.01, and both contributions are written as (+0).
        $result = Get-Driver -Record @(
            (New-Site -Name 'tiny' -Score 0.01 -Category 1 -CategoryName 'Simple' -Reasons 'PageCount=4 (+0); SizeGB=0.2 (+0)')
            (New-Site -Name 'raising' -Score 2 -Reasons 'Signal=2 (+2)')
        )

        $result.Assessed | Should -Be 2
        $result.Scored | Should -Be 1
        $result.Unresolved | Should -Be 1
        $result.TotalScore | Should -Be 2
        @($result.Signal | ForEach-Object { $_.Name }) | Should -Be @('Signal')
        $result.Signal[0].SiteCount | Should -Be 1
        $result.Signal[0].TopSiteCount | Should -Be 1
        $result.Category[0].Signal | Should -HaveCount 0
        $result.Category[0].SiteCount | Should -Be 1
    }

    It 'keeps the contributions that can be read in a site collection that also has rounded ones' {
        $result = Get-Driver -Record @((New-Site -Name 'mixed' -Score 3.01 -Reasons 'Signal=3 (+3); PageCount=4 (+0)'))

        $result.Scored | Should -Be 1
        $result.Unresolved | Should -Be 0
        @($result.Signal | ForEach-Object { $_.Name }) | Should -Be @('Signal')
    }

    It 'does not count a site collection without a score as unresolved' {
        $result = Get-Driver -Record @((New-Site -Name 'plain' -Score 0 -Category 1 -CategoryName 'Simple' -Reasons ''))

        $result.Unresolved | Should -Be 0
    }

    It 'reads the numbers with the invariant culture, as the reasons are written, whatever the culture of the server' {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')

            $result = Get-Driver -Record @((New-Site -Name 'a' -Score 181.5 -Reasons 'EventReceivers=121 (+181.5)'))

            $result.Signal[0].Total | Should -Be 181.5
            $result.TotalScore | Should -Be 181.5
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }
    }

    It 'reads the reasons of a record that holds them as a list, and a record that has none' {
        $result = Get-Driver -Record @(
            (New-Site -Name 'list' -Score 5 -Reasons @('A=1 (+3)', 'B=1 (+2)'))
            [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/old'; AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Score = 0 }
        )

        $result.Assessed | Should -Be 2
        $result.Scored | Should -Be 1
        $result.TotalScore | Should -Be 5
    }

    It 'gives nothing for an empty inventory' {
        $result = Get-Driver -Record @()

        $result.Assessed | Should -Be 0
        $result.Scored | Should -Be 0
        $result.TotalScore | Should -Be 0
        @($result.Signal) | Should -HaveCount 0
        @($result.Category) | Should -HaveCount 0
    }
}

Describe 'Get-SPSScoreDriver by category' {
    It 'gives each category with its site collections, its lowest and highest score, the three signals that weigh most and its blocking signals' {
        $result = Get-Driver -Record @(
            (New-Site -Name 'simple' -Category 1 -CategoryName 'Simple' -Score 0.5 -Reasons 'CustomPermissionLevelCount=5 (+0.5)')
            (New-Site -Name 'complex-a' -Score 100 -Reasons 'EventReceivers=60 (+90); Workflow2010Count=2 (+6); ScriptWebPartCount=2 (+3); CustomMasterPage=1 (+1)')
            (New-Site -Name 'complex-b' -Score 20 -Reasons 'EventReceivers=10 (+15); Workflow2010Count=1 (+3); ScriptWebPartCount=1 (+2)')
            (New-Site -Name 'blocked-a' -Category 4 -CategoryName 'Blocking' -Score 8 -Reasons 'HasFbaZone=1 (+8); blocking: HasFbaZone; blocking: InfoPathFormCount')
            (New-Site -Name 'blocked-b' -Category 4 -CategoryName 'Blocking' -Score 40 -Reasons 'EventReceivers=20 (+30); HasFbaZone=1 (+10); blocking: HasFbaZone')
        )

        @($result.Category | ForEach-Object { $_.Category }) | Should -Be @(1, 3, 4)
        $simple, $complex, $blocking = @($result.Category)
        $simple.CategoryName | Should -BeExactly 'Simple'
        $simple.SiteCount | Should -Be 1
        $simple.MinScore | Should -Be 0.5
        $simple.MaxScore | Should -Be 0.5
        $complex.SiteCount | Should -Be 2
        $complex.MinScore | Should -Be 20
        $complex.MaxScore | Should -Be 100
        @($complex.Signal) | Should -HaveCount 3
        @($complex.Signal | ForEach-Object { $_.Name }) | Should -Be @('EventReceivers', 'Workflow2010Count', 'ScriptWebPartCount')
        # 105 of the 120 that the four signals added in the two site collections.
        $complex.Signal[0].Share | Should -Be 0.875
        $complex.Signal[1].Share | Should -Be 0.075
        $complex.Blocking | Should -HaveCount 0
        $blocking.SiteCount | Should -Be 2
        $blocking.MinScore | Should -Be 8
        $blocking.MaxScore | Should -Be 40
        @($blocking.Blocking | ForEach-Object { '{0}={1}' -f $_.Name, $_.SiteCount }) | Should -Be @('HasFbaZone=2', 'InfoPathFormCount=1')
    }

    It 'counts a blocking signal once for a site collection, and gives no signal to a category that has no weighted signal' {
        $result = Get-Driver -Record @((New-Site -Name 'blocked' -Category 4 -CategoryName 'Blocking' -Score 0 -Reasons 'blocking: HasFbaZone; blocking: HasFbaZone'))

        $blocking = $result.Category[0]
        @($blocking.Signal) | Should -HaveCount 0
        @($blocking.Blocking) | Should -HaveCount 1
        $blocking.Blocking[0].SiteCount | Should -Be 1
    }
}

Describe 'Get-SPSScoreDriver and Measure-SPSSiteComplexity' {
    It 'reads back what Measure-SPSSiteComplexity wrote in the reasons: the same signals, and the same total as the score' {
        $scoring = @{ Weights = @{ EventReceivers = 1.5; Workflow2010Count = 3.0; CustomPermissionLevelCount = 0.1; HasFbaZone = 0 }; Thresholds = @{ Moderate = 1; Complex = 6 }; BlockingSignals = @('HasFbaZone') }
        $signals = @{ EventReceivers = 121; Workflow2010Count = 2; CustomPermissionLevelCount = 3; HasFbaZone = $true }
        $measured = Measure-SPSSiteComplexity -Signals $signals -Scoring $scoring
        $record = [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/a'; AssessmentStatus = 'Complete'; Category = $measured.Category; CategoryName = $measured.CategoryName; Score = $measured.Score; Reasons = ($measured.Reasons -join '; ') }

        $result = Get-Driver -Record @($record)

        @($result.Signal | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @('CustomPermissionLevelCount', 'EventReceivers', 'Workflow2010Count')
        [System.Math]::Round($result.TotalScore, 2) | Should -Be $measured.Score
        $result.Signal[0].Name | Should -BeExactly 'EventReceivers'
        $result.Signal[0].Total | Should -Be 181.5
        $result.Category[0].Category | Should -Be 4
        $result.Category[0].Blocking[0].Name | Should -BeExactly 'HasFbaZone'
    }
}

Describe 'Get-SPSScoreDriver and the caps of the scoring' {
    It 'reads a contribution that a cap cut at the capped amount, and counts the site collections where a cap cut' {
        $result = Get-Driver -Record @(
            (New-Site -Name 'a' -Score 7 -Reasons 'EventReceivers=121 (+4, capped from 181.5); Workflow2010Count=1 (+3)')
            (New-Site -Name 'b' -Score 4 -Reasons 'EventReceivers=300 (+4, capped from 450)')
            (New-Site -Name 'c' -Score 3 -Reasons 'EventReceivers=2 (+3)')
        )

        $receivers = @($result.Signal | Where-Object { $_.Name -eq 'EventReceivers' })[0]
        $workflow = @($result.Signal | Where-Object { $_.Name -eq 'Workflow2010Count' })[0]
        $result.TotalScore | Should -Be 14
        $receivers.Total | Should -Be 11
        $receivers.SiteCount | Should -Be 3
        $receivers.TopSiteCount | Should -Be 3
        $receivers.CappedSiteCount | Should -Be 2
        $receivers.Share | Should -BeGreaterThan 0.7857
        $receivers.Share | Should -BeLessThan 0.7858
        $workflow.Total | Should -Be 3
        $workflow.CappedSiteCount | Should -Be 0
    }

    It 'counts no site collection as capped when no reason says so' {
        $result = Get-Driver -Record @((New-Site -Name 'a' -Score 5 -Reasons 'Signal=1 (+5)'), (New-Site -Name 'b' -Score 2 -Reasons 'Other=2 (+2)'))

        foreach ($signal in @($result.Signal)) {
            $signal.CappedSiteCount | Should -Be 0
        }
    }

    It 'does not read as a contribution a text that only looks like one with a cap' {
        $result = Get-Driver -Record @((New-Site -Name 'a' -Score 5 -Reasons 'Signal=1 (+5); Other=1 (+7, capped from 9) was left out; Third=1 (+2, capped)'))

        @($result.Signal) | Should -HaveCount 1
        $result.Signal[0].Name | Should -BeExactly 'Signal'
        $result.Signal[0].CappedSiteCount | Should -Be 0
    }

    It 'reads back what Measure-SPSSiteComplexity wrote for a capped signal' {
        $scoring = @{ Weights = @{ EventReceivers = 1.5; Workflow2010Count = 3.0 }; Caps = @{ EventReceivers = 4 }; Thresholds = @{ Moderate = 1; Complex = 6 }; BlockingSignals = @() }
        $measured = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121; Workflow2010Count = 1 } -Scoring $scoring
        $record = [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/a'; AssessmentStatus = 'Complete'; Category = $measured.Category; CategoryName = $measured.CategoryName; Score = $measured.Score; Reasons = ($measured.Reasons -join '; ') }

        $result = Get-Driver -Record @($record)

        $measured.Score | Should -Be 7
        $result.TotalScore | Should -Be 7
        $receivers = @($result.Signal | Where-Object { $_.Name -eq 'EventReceivers' })[0]
        $receivers.Total | Should -Be 4
        $receivers.CappedSiteCount | Should -Be 1
    }
}

Describe 'Get-SPSScoreDriver and the contributions below 0' {
    It 'gives a share that is a part of the sum of the sizes of the contributions, whatever the sign of the score, and orders the signals by size' {
        $result = Get-Driver -Record @((New-Site -Name 'a' -Score -6 -Reasons 'Cap=1 (+4); Discount=1 (+-10)'))

        $result.Scored | Should -Be 1
        $result.TotalScore | Should -Be -6
        @($result.Signal | ForEach-Object { $_.Name }) | Should -Be @('Discount', 'Cap')
        $discount, $cap = @($result.Signal)
        $discount.Total | Should -Be -10
        $discount.Share | Should -BeGreaterThan -0.7143
        $discount.Share | Should -BeLessThan -0.7142
        $discount.TopSiteCount | Should -Be 1
        $cap.Share | Should -BeGreaterThan 0.2857
        $cap.Share | Should -BeLessThan 0.2858
        $cap.TopSiteCount | Should -Be 0
        ($discount.Share + $cap.Share) | Should -BeGreaterThan -0.4287
        ($discount.Share + $cap.Share) | Should -BeLessThan -0.4285
    }

    It 'gives a share to each signal when the contributions cancel each other out' {
        $result = Get-Driver -Record @((New-Site -Name 'a' -Score 0 -Reasons 'Up=1 (+5); Down=1 (+-5)'))

        $result.Scored | Should -Be 1
        $result.Unresolved | Should -Be 0
        $result.TotalScore | Should -Be 0
        @($result.Signal | ForEach-Object { $_.Name }) | Should -Be @('Down', 'Up')
        $result.Signal[0].Share | Should -Be -0.5
        $result.Signal[1].Share | Should -Be 0.5
        @($result.Category[0].Signal | ForEach-Object { $_.Name }) | Should -Be @('Down', 'Up')
        $result.Category[0].Signal[0].Share | Should -Be -0.5
        $result.Category[0].Signal[1].Share | Should -Be 0.5
    }

    It 'gives shares to the signals of a category whose contributions add up to less than 0, even when the inventory adds up to more' {
        $result = Get-Driver -Record @(
            (New-Site -Name 'big' -Score 100 -Reasons 'Big=1 (+100)')
            (New-Site -Name 'discounted' -Category 1 -CategoryName 'Simple' -Score -6 -Reasons 'Cap=1 (+4); Discount=1 (+-10)')
        )

        $simple = @($result.Category | Where-Object { $_.Category -eq 1 })[0]
        @($simple.Signal | ForEach-Object { $_.Name }) | Should -Be @('Discount', 'Cap')
        $simple.Signal[0].Share | Should -BeGreaterThan -0.7143
        $simple.Signal[0].Share | Should -BeLessThan -0.7142
        $simple.Signal[1].Share | Should -BeGreaterThan 0.2857
        $simple.Signal[1].Share | Should -BeLessThan 0.2858
        $result.TotalScore | Should -Be 94
    }

    It 'counts a site collection with a score below 0 and no signal that can be read as unresolved, and one with a score of 0 as nothing to explain' {
        $result = Get-Driver -Record @(
            (New-Site -Name 'negative' -Score -0.01 -Reasons 'A=1 (+-0); B=1 (+0)')
            (New-Site -Name 'positive' -Score 0.01 -Reasons 'A=1 (+0); B=1 (+0)')
            (New-Site -Name 'zero' -Score 0 -Reasons 'A=1 (+0)')
        )

        $result.Assessed | Should -Be 3
        $result.Scored | Should -Be 0
        $result.Unresolved | Should -Be 2
        @($result.Signal) | Should -HaveCount 0
    }

    It 'tells the top signal of a site collection by size, and gives a tie to the first name' {
        $result = Get-Driver -Record @(
            (New-Site -Name 'a' -Score -3 -Reasons 'Cap=1 (+2); Discount=1 (+-5)')
            (New-Site -Name 'b' -Score 0 -Reasons 'Zulu=1 (+3); Alpha=1 (+-3)')
        )

        @($result.Signal | Where-Object { $_.TopSiteCount -gt 0 } | ForEach-Object { '{0}={1}' -f $_.Name, $_.TopSiteCount } | Sort-Object) | Should -Be @('Alpha=1', 'Discount=1')
    }
}
