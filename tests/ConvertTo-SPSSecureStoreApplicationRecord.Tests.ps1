# Behavior tests for ConvertTo-SPSSecureStoreApplicationRecord (no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force

    # ConvertTo-SPSSecureStoreApplicationRecord is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # Mirrors Microsoft.BusinessData.Infrastructure.SecureStore.TargetApplicationType. A real .NET type is required for
    # the failing getters: PowerShell turns them into $null, and swallows script-property exceptions.
    if (-not ('SPSTestTargetApplicationType' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public enum SPSTestTargetApplicationType { Individual = 0, Group = 1, IndividualWithTicketing = 2, GroupWithTicketing = 3, RestrictedIndividual = 4, RestrictedGroup = 5 }

public class SPSTestFailingNameApplication
{
    public string Name { get { throw new InvalidOperationException("name unavailable"); } }
    public object Type { get { return SPSTestTargetApplicationType.Group; } }
}

public class SPSTestFailingTypeApplication
{
    public string Name { get { return "SapTarget"; } }
    public object Type { get { throw new InvalidOperationException("type unavailable"); } }
}

public class SPSTestFailingEmailApplication
{
    public string Name { get { return "SapTarget"; } }
    public object Type { get { return SPSTestTargetApplicationType.Group; } }
    public string ContactEmail { get { throw new InvalidOperationException("email unavailable"); } }
}

// The members of the contract of the Secure Store service are named in lower camel case.
public class SPSTestContractApplication
{
    public string appId { get { return "ContractTarget"; } }
    public string friendlyName { get { return "Contract display"; } }
    public string contactEmail { get { return "contract@contoso.com"; } }
    public string credentialManagementUrl { get { return "https://contoso.com/contract"; } }
    public int ticketTimeout { get { return 7; } }
    public object type { get { return SPSTestTargetApplicationType.GroupWithTicketing; } }
}

public class SPSTestContractFailingEmailApplication
{
    public string appId { get { return "ContractTarget"; } }
    public object type { get { return SPSTestTargetApplicationType.Group; } }
    public string contactEmail { get { throw new InvalidOperationException("contact unavailable"); } }
}
'@
    }

    function Get-TestApplication {
        param ($Name = 'SapTarget', $FriendlyName = 'SAP', $Email = 'owner@contoso.com', $Type = [SPSTestTargetApplicationType]::RestrictedGroup, $Url = [uri]'https://contoso.com/credentials', $Timeout = 2)
        [PSCustomObject]@{
            Name                    = $Name
            FriendlyName            = $FriendlyName
            ContactEmail            = $Email
            Type                    = $Type
            CredentialManagementUrl = $Url
            TicketTimeoutInMinutes  = $Timeout
        }
    }

    function Convert-Application {
        param ($Application)
        & $script:Module { param ($Candidate) ConvertTo-SPSSecureStoreApplicationRecord -Application $Candidate } $Application
    }
}

