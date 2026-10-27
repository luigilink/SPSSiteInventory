# Behavior tests for ConvertTo-SPSSharePointAlertRecord (pure, no farm needed).
BeforeDiscovery {
    # Each property the projection reads, with the alert that makes it read it (a getter that is skipped cannot fail).
    $script:ReadCases = @(
        @{ Name = 'ID'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'AlertType'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'Title'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'EventType'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'AlertFrequency'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'Status'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'DeliveryChannels'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'AlwaysNotify'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'UserId'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'AlertTemplateName'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'Filter'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'DynamicRecipient'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'ListUrl'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'ListID'; AlertType = 'List'; Frequency = 'Immediate' }
        @{ Name = 'ItemID'; AlertType = 'Item'; Frequency = 'Immediate' }
        @{ Name = 'AlertTime'; AlertType = 'List'; Frequency = 'Daily' }
    )
}

BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # PowerShell turns an exception from a .NET getter into $null, so the getters that throw must be real ones.
    if (-not ('SPSSiteInventoryTestAlert' -as [type])) {
        Add-Type -TypeDefinition @'
using System;

public enum SPSSiteInventoryTestAlertType { List, Item, Custom }
public enum SPSSiteInventoryTestFrequency { Immediate, Daily, Weekly }
public enum SPSSiteInventoryTestStatus { On, Off, Error }
public enum SPSSiteInventoryTestChannels { Email = 1, Sms = 2 }
public enum SPSSiteInventoryTestEvent { Add = 1, Modify = 2, Delete = 4, All = -1 }

public sealed class SPSSiteInventoryTestAlert
{
    public Guid IdValue { get; set; }
    public string TitleValue { get; set; }
    public string AlertTemplateNameValue { get; set; }
    public string FilterValue { get; set; }
    public string DynamicRecipientValue { get; set; }
    public SPSSiteInventoryTestAlertType AlertTypeValue { get; set; }
    public SPSSiteInventoryTestEvent EventTypeValue { get; set; }
    public SPSSiteInventoryTestFrequency AlertFrequencyValue { get; set; }
    public SPSSiteInventoryTestStatus StatusValue { get; set; }
    public SPSSiteInventoryTestChannels DeliveryChannelsValue { get; set; }
    public bool AlwaysNotifyValue { get; set; }
    public int UserIdValue { get; set; }
    public DateTime TimeValue { get; set; }
    public string ListUrlValue { get; set; }
    public Guid ListIdValue { get; set; }
    public int ItemIdValue { get; set; }
    public object UserValue { get; set; }
    public bool UserThrows { get; set; }
    public string FailOn { get; set; }
    public static int UserLookups;

    private void Check(string name)
    {
        if (FailOn == name) { throw new InvalidOperationException(name + " getter failed."); }
    }

    public Guid ID { get { Check("ID"); return IdValue; } }
    public string Title { get { Check("Title"); return TitleValue; } }
    public string AlertTemplateName { get { Check("AlertTemplateName"); return AlertTemplateNameValue; } }
    public string Filter { get { Check("Filter"); return FilterValue; } }
    public string DynamicRecipient { get { Check("DynamicRecipient"); return DynamicRecipientValue; } }
    public SPSSiteInventoryTestAlertType AlertType { get { Check("AlertType"); return AlertTypeValue; } }
    public SPSSiteInventoryTestEvent EventType { get { Check("EventType"); return EventTypeValue; } }
    public SPSSiteInventoryTestFrequency AlertFrequency { get { Check("AlertFrequency"); return AlertFrequencyValue; } }
    public SPSSiteInventoryTestStatus Status { get { Check("Status"); return StatusValue; } }
    public SPSSiteInventoryTestChannels DeliveryChannels { get { Check("DeliveryChannels"); return DeliveryChannelsValue; } }
    public bool AlwaysNotify { get { Check("AlwaysNotify"); return AlwaysNotifyValue; } }
    public int UserId { get { Check("UserId"); return UserIdValue; } }

    // SharePoint throws for these when the alert type or frequency does not define them.
    public string ListUrl
    {
        get
        {
            Check("ListUrl");
            if (AlertTypeValue == SPSSiteInventoryTestAlertType.Custom) { throw new InvalidOperationException("A custom alert has no list URL."); }
            return ListUrlValue;
        }
    }

    public Guid ListID
    {
        get
        {
            Check("ListID");
            if (AlertTypeValue == SPSSiteInventoryTestAlertType.Custom) { throw new InvalidOperationException("A custom alert has no list ID."); }
            return ListIdValue;
        }
    }

    public int ItemID
    {
        get
        {
            Check("ItemID");
            if (AlertTypeValue != SPSSiteInventoryTestAlertType.Item) { throw new InvalidOperationException("Only an item alert has an item ID."); }
            return ItemIdValue;
        }
    }

    public DateTime AlertTime
    {
        get
        {
            Check("AlertTime");
            if (AlertFrequencyValue == SPSSiteInventoryTestFrequency.Immediate) { throw new InvalidOperationException("An immediate alert has no time."); }
            return TimeValue;
        }
    }

    public object User
    {
        get
        {
            UserLookups++;
            if (UserThrows) { throw new InvalidOperationException("The user is not in the site."); }
            return UserValue;
        }
    }
}
'@
    }

    function New-TestAlert {
        param (
            [string]$AlertType = 'List',
            [string]$Frequency = 'Immediate',
            [string]$FailOn = '',
            [int]$UserId = 7,
            [object]$User = [PSCustomObject]@{ LoginName = "i:0#.w|contoso\user$UserId" },
            [switch]$UserThrows
        )
        $alert = [SPSSiteInventoryTestAlert]::new()
        $alert.IdValue = [guid]'11111111-1111-1111-1111-111111111111'
        $alert.TitleValue = 'Documents: all changes'
        $alert.AlertTemplateNameValue = 'SPAlertTemplateType.DocumentLibrary'
        $alert.FilterValue = '<Query />'
        $alert.DynamicRecipientValue = ''
        $alert.AlertTypeValue = $AlertType
        $alert.EventTypeValue = 'All'
        $alert.AlertFrequencyValue = $Frequency
        $alert.StatusValue = 'On'
        $alert.DeliveryChannelsValue = 'Email'
        $alert.AlwaysNotifyValue = $true
        $alert.UserIdValue = $UserId
        $alert.TimeValue = [datetime]'2026-10-27T08:30:00'
        $alert.ListUrlValue = 'Shared Documents'
        $alert.ListIdValue = [guid]'22222222-2222-2222-2222-222222222222'
        $alert.ItemIdValue = 42
        $alert.UserValue = $User
        $alert.UserThrows = [bool]$UserThrows
        $alert.FailOn = $FailOn
        return $alert
    }

    function ConvertTo-Record {
        param ([object]$Alert, [hashtable]$Cache)
        if ($PSBoundParameters.ContainsKey('Cache')) {
            & $script:Module { param ($Source, $Users) ConvertTo-SPSSharePointAlertRecord -Alert $Source -SiteUrl 'https://intranet/sites/team' -WebUrl 'https://intranet/sites/team/sub' -UserLoginCache $Users } $Alert $Cache
        }
        else {
            & $script:Module { param ($Source) ConvertTo-SPSSharePointAlertRecord -Alert $Source -SiteUrl 'https://intranet/sites/team' -WebUrl 'https://intranet/sites/team/sub' } $Alert
        }
    }
}

