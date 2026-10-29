# Behavior tests for Get-SPSConnectionPropertyMap (no farm needed). The connections are real .NET types, because the function reads a
# collection that declares no interface and reads non-public members by reflection, which a fake object cannot show.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    if (-not ('SPSTestMapCollection' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;

public class SPSTestProfileProperty { public string Name { get; set; } }

public class SPSTestPropertyMap {
    public SPSTestProfileProperty ProfileProperty { get; set; }
    public string DataSourcePropertyName { get; set; }
    public bool IsExport { get; set; }
}

public class SPSTestFailingPropertyMap {
    public SPSTestProfileProperty ProfileProperty { get { return new SPSTestProfileProperty { Name = "Title" }; } }
    public string DataSourcePropertyName { get { throw new InvalidOperationException("attribute unavailable"); } }
    public bool IsExport { get { return false; } }
}

// Like PropertyMapCollection, it declares no interface: it only has a GetEnumerator method.
public class SPSTestMapCollection {
    private readonly List<object> items = new List<object>();
    public void Add(object map) { items.Add(map); }
    public IEnumerator GetEnumerator() { return items.GetEnumerator(); }
}

public class SPSTestMappingConnection {
    public string DisplayName { get; set; }
    public string Type { get; set; }
    public SPSTestMapCollection PropertyMapping { get; set; }
}

public class SPSTestFailingNameConnection {
    public string DisplayName { get { throw new InvalidOperationException("name unavailable"); } }
    public string Type { get { return "BusinessDataCatalog"; } }
    public SPSTestMapCollection PropertyMapping { get { return new SPSTestMapCollection(); } }
}

// The mappings of an Active Directory import connection: a non-public method, and non-public members of non-public types.
internal class SPSTestAdMappingOfProperty { internal string ProfileProperty { get; set; } internal string ADAttribute { get; set; } }
internal class SPSTestAdMappingOfField { internal string ProfileProperty; internal string ADAttribute; }
internal class SPSTestAdMappingWithoutAttribute { internal string ProfileProperty { get; set; } }

public class SPSTestAdConnection {
    public string DisplayName { get; set; }
    public string Type { get { return "ActiveDirectoryImport"; } }
    public object PropertyMapping { get { return null; } }
    public string Mode = "items";
    internal IList ADImportPropertyMappings() {
        if (Mode == "null") { return null; }
        if (Mode == "throws") { throw new InvalidOperationException("the import is not configured"); }
        var list = new List<object>();
        if (Mode == "empty") { return list; }
        if (Mode == "noattribute") { list.Add(new SPSTestAdMappingWithoutAttribute { ProfileProperty = "FirstName" }); return list; }
        if (Mode == "noname") { list.Add(new SPSTestAdMappingOfProperty { ProfileProperty = " ", ADAttribute = "givenName" }); return list; }
        list.Add(new SPSTestAdMappingOfProperty { ProfileProperty = "FirstName", ADAttribute = "givenName" });
        list.Add(new SPSTestAdMappingOfField { ProfileProperty = "Department", ADAttribute = "department" });
        list.Add(null);
        return list;
    }
}

public class SPSTestAdConnectionWithoutMethod {
    public string DisplayName { get { return "No method"; } }
    public string Type { get { return "ActiveDirectoryImport"; } }
    public object PropertyMapping { get { return null; } }
}

public class SPSTestOtherConnection {
    public string DisplayName { get { return "Other"; } }
    public string Type { get { return "LdapEdirectory"; } }
    public object PropertyMapping { get { return null; } }
}
'@
    }

    function Get-Map {
        param ($Connection)
        & $script:Module { param ($Candidate) Get-SPSConnectionPropertyMap -Connection $Candidate } $Connection
    }

    function New-Connection {
        param ([string]$Name = 'Contoso', [string]$Type = 'BusinessDataCatalog', [object[]]$Map = @())
        $collection = [SPSTestMapCollection]::new()
        foreach ($entry in $Map) { $collection.Add($entry) }
        [SPSTestMappingConnection]@{ DisplayName = $Name; Type = $Type; PropertyMapping = $collection }
    }

    function New-Map {
        param ([string]$Property, [string]$Attribute, [bool]$Export = $false)
        [SPSTestPropertyMap]@{ ProfileProperty = [SPSTestProfileProperty]@{ Name = $Property }; DataSourcePropertyName = $Attribute; IsExport = $Export }
    }
}