Describe 'ConvertTo-SPSSecureStoreApplicationRecord' {
    It 'projects the name, display name, contact, type, credential management URL and ticket time-out of a target application' {
        $record = Convert-Application -Application (Get-TestApplication)

        $record.Name | Should -Be 'SapTarget'
        $record.FriendlyName | Should -Be 'SAP'
        $record.ContactEmail | Should -Be 'owner@contoso.com'
        $record.ApplicationType | Should -Be 'RestrictedGroup'
        $record.CredentialManagementUrl | Should -Be 'https://contoso.com/credentials'
        $record.TicketTimeoutMinutes | Should -Be 2
        $record.TicketTimeoutMinutes | Should -BeOfType ([int])
    }

    It 'returns the properties of the row in a fixed order, and nothing else: no field of the application and no credential' {
        $application = Get-TestApplication
        $application | Add-Member -NotePropertyName Fields -NotePropertyValue @([PSCustomObject]@{ Name = 'Password'; Masked = $true })
        $application | Add-Member -NotePropertyName Credentials -NotePropertyValue 'secret'

        $record = Convert-Application -Application $application

        ($record.PSObject.Properties.Name -join ',') | Should -Be 'Name,FriendlyName,ContactEmail,ApplicationType,CredentialManagementUrl,TicketTimeoutMinutes'
        ($record | ConvertTo-Json -Compress) | Should -Not -Match 'secret|Password'
    }

    It 'reads the members under the names of the parameters of the cmdlets, and of the target application that the object wraps' -ForEach @(
        @{ Name = 'parameter names'; Object = [PSCustomObject]@{ Name = 'T1'; FriendlyName = 'F1'; ContactEmail = 'a@b.c'; ApplicationType = 'Group'; SetCredentialsUri = 'https://x/y'; TimeoutInMinutes = 5 } }
        @{ Name = 'wrapped target application'; Object = [PSCustomObject]@{ TargetApplication = [PSCustomObject]@{ Name = 'T1'; FriendlyName = 'F1'; ContactEmail = 'a@b.c'; Type = 'Group'; CredentialManagementUrl = 'https://x/y'; TicketTimeoutInMinutes = 5 } } }
        @{ Name = 'application ID'; Object = [PSCustomObject]@{ ApplicationId = 'T1'; FriendlyName = 'F1'; ContactEmail = 'a@b.c'; Type = 'Group'; CredentialManagementUri = 'https://x/y'; TicketTimeout = 5 } }
        @{ Name = 'names of the contract'; Object = [PSCustomObject]@{ appId = 'T1'; friendlyName = 'F1'; contactEmail = 'a@b.c'; type = 'Group'; credentialManagementUrl = 'https://x/y'; ticketTimeout = 5 } }
        @{ Name = 'wrapped target application with the names of the contract'; Object = [PSCustomObject]@{ TargetApplication = [PSCustomObject]@{ appId = 'T1'; friendlyName = 'F1'; contactEmail = 'a@b.c'; type = 'Group'; credentialManagementUrl = 'https://x/y'; ticketTimeout = 5 } } }
    ) {
        $record = Convert-Application -Application $Object

        $record.Name | Should -Be 'T1' -Because $Name
        $record.FriendlyName | Should -Be 'F1' -Because $Name
        $record.ContactEmail | Should -Be 'a@b.c' -Because $Name
        $record.ApplicationType | Should -Be 'Group' -Because $Name
        $record.CredentialManagementUrl | Should -Be 'https://x/y' -Because $Name
        $record.TicketTimeoutMinutes | Should -Be 5 -Because $Name
    }

    It 'reads an object whose members are named like the contract of the service: appId, friendlyName, contactEmail, type' {
        # The type exists once the tests run, not when they are discovered.
        $record = Convert-Application -Application ([SPSTestContractApplication]::new())

        $record.Name | Should -Be 'ContractTarget'
        $record.FriendlyName | Should -Be 'Contract display'
        $record.ContactEmail | Should -Be 'contract@contoso.com'
        $record.ApplicationType | Should -Be 'GroupWithTicketing'
        $record.CredentialManagementUrl | Should -Be 'https://contoso.com/contract'
        $record.TicketTimeoutMinutes | Should -Be 7
    }

    It 'leaves the values that have no member empty, and keeps a time-out of 0' {
        $record = Convert-Application -Application ([PSCustomObject]@{ Name = 'T1'; Type = 'Individual' })
        $zero = Convert-Application -Application (Get-TestApplication -Timeout 0)

        $record.FriendlyName | Should -Be ''
        $record.ContactEmail | Should -Be ''
        $record.CredentialManagementUrl | Should -Be ''
        $record.TicketTimeoutMinutes | Should -BeNullOrEmpty
        $zero.TicketTimeoutMinutes | Should -Be 0
    }

    It 'trims the text values' {
        $record = Convert-Application -Application (Get-TestApplication -Name '  SapTarget ' -FriendlyName ' SAP  ' -Email ' owner@contoso.com ')

        $record.Name | Should -Be 'SapTarget'
        $record.FriendlyName | Should -Be 'SAP'
        $record.ContactEmail | Should -Be 'owner@contoso.com'
    }

    It 'raises an error that lists the members of the object when the name or the type is not a member' -ForEach @(
        @{ Name = 'name'; Object = [PSCustomObject]@{ Title = 'x'; Type = 'Group' }; Message = '*no readable name (members: Title, Type)*' }
        @{ Name = 'type'; Object = [PSCustomObject]@{ Name = 'T1'; Kind = 'Group' }; Message = "*type of Secure Store application 'T1' could not be read (members: Kind, Name)*" }
    ) {
        { Convert-Application -Application $Object } | Should -Throw -ExpectedMessage $Message -Because $Name
    }

    It 'raises an error for an empty name or an empty type' {
        { Convert-Application -Application (Get-TestApplication -Name '  ') } | Should -Throw '*no readable name*'
        { Convert-Application -Application (Get-TestApplication -Type $null) } | Should -Throw '*could not be read*'
        { Convert-Application -Application (Get-TestApplication -Type '') } | Should -Throw '*could not be read*'
    }

    It 'raises an error instead of reading a getter that fails as an empty value' -ForEach @(
        @{ Member = 'name'; Pattern = 'name unavailable' }
        @{ Member = 'type'; Pattern = 'type unavailable' }
        @{ Member = 'email'; Pattern = 'email unavailable' }
        @{ Member = 'email of a member named in lower camel case'; Pattern = 'contact unavailable' }
    ) {
        # The types exist once the tests run, not when they are discovered.
        $object = switch ($Member) {
            'name' { [SPSTestFailingNameApplication]::new() }
            'type' { [SPSTestFailingTypeApplication]::new() }
            'email' { [SPSTestFailingEmailApplication]::new() }
            'email of a member named in lower camel case' { [SPSTestContractFailingEmailApplication]::new() }
        }

        { Convert-Application -Application $object } | Should -Throw ('*' + $Pattern + '*')
    }

    It 'raises an error for a ticket time-out that is not a number of minutes' {
        { Convert-Application -Application (Get-TestApplication -Timeout 'soon') } | Should -Throw '*not a number of minutes*'
    }
}
