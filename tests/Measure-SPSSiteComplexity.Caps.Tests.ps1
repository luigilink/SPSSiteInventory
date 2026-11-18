# Scoring.Caps limits what one signal can add to the score of a site collection. No farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-Scoring {
        param ([object]$Caps)
        $scoring = @{
            Weights = @{ EventReceivers = 1.5; Workflow2010Count = 3.0; CustomMasterPage = 2.0; InfoPathFormCount = 3.0; Discount = -2.0 }
            Thresholds = @{ Moderate = 1.0; Complex = 6.0 }
            BlockingSignals = @('InfoPathFormCount')
        }
        if ($PSBoundParameters.ContainsKey('Caps')) {
            $scoring['Caps'] = $Caps
        }
        $scoring
    }
}

Describe 'Measure-SPSSiteComplexity with Scoring.Caps' {
    It 'changes nothing without a cap: no key, a null Caps and an empty Caps give the same result' {
        $signals = @{ EventReceivers = 121; Workflow2010Count = 1; CustomMasterPage = 1 }

        $without = Measure-SPSSiteComplexity -Signals $signals -Scoring (New-Scoring)
        $withNull = Measure-SPSSiteComplexity -Signals $signals -Scoring (New-Scoring -Caps $null)
        $withEmpty = Measure-SPSSiteComplexity -Signals $signals -Scoring (New-Scoring -Caps @{})

        $without.Score | Should -Be 186.5
        $without.Category | Should -Be 3
        $without.Reasons | Should -Contain 'EventReceivers=121 (+181.5)'
        ($without.Reasons -join ';') | Should -Not -Match 'capped'
        foreach ($other in $withNull, $withEmpty) {
            $other.Score | Should -Be $without.Score
            $other.Category | Should -Be $without.Category
            @($other.Reasons | Sort-Object) | Should -Be @($without.Reasons | Sort-Object)
        }
    }

    It 'cuts what a signal adds to its cap, says so in the reason, and scores the capped value' {
        $result = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121 } -Scoring (New-Scoring -Caps @{ EventReceivers = 4 })

        $result.Score | Should -Be 4
        $result.Reasons | Should -Be @('EventReceivers=121 (+4, capped from 181.5)')
    }

    It 'keeps the site collection out of the category that the signal alone made, when the cap is below the threshold' {
        $uncapped = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121 } -Scoring (New-Scoring)
        $capped = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121 } -Scoring (New-Scoring -Caps @{ EventReceivers = 4 })

        $uncapped.Category | Should -Be 3
        $capped.Category | Should -Be 2
        $capped.CategoryName | Should -Be 'Moderate'
    }

    It 'still makes the site collection Complex when other signals add what the cap leaves out' {
        $result = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121; Workflow2010Count = 1 } -Scoring (New-Scoring -Caps @{ EventReceivers = 4 })

        $result.Score | Should -Be 7
        $result.Category | Should -Be 3
    }

    It 'does not change the category when the cap is at the threshold of the category: the signal alone still makes it' {
        $result = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121 } -Scoring (New-Scoring -Caps @{ EventReceivers = 6 })

        $result.Score | Should -Be 6
        $result.Category | Should -Be 3
        $result.Reasons | Should -Be @('EventReceivers=121 (+6, capped from 181.5)')
    }

    It 'leaves a signal under its cap alone, and one that is exactly at it' {
        $under = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 2 } -Scoring (New-Scoring -Caps @{ EventReceivers = 4 })
        $exact = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 4 } -Scoring (New-Scoring -Caps @{ EventReceivers = 6 })

        $under.Reasons | Should -Be @('EventReceivers=2 (+3)')
        $under.Score | Should -Be 3
        $exact.Reasons | Should -Be @('EventReceivers=4 (+6)')
        $exact.Score | Should -Be 6
    }

    It 'caps each signal on its own, and adds up the others as they are' {
        $result = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121; Workflow2010Count = 10; CustomMasterPage = 1 } -Scoring (New-Scoring -Caps @{ EventReceivers = 4; Workflow2010Count = 5 })

        $result.Score | Should -Be 11
        $result.Reasons | Should -Contain 'EventReceivers=121 (+4, capped from 181.5)'
        $result.Reasons | Should -Contain 'Workflow2010Count=10 (+5, capped from 30)'
        $result.Reasons | Should -Contain 'CustomMasterPage=1 (+2)'
        $result.Reasons.Count | Should -Be 3
    }

    It 'says nothing of a cap on a signal that the site collection does not have' {
        $result = Measure-SPSSiteComplexity -Signals @{ Workflow2010Count = 1 } -Scoring (New-Scoring -Caps @{ EventReceivers = 4 })

        $result.Reasons | Should -Be @('Workflow2010Count=1 (+3)')
        $result.Score | Should -Be 3
    }

    It 'leaves the blocking signals alone: a capped signal that blocks still blocks' {
        $result = Measure-SPSSiteComplexity -Signals @{ InfoPathFormCount = 5 } -Scoring (New-Scoring -Caps @{ InfoPathFormCount = 1 })

        $result.Category | Should -Be 4
        $result.Score | Should -Be 1
        $result.Reasons | Should -Contain 'InfoPathFormCount=5 (+1, capped from 15)'
        $result.Reasons | Should -Contain 'blocking: InfoPathFormCount'
    }

    It 'does not cap a negative contribution' {
        $result = Measure-SPSSiteComplexity -Signals @{ Discount = 5; Workflow2010Count = 4 } -Scoring (New-Scoring -Caps @{ Discount = 3 })

        $result.Reasons | Should -Contain 'Discount=5 (+-10)'
        $result.Score | Should -Be 2
    }

    It 'reads the name of a cap without regard to case' {
        $result = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121 } -Scoring (New-Scoring -Caps @{ eventreceivers = 4 })

        $result.Reasons | Should -Be @('EventReceivers=121 (+4, capped from 181.5)')
    }

    It 'rounds the amounts of the reason to two decimals, and the score once, from the unrounded caps' {
        $result = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121; Workflow2010Count = 100 } -Scoring (New-Scoring -Caps @{ EventReceivers = 1.004; Workflow2010Count = 1.004 })

        $result.Reasons | Should -Contain 'EventReceivers=121 (+1, capped from 181.5)'
        $result.Reasons | Should -Contain 'Workflow2010Count=100 (+1, capped from 300)'
        $result.Score | Should -Be 2.01
    }

    It 'writes the capped amounts the same way in <Culture>' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
    ) {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
            $result = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121 } -Scoring (New-Scoring -Caps @{ EventReceivers = 4.5 })
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }

        $result.Reasons | Should -Be @('EventReceivers=121 (+4.5, capped from 181.5)')
        $result.Score | Should -Be 4.5
    }

    It 'refuses a cap that is not valid, as the settings loader does' {
        { Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121 } -Scoring (New-Scoring -Caps @{ EventReceivers = 0 }) } | Should -Throw -ExpectedMessage '*Scoring.Caps.EventReceivers must be a number greater than 0*'
        { Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121 } -Scoring (New-Scoring -Caps @{ EventReceiver = 4 }) } | Should -Throw -ExpectedMessage '*Scoring.Caps.EventReceiver is not a signal of Scoring.Weights*'
    }
}
