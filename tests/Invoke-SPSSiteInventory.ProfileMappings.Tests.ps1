# The orchestrator reads SharePoint, so it cannot run here: these tests read its code, and check that the profile property mappings are read
# once for the farm, that a failure of that read cannot stop the site report, and that what it returns reaches the export.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:Path = Join-Path $repoRoot 'src/Invoke-SPSSiteInventory.ps1'
    $script:Text = Get-Content -LiteralPath $script:Path -Raw
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$null)
    $script:Commands = @($script:Ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))

    function Get-CommandText {
        param ([string]$Name)
        @($script:Commands | Where-Object { $_.GetCommandName() -eq $Name })
    }

    function Get-EnclosingTry {
        param ($Node)
        $parent = $Node.Parent
        while ($null -ne $parent -and $parent -isnot [System.Management.Automation.Language.TryStatementAst]) {
            $parent = $parent.Parent
        }
        return $parent
    }
}

Describe 'Invoke-SPSSiteInventory.ps1 and the profile property mappings' {
    It 'is valid PowerShell' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It 'reads the profile property mappings once, for the web applications of the settings' {
        $call = @(Get-CommandText -Name 'Get-SPSProfilePropertyMapping')

        $call | Should -HaveCount 1
        $call[0].Extent.Text | Should -Match '-WebApplicationUrl \$settings\.WebApplicationUrl'
    }

    It 'does not let a failure of that read stop the site report: the read is in a try that only logs a warning, after a result that says the inventory is not complete' {
        $call = @(Get-CommandText -Name 'Get-SPSProfilePropertyMapping')
        $try = Get-EnclosingTry -Node $call[0]

        $try | Should -Not -BeNullOrEmpty
        $try.CatchClauses[0].Body.Extent.Text | Should -Match '-Level Warning'
        $try.CatchClauses[0].Body.Extent.Text | Should -Not -Match 'throw'
        $script:Text | Should -Match '\$profileMappings = \[PSCustomObject\]@\{ Mappings = @\(\); Complete = \$false; Warnings = @\(\) \}'
        $script:Text.IndexOf('$profileMappings = [PSCustomObject]@{') | Should -BeLessThan $script:Text.IndexOf('Get-SPSProfilePropertyMapping -WebApplicationUrl')
    }

    It 'writes the warnings of the read to the log' {
        $script:Text | Should -Match 'foreach \(\$profileWarning in @\(\$profileMappings\.Warnings\)\)'
        $script:Text | Should -Match 'Add-SPSInventoryEvent -Message \$profileWarning -Level Warning'
    }

    It 'gives the mappings and the completeness flag to the export, and logs the paths of the report' {
        $export = @(Get-CommandText -Name 'Export-SPSInventoryReport')

        $export | Should -HaveCount 1
        $export[0].Extent.Text | Should -Match '-ProfilePropertyMappings @\(\$profileMappings\.Mappings\) -ProfileInventoryComplete \(\[bool\]\$profileMappings\.Complete\)'
        $script:Text | Should -Match 'Profile property mappings report\. CSV: \$\(\$output\.ProfileMappingsCsvPath\) \| JSON: \$\(\$output\.ProfileMappingsJsonPath\)'
    }
}
