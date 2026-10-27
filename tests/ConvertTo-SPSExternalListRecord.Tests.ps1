# Behavior tests for ConvertTo-SPSExternalListRecord (no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # ConvertTo-SPSExternalListRecord is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # Real .NET types are required: PowerShell turns a failing getter into $null, and also swallows
    # exceptions from script properties, so only a compiled getter reproduces a failed property read.
    if (-not ('SPSTestExternalDataSource' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

public class SPSTestExternalDataSource
{
    private readonly Dictionary<string, string> properties = new Dictionary<string, string>();
    public bool FailRead { get; set; }
    public void Set(string key, string value) { properties[key] = value; }
    public string GetProperty(string key)
    {
        if (FailRead) { throw new InvalidOperationException("data source unavailable"); }
        string value;
        return properties.TryGetValue(key, out value) ? value : null;
    }
}

public class SPSTestExternalList
{
    public string Title { get; set; }
    public object RootFolder { get; set; }
    public object DataSourceValue { get; set; }
    public bool FailDataSource { get; set; }
    public object DataSource { get { if (FailDataSource) { throw new InvalidOperationException("data source store unavailable"); } return DataSourceValue; } }
}
'@
    }

    function Get-TestDataSource {
        param ([string]$Instance = 'CrmInstance', [string]$EntityNamespace = 'Contoso.Crm', [string]$Entity = 'Customer')
        $dataSource = [PSCustomObject]@{
            Properties = @{ LobSystemInstance = $Instance; EntityNamespace = $EntityNamespace; Entity = $Entity; SpecificFinder = 'Read Item' }
        }
        $dataSource | Add-Member -MemberType ScriptMethod -Name GetProperty -Value {
            param ($Key)
            if ($this.Properties.ContainsKey($Key)) { return $this.Properties[$Key] }
            return $null
        }
        return $dataSource
    }

    function Get-TestExternalList {
        param ($DataSource = (Get-TestDataSource))
        [PSCustomObject]@{
            Title = 'Customers'
            RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Lists/Customers' }
            HasExternalDataSource = $true
            DataSource = $DataSource
        }
    }

    function Convert-List {
        param ($List)
        & $script:Module {
            param ($Candidate)
            ConvertTo-SPSExternalListRecord -List $Candidate -SiteUrl 'https://intranet.contoso.com/sites/team' -WebUrl 'https://intranet.contoso.com/sites/team/sub'
        } $List
    }
}

Describe 'ConvertTo-SPSExternalListRecord' {
    It 'projects the list and the BCS binding SharePoint stores with it' {
        $record = Convert-List -List (Get-TestExternalList)

        $record.SiteUrl | Should -Be 'https://intranet.contoso.com/sites/team'
        $record.WebUrl | Should -Be 'https://intranet.contoso.com/sites/team/sub'
        $record.ListTitle | Should -Be 'Customers'
        $record.ListUrl | Should -Be '/sites/team/Lists/Customers'
        $record.LobSystemInstance | Should -Be 'CrmInstance'
        $record.EntityNamespace | Should -Be 'Contoso.Crm'
        $record.Entity | Should -Be 'Customer'
    }

    It 'does not collect item counts, dates or the list creator, which live outside SharePoint or are personal data' {
        $record = Convert-List -List (Get-TestExternalList)

        $record.PSObject.Properties.Name | Should -Not -Contain 'ListItemCount'
        $record.PSObject.Properties.Name | Should -Not -Contain 'ItemLastModifiedDate'
        $record.PSObject.Properties.Name | Should -Not -Contain 'ListCreator'
    }

    It 'rejects a list that is not external because it has no data source' {
        $list = [PSCustomObject]@{ Title = 'Documents'; RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Documents' }; HasExternalDataSource = $false; DataSource = $null }

        { Convert-List -List $list } | Should -Throw "*external data source of list 'Documents' could not be read*"
    }

    It 'rejects an external list whose title or URL cannot be read' {
        $noTitle = Get-TestExternalList
        $noTitle.Title = ''
        { Convert-List -List $noTitle } | Should -Throw '*list title could not be read*'
        $noUrl = Get-TestExternalList
        $noUrl.RootFolder = $null
        { Convert-List -List $noUrl } | Should -Throw "*URL of list 'Customers' could not be read*"
    }

    It 'rejects an external list whose data source cannot be read' {
        { Convert-List -List (Get-TestExternalList -DataSource $null) } | Should -Throw "*external data source of list 'Customers' could not be read*"

        $list = [SPSTestExternalList]::new()
        $list.Title = 'Customers'
        $list.RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/team/Lists/Customers' }
        $list.FailDataSource = $true
        { Convert-List -List $list } | Should -Throw '*data source store unavailable*'
    }

    It 'rejects a binding value that is missing or blank instead of exporting an empty value' {
        foreach ($key in @('LobSystemInstance', 'EntityNamespace', 'Entity')) {
            $dataSource = Get-TestDataSource
            $dataSource.Properties[$key] = ' '

            { Convert-List -List (Get-TestExternalList -DataSource $dataSource) } | Should -Throw "*The $key of the external data source of list 'Customers' could not be read*"
        }

        $missing = Get-TestDataSource
        $missing.Properties.Remove('Entity')
        { Convert-List -List (Get-TestExternalList -DataSource $missing) } | Should -Throw '*The Entity of the external data source*'
    }

    It 'lets a failing data source method propagate and reads the binding of a real .NET data source' {
        $failing = [SPSTestExternalDataSource]::new()
        $failing.FailRead = $true
        { Convert-List -List (Get-TestExternalList -DataSource $failing) } | Should -Throw '*data source unavailable*'

        $real = [SPSTestExternalDataSource]::new()
        $real.Set('LobSystemInstance', 'SapInstance')
        $real.Set('EntityNamespace', 'Contoso.Sap')
        $real.Set('Entity', 'Order')

        $record = Convert-List -List (Get-TestExternalList -DataSource $real)

        $record.LobSystemInstance | Should -Be 'SapInstance'
        $record.Entity | Should -Be 'Order'
    }
}
