# A SharePoint type must be found among the loaded assemblies. Type.GetType with an assembly name that has no version and
# no public key token does not look in the GAC, so it returns $null on a farm server while it works with the mocks of the
# unit tests: no mock can show that failure, so these tests read the code instead.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent

    # The static calls of [Type]::GetType and [System.Type]::GetType in a script, as text.
    $script:FindGetTypeCall = {
        param ([System.String] $Content)

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$null, [ref]$null)
        $nodes = $ast.FindAll({
                param ($node)
                $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $node.Static -and
                $node.Member.Extent.Text -eq 'GetType' -and
                $node.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                $node.Expression.TypeName.Name -in @('Type', 'System.Type')
            }, $true)
        foreach ($node in $nodes) {
            $node.Extent.Text
        }
    }

    $script:SharePointCall = @()
    $folders = @((Join-Path $repoRoot 'src'), (Join-Path $repoRoot 'tools'))
    foreach ($file in (Get-ChildItem -Path $folders -Include '*.ps1', '*.psm1' -Recurse -File)) {
        foreach ($text in (& $script:FindGetTypeCall ([System.IO.File]::ReadAllText($file.FullName)))) {
            if ($text -match 'Microsoft\.(SharePoint|Office)') {
                $script:SharePointCall += ('{0}: {1}' -f $file.Name, $text)
            }
        }
    }
}

Describe 'The SharePoint types of the toolkit' {
    It 'are not resolved with Type.GetType and an assembly name' {
        $script:SharePointCall | Should -BeNullOrEmpty -Because "'Microsoft.SharePoint.SPQuery' -as [System.Type] finds a type among the loaded assemblies, Type.GetType with a partial assembly name does not"
    }

    It 'are found by the check above when the call is there' {
        $bad = "`$type = [Type]::GetType('Microsoft.SharePoint.SPQuery, Microsoft.SharePoint', `$false)"
        $alsoBad = "`$type = [System.Type]::GetType('Microsoft.Office.Server.UserProfiles.UserProfileManager, Microsoft.Office.Server.UserProfiles')"
        $fine = "`$type = 'Microsoft.SharePoint.SPQuery' -as [System.Type]; `$other = `$object.GetType()"

        @(& $script:FindGetTypeCall $bad) | Should -HaveCount 1
        @(& $script:FindGetTypeCall $alsoBad) | Should -HaveCount 1
        @(& $script:FindGetTypeCall $fine) | Should -HaveCount 0
    }
}
