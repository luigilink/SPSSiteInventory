# Behavior tests for ConvertTo-SPSBcsApplicationRecord (no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # ConvertTo-SPSBcsApplicationRecord is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # Mirrors Microsoft.BusinessData.MetadataModel.SystemType. A real .NET type is required for the
    # failing getters: PowerShell turns them into $null, and swallows script-property exceptions.
    if (-not ('SPSTestSystemType' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public enum SPSTestSystemType { Database = 1, WebService = 2, Custom = 6, Wcf = 8, DotNetAssembly = 9, OData = 10 }

public class SPSTestFailingLobSystem
{
    public string Name { get { throw new InvalidOperationException("name unavailable"); } }
    public object SystemType { get { return 8; } }
    public object LobSystemInstances { get { return new object[0]; } }
    public object Entities { get { return new object[0]; } }
}

public class SPSTestFailingEntitiesLobSystem
{
    public string Name { get { return "Crm"; } }
    public object SystemType { get { return 8; } }
    public object LobSystemInstances { get { return new object[0]; } }
    public object Entities { get { throw new InvalidOperationException("entities unavailable"); } }
}
'@
    }

    function Get-TestEntity {
        param ([string]$Namespace = 'Contoso.Crm', [string]$Name)
        [PSCustomObject]@{ Namespace = $Namespace; Name = $Name }
    }

    function Get-TestLobSystem {
        param ([string]$Name = 'CrmSystem', $Type = [SPSTestSystemType]::Wcf, [string[]]$Instances = @('CrmInstance'), [object[]]$Entities = @())
        [PSCustomObject]@{
            Name = $Name
            SystemType = $Type
            LobSystemInstances = @($Instances | ForEach-Object { [PSCustomObject]@{ Name = $_ } })
            Entities = $Entities
        }
    }

    function Convert-LobSystem {
        param ($LobSystem, [int]$Max = 20)
        & $script:Module { param ($Candidate, $Limit) ConvertTo-SPSBcsApplicationRecord -LobSystem $Candidate -MaxEntityName $Limit } $LobSystem $Max
    }
}

Describe 'ConvertTo-SPSBcsApplicationRecord' {
    It 'projects the name, type, sorted instances and entities of a LOB system' {
        $lob = Get-TestLobSystem -Name 'CrmSystem' -Instances @('ProdInstance', 'DevInstance') -Entities @(
            (Get-TestEntity -Name 'Customer')
            (Get-TestEntity -Namespace 'Contoso.Billing' -Name 'Invoice')
            (Get-TestEntity -Name 'Account')
        )

        $record = Convert-LobSystem -LobSystem $lob

        $record.LobSystemName | Should -Be 'CrmSystem'
        $record.LobSystemType | Should -Be 'Wcf'
        $record.LobSystemInstances | Should -Be 'DevInstance; ProdInstance'
        $record.EntityCount | Should -Be 3
        $record.LobEntities | Should -Be 'Contoso.Billing.Invoice; Contoso.Crm.Account; Contoso.Crm.Customer'
    }

    It 'reports a LOB system without entities or instances' {
        $record = Convert-LobSystem -LobSystem (Get-TestLobSystem -Instances @() -Entities @())

        $record.EntityCount | Should -Be 0
        $record.LobEntities | Should -Be ''
        $record.LobSystemInstances | Should -Be ''
    }

    It 'caps the entity names but keeps the full entity count' {
        $entities = @(1..25 | ForEach-Object { Get-TestEntity -Name ('Entity{0:D2}' -f $_) })

        $record = Convert-LobSystem -LobSystem (Get-TestLobSystem -Entities $entities) -Max 20

        $record.EntityCount | Should -Be 25
        ($record.LobEntities -split '; ') | Should -HaveCount 20
        $record.LobEntities | Should -Match '\(\+5 more\)$'
        $record.LobEntities | Should -Match '^Contoso\.Crm\.Entity01; '
    }

    It 'writes the system type of every kind of LOB system by name' {
        foreach ($type in @('Database', 'WebService', 'Custom', 'Wcf', 'DotNetAssembly', 'OData')) {
            (Convert-LobSystem -LobSystem (Get-TestLobSystem -Type ([SPSTestSystemType]$type))).LobSystemType | Should -Be $type
        }
    }

    It 'does not read or export connection properties, credentials or Secure Store targets' {
        $lob = Get-TestLobSystem
        $lob | Add-Member -MemberType NoteProperty -Name Properties -Value @{ RdbConnection = 'Server=secret-host;Password=hunter2' }
        $lob.LobSystemInstances[0] | Add-Member -MemberType NoteProperty -Name Properties -Value @{ SsoApplicationId = 'SecretTarget' }

        $record = Convert-LobSystem -LobSystem $lob

        ($record | ConvertTo-Json -Depth 4) | Should -Not -Match 'secret|hunter2|Secret'
        $record.PSObject.Properties.Name | Should -Be @('LobSystemName', 'LobSystemType', 'LobSystemInstances', 'EntityCount', 'LobEntities')
    }

    It 'rejects a LOB system without a readable name or type' {
        { Convert-LobSystem -LobSystem (Get-TestLobSystem -Name '') } | Should -Throw '*no readable name*'
        { Convert-LobSystem -LobSystem (Get-TestLobSystem -Type $null) } | Should -Throw "*system type of LOB system 'CrmSystem' could not be read*"
    }

    It 'rejects unreadable instances or entities instead of exporting empty values' {
        $noInstances = Get-TestLobSystem
        $noInstances.LobSystemInstances = $null
        { Convert-LobSystem -LobSystem $noInstances } | Should -Throw "*instances of LOB system 'CrmSystem' could not be read*"
        { Convert-LobSystem -LobSystem (Get-TestLobSystem -Instances @(' ')) } | Should -Throw "*instance of LOB system 'CrmSystem' has no readable name*"
        $noEntities = Get-TestLobSystem
        $noEntities.Entities = $null
        { Convert-LobSystem -LobSystem $noEntities } | Should -Throw "*entities of LOB system 'CrmSystem' could not be read*"
        { Convert-LobSystem -LobSystem (Get-TestLobSystem -Entities @((Get-TestEntity -Name ''))) } | Should -Throw '*entity of LOB system*no readable name or namespace*'
        { Convert-LobSystem -LobSystem (Get-TestLobSystem -Entities @((Get-TestEntity -Namespace '' -Name 'Customer'))) } | Should -Throw '*entity of LOB system*no readable name or namespace*'
    }

    It 'lets a failing getter propagate instead of reading it as an empty value' {
        { Convert-LobSystem -LobSystem ([SPSTestFailingLobSystem]::new()) } | Should -Throw '*name unavailable*'
        { Convert-LobSystem -LobSystem ([SPSTestFailingEntitiesLobSystem]::new()) } | Should -Throw "*entities of LOB system 'Crm' could not be read*"
    }

    It 'rejects an entity cap outside the supported range' {
        { Convert-LobSystem -LobSystem (Get-TestLobSystem) -Max 0 } | Should -Throw
    }
}
