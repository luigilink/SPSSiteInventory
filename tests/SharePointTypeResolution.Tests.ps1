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

# Each run is a separate PowerShell process: the stub type of the SharePoint query stays out of the other tests, which
# rely on the object that the scan builds when the type is not loaded.
Describe 'The paged queries of the customization scan' {
    BeforeAll {
        $script:ModulePath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
        $script:ChildScript = Join-Path $TestDrive 'query-child.ps1'
        Set-Content -Path $script:ChildScript -Encoding UTF8 -Value @'
param ([System.String] $ModulePath, [switch] $LoadSharePointStub)
$ErrorActionPreference = 'Stop'
if ($LoadSharePointStub) {
    $source = 'namespace Microsoft.SharePoint { public class SPQuery { public uint RowLimit { get; set; } public string ViewAttributes { get; set; } public string Query { get; set; } public object ListItemCollectionPosition { get; set; } public string QueryThrottleMode { get; set; } } }'
    Add-Type -TypeDefinition $source
}
Import-Module -Name $ModulePath -Force
$list = [PSCustomObject]@{
    Title = 'Documents'
    RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Documents'; Properties = @{} }
    ContentTypes = @()
    WorkflowAssociations = @()
    EventReceivers = @()
    IrmEnabled = $false
    ItemCount = 0
    Views = @()
    CheckedOutFiles = @()
    EnableVersioning = $false
    Items = @()
    BaseTemplate = 101
    Fields = @()
    HasExternalDataSource = $false
}
$list | Add-Member -NotePropertyName Seen -NotePropertyValue ([System.Collections.Generic.List[object]]::new())
$list | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
    param ($Query)
    $this.Seen.Add([PSCustomObject]@{ Type = $Query.GetType().FullName; RowLimit = [string]$Query.RowLimit; ViewAttributes = [string]$Query.ViewAttributes; Query = [string]$Query.Query })
    return [PSCustomObject]@{ Items = @(); ListItemCollectionPosition = $null }
}
$web = [PSCustomObject]@{
    Url = 'https://intranet.contoso.com/sites/team'
    ContentTypes = @()
    Lists = @($list)
    WorkflowAssociations = @()
    HasUniqueRoleAssignments = $false
    CustomMasterUrl = ''
    Features = @()
    Files = @()
    IsRootWeb = $true
    HasUniqueRoleDefinitions = $true
    RoleDefinitions = @()
    Alerts = @()
    AlternateCssUrl = ''
    RootFolder = [PSCustomObject]@{ WelcomePage = '' }
}
$web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
$site = [PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/team'; Features = @(); Solutions = @(); AllWebs = @($web) }
$null = Get-SPSSiteCustomization -Site $site -WarningAction SilentlyContinue
foreach ($entry in $list.Seen) {
    ConvertTo-Json -InputObject $entry -Compress
}
'@

        function Invoke-QueryChild {
            param ([switch] $LoadStub)

            $shell = (Get-Process -Id $PID).Path
            $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script:ChildScript, '-ModulePath', $script:ModulePath)
            if ($LoadStub) {
                $arguments += '-LoadSharePointStub'
            }
            $output = @(& $shell @arguments 2>&1 | ForEach-Object { [System.String]$_ })
            $exitCode = $LASTEXITCODE
            $entry = @($output | Where-Object { $_ -like '{*' } | ForEach-Object { ConvertFrom-Json -InputObject $_ })

            [PSCustomObject]@{ ExitCode = $exitCode; Entry = $entry; Text = ($output -join [System.Environment]::NewLine) }
        }
    }

    It 'hands a SharePoint query object to GetItems when the SharePoint type is loaded' {
        $result = Invoke-QueryChild -LoadStub

        $result.ExitCode | Should -Be 0 -Because $result.Text
        $result.Entry.Count | Should -BeGreaterThan 1
        foreach ($entry in $result.Entry) {
            $entry.Type | Should -Be 'Microsoft.SharePoint.SPQuery'
            $entry.RowLimit | Should -Be '200'
            $entry.ViewAttributes | Should -Be "Scope='RecursiveAll'"
        }
        @($result.Entry | Where-Object { $_.Query -match 'CheckoutUser' }) | Should -HaveCount 1
    }

    It 'still builds a plain query object on a host without the SharePoint type' {
        $result = Invoke-QueryChild

        $result.ExitCode | Should -Be 0 -Because $result.Text
        $result.Entry.Count | Should -BeGreaterThan 1
        foreach ($entry in $result.Entry) {
            $entry.Type | Should -Be 'System.Management.Automation.PSCustomObject'
            $entry.RowLimit | Should -Be '200'
            $entry.ViewAttributes | Should -Be "Scope='RecursiveAll'"
        }
    }
}