Describe 'ConvertTo-SPSSharePointAlertRecord' {
    It 'projects an immediate list alert with its owner' {
        $record = ConvertTo-Record -Alert (New-TestAlert)

        $record.SiteUrl | Should -Be 'https://intranet/sites/team'
        $record.WebUrl | Should -Be 'https://intranet/sites/team/sub'
        $record.AlertId | Should -Be '11111111-1111-1111-1111-111111111111'
        $record.Title | Should -Be 'Documents: all changes'
        $record.AlertTemplateName | Should -Be 'SPAlertTemplateType.DocumentLibrary'
        $record.AlertType | Should -Be 'List'
        $record.ListUrl | Should -Be 'Shared Documents'
        $record.ListId | Should -Be '22222222-2222-2222-2222-222222222222'
        $record.ItemId | Should -Be ''
        $record.EventType | Should -Be 'All'
        $record.AlertFrequency | Should -Be 'Immediate'
        $record.AlertTime | Should -Be ''
        $record.Status | Should -Be 'On'
        $record.DeliveryChannels | Should -Be 'Email'
        $record.AlwaysNotify | Should -BeTrue
        $record.Filter | Should -Be '<Query />'
        $record.DynamicRecipient | Should -Be ''
        $record.UserId | Should -Be 7
        $record.UserLoginName | Should -Be 'i:0#.w|contoso\user7'
    }

    It 'adds the item ID of an item alert' {
        $record = ConvertTo-Record -Alert (New-TestAlert -AlertType 'Item')

        $record.AlertType | Should -Be 'Item'
        $record.ListUrl | Should -Be 'Shared Documents'
        $record.ItemId | Should -Be '42'
    }

    It 'projects a custom alert without reading the list or the item, which SharePoint refuses' {
        $record = ConvertTo-Record -Alert (New-TestAlert -AlertType 'Custom')

        $record.AlertType | Should -Be 'Custom'
        $record.ListUrl | Should -Be ''
        $record.ListId | Should -Be ''
        $record.ItemId | Should -Be ''
    }

    It 'reads the time of a <Frequency> digest' -ForEach @(
        @{ Frequency = 'Daily' }
        @{ Frequency = 'Weekly' }
    ) {
        $record = ConvertTo-Record -Alert (New-TestAlert -Frequency $Frequency)

        $record.AlertFrequency | Should -Be $Frequency
        $record.AlertTime | Should -Be '2026-10-27 08:30'
    }

    It 'leaves the owner empty when the user is no longer in the site, without failing' {
        $record = ConvertTo-Record -Alert (New-TestAlert -UserThrows)

        $record.UserId | Should -Be 7
        $record.UserLoginName | Should -Be ''
        $record.AlertId | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'does not look for the owner of an alert without a user' {
        $record = ConvertTo-Record -Alert (New-TestAlert -UserId 0)

        $record.UserId | Should -Be 0
        $record.UserLoginName | Should -Be ''
    }

    It 'raises the error of the getter instead of an empty cell when <Name> cannot be read' -ForEach $script:ReadCases {
        $alert = New-TestAlert -AlertType $AlertType -Frequency $Frequency -FailOn $Name

        { ConvertTo-Record -Alert $alert } | Should -Throw -ExpectedMessage "*$Name getter failed*"
    }

    It 'refuses an alert whose <Name> is empty' -ForEach @(
        @{ Name = 'ID'; Set = { param ($a) $a.IdValue = [guid]::Empty } }
        @{ Name = 'Title'; Set = { param ($a) $a.TitleValue = '' } }
    ) {
        $alert = New-TestAlert
        & $Set $alert

        { ConvertTo-Record -Alert $alert } | Should -Throw -ExpectedMessage "*$Name*"
    }

    It 'keeps the row of an alert whose list no longer exists, with an empty list URL' {
        $alert = New-TestAlert
        $alert.ListUrlValue = $null

        $record = ConvertTo-Record -Alert $alert

        $record.ListUrl | Should -Be ''
        $record.ListId | Should -Be '22222222-2222-2222-2222-222222222222'
    }

    It 'resolves each owner once when the alerts share a cache' {
        $cache = @{}
        [SPSSiteInventoryTestAlert]::UserLookups = 0

        $first = ConvertTo-Record -Alert (New-TestAlert -UserId 7) -Cache $cache
        $second = ConvertTo-Record -Alert (New-TestAlert -UserId 7) -Cache $cache
        $other = ConvertTo-Record -Alert (New-TestAlert -UserId 8) -Cache $cache

        [SPSSiteInventoryTestAlert]::UserLookups | Should -Be 2
        $first.UserLoginName | Should -Be 'i:0#.w|contoso\user7'
        $second.UserLoginName | Should -Be 'i:0#.w|contoso\user7'
        $other.UserLoginName | Should -Be 'i:0#.w|contoso\user8'
        $cache[7] | Should -Be 'i:0#.w|contoso\user7'
    }

    It 'remembers an owner that cannot be found, so the failing lookup is not repeated' {
        $cache = @{}
        [SPSSiteInventoryTestAlert]::UserLookups = 0

        $first = ConvertTo-Record -Alert (New-TestAlert -UserThrows) -Cache $cache
        $second = ConvertTo-Record -Alert (New-TestAlert -UserThrows) -Cache $cache

        [SPSSiteInventoryTestAlert]::UserLookups | Should -Be 1
        $first.UserLoginName | Should -Be ''
        $second.UserLoginName | Should -Be ''
        $cache.ContainsKey(7) | Should -BeTrue
    }

    It 'looks the owner up for every alert when no cache is given' {
        [SPSSiteInventoryTestAlert]::UserLookups = 0

        $null = ConvertTo-Record -Alert (New-TestAlert -UserId 7)
        $null = ConvertTo-Record -Alert (New-TestAlert -UserId 7)

        [SPSSiteInventoryTestAlert]::UserLookups | Should -Be 2
    }

    It 'does not look the owner up for an alert without a user, even with a cache' {
        $cache = @{}
        [SPSSiteInventoryTestAlert]::UserLookups = 0

        $null = ConvertTo-Record -Alert (New-TestAlert -UserId 0) -Cache $cache

        [SPSSiteInventoryTestAlert]::UserLookups | Should -Be 0
        $cache.Count | Should -Be 0
    }

    It 'accepts the values that are legitimately empty' {
        $alert = New-TestAlert
        $alert.AlertTemplateNameValue = $null
        $alert.FilterValue = $null
        $alert.DynamicRecipientValue = $null

        $record = ConvertTo-Record -Alert $alert

        $record.AlertTemplateName | Should -Be ''
        $record.Filter | Should -Be ''
        $record.DynamicRecipient | Should -Be ''
    }
}