Describe 'Get-SPSConnectionPropertyMap with a PropertyMapping' {
    It 'enumerates the collection through its GetEnumerator method, although it declares no interface' {
        $collection = [SPSTestMapCollection]::new()

        ($collection -is [System.Collections.IEnumerable]) | Should -BeFalse
        $maps = @(Get-Map -Connection (New-Connection -Map @((New-Map 'FirstName' 'givenName'), (New-Map 'Department' 'department'))))

        $maps | Should -HaveCount 2
    }

    It 'gives the property, the attribute and the direction of each mapping, Export when the mapping exports' {
        $maps = @(Get-Map -Connection (New-Connection -Map @((New-Map 'FirstName' 'givenName'), (New-Map 'Title' 'jobTitle' -Export $true))))

        $maps[0].ProfilePropertyName | Should -Be 'FirstName'
        $maps[0].DataSourcePropertyName | Should -Be 'givenName'
        $maps[0].Direction | Should -Be 'Import'
        $maps[1].ProfilePropertyName | Should -Be 'Title'
        $maps[1].DataSourcePropertyName | Should -Be 'jobTitle'
        $maps[1].Direction | Should -Be 'Export'
    }

    It 'returns no mapping, and no error, for a connection that has none' {
        @(Get-Map -Connection (New-Connection)) | Should -HaveCount 0
    }

    It 'raises an error, naming the connection, for a mapping that has no readable profile property' {
        $nameless = [SPSTestPropertyMap]@{ ProfileProperty = [SPSTestProfileProperty]@{ Name = '' }; DataSourcePropertyName = 'x' }
        $noProperty = [SPSTestPropertyMap]@{ DataSourcePropertyName = 'x' }

        { Get-Map -Connection (New-Connection -Name 'Crm' -Map @($nameless)) } | Should -Throw "*connection 'Crm' (BusinessDataCatalog)*no readable profile property name*"
        { Get-Map -Connection (New-Connection -Name 'Crm' -Map @($noProperty)) } | Should -Throw "*connection 'Crm' (BusinessDataCatalog)*has no profile property*"
    }

    It 'raises an error instead of reading a getter that fails as an empty value' {
        { Get-Map -Connection (New-Connection -Map @([SPSTestFailingPropertyMap]::new())) } | Should -Throw '*attribute unavailable*'
        { Get-Map -Connection ([SPSTestFailingNameConnection]::new()) } | Should -Throw '*name unavailable*'
    }
}

Describe 'Get-SPSConnectionPropertyMap with an Active Directory import connection' {
    It 'reads the mappings from the method that SharePoint uses, from properties and fields that are not public, as imports' {
        $maps = @(Get-Map -Connection ([SPSTestAdConnection]@{ DisplayName = 'contoso-local' }))

        $maps | Should -HaveCount 2
        $maps[0].ProfilePropertyName | Should -Be 'FirstName'
        $maps[0].DataSourcePropertyName | Should -Be 'givenName'
        $maps[1].ProfilePropertyName | Should -Be 'Department'
        $maps[1].DataSourcePropertyName | Should -Be 'department'
        @($maps.Direction | Select-Object -Unique) | Should -Be @('Import')
    }

    It 'returns no mapping, and no error, when SharePoint returns an empty list' {
        @(Get-Map -Connection ([SPSTestAdConnection]@{ DisplayName = 'contoso-local'; Mode = 'empty' })) | Should -HaveCount 0
    }

    It 'raises an error, naming the connection, when the method is not there, returns nothing or fails' {
        { Get-Map -Connection ([SPSTestAdConnectionWithoutMethod]::new()) } | Should -Throw "*Active Directory import connection 'No method' (ActiveDirectoryImport)*was not found*"
        { Get-Map -Connection ([SPSTestAdConnection]@{ DisplayName = 'Null'; Mode = 'null' }) } | Should -Throw "*'Null' (ActiveDirectoryImport)*SharePoint returned none*"
        { Get-Map -Connection ([SPSTestAdConnection]@{ DisplayName = 'Fails'; Mode = 'throws' }) } | Should -Throw "*'Fails' (ActiveDirectoryImport)*the import is not configured*"
    }

    It 'gives the error raised by SharePoint as the reason, not the message of the call that wraps it' {
        $message = $null
        try {
            Get-Map -Connection ([SPSTestAdConnection]@{ DisplayName = 'Fails'; Mode = 'throws' }) | Out-Null
        }
        catch {
            $message = $_.Exception.Message
        }

        $message | Should -Be "The property mappings of the Active Directory import connection 'Fails' (ActiveDirectoryImport) could not be read: the import is not configured"
    }

    It 'raises an error, naming the connection, when a mapping has no attribute member or no property name' {
        { Get-Map -Connection ([SPSTestAdConnection]@{ DisplayName = 'Old'; Mode = 'noattribute' }) } | Should -Throw "*'Old' (ActiveDirectoryImport)*no member named ADAttribute*"
        { Get-Map -Connection ([SPSTestAdConnection]@{ DisplayName = 'Blank'; Mode = 'noname' }) } | Should -Throw "*'Blank' (ActiveDirectoryImport)*no readable profile property name*"
    }

    It 'raises an error for a connection of another kind that has no PropertyMapping' {
        { Get-Map -Connection ([SPSTestOtherConnection]::new()) } | Should -Throw "*connection 'Other' (LdapEdirectory)*not an Active Directory import connection*"
    }
}
