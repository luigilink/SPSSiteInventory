# The orchestrator reads SharePoint, so it cannot run here: these tests read its code, and check that the folder of the reports
# is resolved (the Reports folder next to the script when OutputFolder is empty) and created before the scan, and that the
# exports write there. The two example files leave OutputFolder empty.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:Path = Join-Path $repoRoot 'src/Invoke-SPSSiteInventory.ps1'
    $script:Text = Get-Content -LiteralPath $script:Path -Raw
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$null)
    $script:Commands = @($script:Ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    $script:OnlineExample = Join-Path $repoRoot 'src/config/inventory-settings.example.psd1'
    $script:OnPremExample = Join-Path $repoRoot 'src/config/inventory-settings.onprem.example.psd1'

    function Get-CommandText {
        param ([string]$Name)
        @($script:Commands | Where-Object { $_.GetCommandName() -eq $Name })
    }
}

Describe 'Invoke-SPSSiteInventory.ps1 and the folder of the reports' {
    It 'is valid PowerShell' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It 'resolves the folder with the OutputFolder of the settings and the folder of the script, and creates it' {
        $call = @(Get-CommandText -Name 'Resolve-SPSOutputFolder')

        $call | Should -HaveCount 1
        $call[0].Extent.Text | Should -Match '-OutputFolder \$Folder'
        $call[0].Extent.Text | Should -Match '-ScriptRoot \$Root'
        $call[0].Extent.Text | Should -Match '-Create'
        $script:Text | Should -Match "\} \`$settings\['OutputFolder'\] \`$PSScriptRoot"
    }

    It 'creates the folder before the SharePoint commands are loaded and before the scan, so that a folder that cannot be created stops the run early' {
        $resolve = $script:Text.IndexOf('Resolve-SPSOutputFolder')

        $resolve | Should -BeGreaterThan 0
        $resolve | Should -BeLessThan $script:Text.IndexOf('Import-SPSSharePointCommand')
        $resolve | Should -BeLessThan $script:Text.IndexOf('Get-SPSSiteInventory -WebApplicationUrl')
        $resolve | Should -BeLessThan $script:Text.IndexOf('Get-SPSFarmSolutionMap @solutionMapParams')
    }

    It 'says which folder it is, and when it is the default, in the log of the run' {
        $event = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Add-SPSInventoryEvent' -and $_.Extent.Text -match "Report folder: '\{0\}'" })

        $event | Should -HaveCount 1
        $event[0].Extent.Text | Should -Match '-Level Information'
        $event[0].Extent.Text | Should -Match 'OutputFolder is empty: the Reports folder next to the script'
    }

    It 'writes both exports in the folder that was resolved, and no longer reads OutputFolder from the settings for them' {
        foreach ($name in @('Export-SPSSolutionReport', 'Export-SPSInventoryReport')) {
            $export = @(Get-CommandText -Name $name)

            $export | Should -HaveCount 1
            $export[0].Extent.Text | Should -Match '-OutputFolder \$outputFolder\.Path'
            $export[0].Extent.Text | Should -Not -Match 'settings\.OutputFolder'
        }
        $script:Text | Should -Not -Match '\$settings\.OutputFolder'
    }
}

Describe 'The example settings files and OutputFolder' {
    It 'leave OutputFolder empty in <Name>, so that the reports go next to the script' -ForEach @(
        @{ Name = 'inventory-settings.example.psd1'; Path = $null; Key = 'Online' }
        @{ Name = 'inventory-settings.onprem.example.psd1'; Path = $null; Key = 'OnPrem' }
    ) {
        $path = if ($Key -eq 'Online') { $script:OnlineExample } else { $script:OnPremExample }

        $settings = Import-PowerShellDataFile -Path $path

        $settings.ContainsKey('OutputFolder') | Should -BeTrue
        $settings.OutputFolder | Should -Be ''
    }

    It 'say so next to the setting, in both files' -ForEach @(
        @{ Key = 'Online' }
        @{ Key = 'OnPrem' }
    ) {
        $path = if ($Key -eq 'Online') { $script:OnlineExample } else { $script:OnPremExample }
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should -Match 'Leave it empty to write them in a\s+# Reports folder next to Invoke-SPSSiteInventory\.ps1'
    }
}
