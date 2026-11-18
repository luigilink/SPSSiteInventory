# The wiki and the example settings document Scoring.Caps: these tests keep the documented behavior true.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:RepoRoot = $repoRoot
    $script:Wiki = Get-Content -Path (Join-Path $repoRoot 'wiki/Configuration.md') -Raw
    $script:Usage = Get-Content -Path (Join-Path $repoRoot 'wiki/Usage.md') -Raw
    $script:Section = @(($script:Wiki -split '(?m)^### ') | Where-Object { $_ -like 'Caps*' })[0]
}

Describe 'The wiki page on Scoring.Caps' {
    It 'has a Caps section, linked from the Weights section and from the page that describes the report' {
        $script:Section | Should -Not -BeNullOrEmpty
        $script:Wiki | Should -Match '\[`Caps`\]\(#caps\)'
        $script:Usage | Should -Match '\[`Caps`\]\(Configuration#caps\)'
    }

    It 'gives an example that the settings loader accepts, and that does what the text says' {
        $code = [regex]::Match($script:Section, '(?s)```powershell\r?\n(.+?)```').Groups[1].Value
        $path = Join-Path $TestDrive 'wiki-caps.psd1'
        "@{`n$code`n}" | Set-Content -Path $path -Encoding UTF8

        $settings = Get-SPSInventorySetting -Path $path

        $settings.Scoring.Caps.EventReceivers | Should -Be 4
        $alone = Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121 } -Scoring $settings.Scoring
        $alone.CategoryName | Should -Be 'Moderate'
        $alone.Reasons | Should -Be @('EventReceivers=121 (+4, capped from 181.5)')
        $script:Section | Should -Match ([regex]::Escape('`EventReceivers=121 (+4, capped from 181.5)`'))
        $script:Section | Should -Match 'Moderate at most \(4, below `Complex`, 6\)'
        $script:Section | Should -Match 'other signals worth 2 more'
        # The text says 2 more: 1.8 is not enough with the cap of 4, and 2.1 is.
        (Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121; Workflow2010Count = 0.6 } -Scoring $settings.Scoring).CategoryName | Should -Be 'Moderate'
        (Measure-SPSSiteComplexity -Signals @{ EventReceivers = 121; Workflow2010Count = 0.7 } -Scoring $settings.Scoring).CategoryName | Should -Be 'Complex'
    }

    It 'says that there is no cap by default, and the two example files ship without one' {
        $script:Section | Should -Match '\*\*There is no cap by default\*\*'
        foreach ($file in 'inventory-settings.example.psd1', 'inventory-settings.onprem.example.psd1') {
            $settings = Get-SPSInventorySetting -Path (Join-Path $script:RepoRoot "src/config/$file")

            $settings.Scoring.ContainsKey('Caps') | Should -BeFalse -Because $file
        }
    }

    It 'has the Caps block in comments in <File>, and the block is valid once it is uncommented' -ForEach @(
        @{ File = 'inventory-settings.example.psd1' }
        @{ File = 'inventory-settings.onprem.example.psd1' }
    ) {
        $text = Get-Content -Path (Join-Path $script:RepoRoot "src/config/$File") -Raw
        $uncommented = [regex]::Replace($text, '(?m)^( +)# Caps = @\{\r?\n\1#\s+EventReceivers = 4\r?\n\1# \}', '${1}Caps = @{ EventReceivers = 4 }')
        $path = Join-Path $TestDrive $File
        Set-Content -Path $path -Value $uncommented -Encoding UTF8

        $uncommented | Should -Not -BeExactly $text
        $settings = Get-SPSInventorySetting -Path $path
        $settings.Scoring.Caps.EventReceivers | Should -Be 4
    }
}
