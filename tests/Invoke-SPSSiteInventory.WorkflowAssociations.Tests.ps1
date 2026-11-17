# The orchestrator reads SharePoint, so it cannot run here: these tests read its code, and check that the workflow association rows
# reach the export and that the files are logged.
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
}

Describe 'Invoke-SPSSiteInventory.ps1 and the workflow associations' {
    It 'is valid PowerShell' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Path, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It 'gives the workflow association rows of the assessment to the export, before the splat of the packages' {
        $export = @(Get-CommandText -Name 'Export-SPSInventoryReport')

        $script:Text | Should -Match '\$workflowAssociations = @\(\$assessment\.WorkflowAssociations\)'
        $export | Should -HaveCount 1
        $export[0].Extent.Text | Should -Match '-WorkflowAssociations \$workflowAssociations '
        $export[0].Extent.Text.IndexOf('-WorkflowAssociations') | Should -BeLessThan $export[0].Extent.Text.IndexOf('@packageExportParams')
        $script:Text.IndexOf('$workflowAssociations = @($assessment.WorkflowAssociations)') | Should -BeLessThan $script:Text.IndexOf('$output = Export-SPSInventoryReport')
    }

    It 'logs the paths of the workflow association report, once, at the information level' {
        $event = @($script:Commands | Where-Object { $_.GetCommandName() -eq 'Add-SPSInventoryEvent' -and $_.Extent.Text -match 'Workflow association report\.' })

        $event | Should -HaveCount 1
        $event[0].Extent.Text | Should -Match 'CSV: \$\(\$output\.WorkflowAssociationsCsvPath\) \| JSON: \$\(\$output\.WorkflowAssociationsJsonPath\)'
        $event[0].Extent.Text | Should -Match '-Level Information'
    }
}
