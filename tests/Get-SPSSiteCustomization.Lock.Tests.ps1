# Behavior tests for the lock state of Get-SPSSiteCustomization, with a site whose getters raise
# the errors that SharePoint raises. A PSCustomObject cannot reproduce them: PowerShell turns the
# exception of a .NET property getter into $null, which is how a NoAccess lock went unnoticed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    if (-not ('SPSLockTestSite' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Runtime.InteropServices;

// The collections of a site that SharePoint cannot read are returned, and raise when they are enumerated.
public sealed class SPSLockTestCollection : IEnumerable
{
    private readonly int hresult;
    private readonly string message;

    public SPSLockTestCollection(int hresult, string message)
    {
        this.hresult = hresult;
        this.message = message;
    }

    public IEnumerator GetEnumerator()
    {
        if (hresult != 0) { throw new COMException(message, hresult); }
        return new object[0].GetEnumerator();
    }
}

public sealed class SPSLockTestSite
{
    public string Url = "https://intranet.contoso.com/sites/locked";
    public bool ReadLockedValue;
    public bool WriteLockedValue;
    public bool ReadOnlyValue;
    public bool IsReadLockedValue;
    // An HRESULT other than 0 makes the getter raise a COMException with it.
    public int ReadLockedError;
    public int WriteLockedError;
    public int ReadOnlyError;
    public int OtherError;
    public string ErrorMessage = "Access to this Web site has been blocked. Please contact the administrator to resolve this problem.";

    private void Raise(int hresult)
    {
        if (hresult != 0) { throw new COMException(ErrorMessage, hresult); }
    }

    public bool ReadLocked { get { Raise(ReadLockedError); return ReadLockedValue; } }
    public bool WriteLocked { get { Raise(WriteLockedError); return WriteLockedValue; } }
    public bool ReadOnly { get { Raise(ReadOnlyError); return ReadOnlyValue; } }
    public bool IsReadLocked { get { return IsReadLockedValue; } }
    public IEnumerable Solutions { get { return new SPSLockTestCollection(OtherError, ErrorMessage); } }
    public IEnumerable Features { get { return new SPSLockTestCollection(OtherError, ErrorMessage); } }
    public IEnumerable AllWebs { get { return new SPSLockTestCollection(OtherError, ErrorMessage); } }
}
'@
    }

    # 0x81020071, the error of a NoAccess lock, 0x81070966 the one of a NoAdditions lock and 0x80070005 an access denied.
    $script:Blocked = -2130575247
    $script:AdditionsBlocked = -2130245274
    $script:AccessDenied = -2147024891
    $script:Failure = -2147467259

    function New-LockSite {
        param ([hashtable]$Setting = @{})
        $site = [SPSLockTestSite]::new()
        foreach ($name in $Setting.Keys) {
            $site.$name = $Setting[$name]
        }
        $site
    }

    # What a NoAccess site collection does: every read of its lock flags and of the rest raises the error.
    function New-NoAccessSite {
        param ([hashtable]$Setting = @{})
        $all = @{ ReadLockedError = $script:Blocked; WriteLockedError = $script:Blocked; ReadOnlyError = $script:Blocked; OtherError = $script:Blocked; IsReadLockedValue = $true }
        foreach ($name in $Setting.Keys) { $all[$name] = $Setting[$name] }
        New-LockSite -Setting $all
    }

    function Get-Lock {
        param ($Site)
        $result = [PSCustomObject]@{ Signals = $null; Warning = @() }
        $warnings = $null
        $result.Signals = Get-SPSSiteCustomization -Site $Site -WarningVariable warnings -WarningAction SilentlyContinue
        $result.Warning = @($warnings | ForEach-Object { [string]$_.Message })
        $result
    }
}

Describe 'Get-SPSSiteCustomization lock state' {
    Context 'a site collection locked with NoAccess' {
        It 'is reported as NoAccess, locked and blocking, although every read of the site raises' {
            $lock = Get-Lock -Site (New-NoAccessSite)

            $lock.Signals.SiteLockState | Should -Be 'NoAccess'
            $lock.Signals.IsLockedSite | Should -BeTrue
            $lock.Signals.HasNoAccessLock | Should -BeTrue
        }

        It 'does not warn that the lock state could not be read, and stays partial because nothing else can be read' {
            $lock = Get-Lock -Site (New-NoAccessSite)

            @($lock.Warning | Where-Object { $_ -match 'lock state' }).Count | Should -Be 0
            $lock.Signals.CustomizationInventoryComplete | Should -BeFalse
            ($lock.Warning -join ' ') | Should -Match 'Could not read sandbox solutions'
        }

        It 'is recognized from the error alone, when IsReadLocked does not exist or is false' {
            (Get-Lock -Site (New-NoAccessSite @{ IsReadLockedValue = $false })).Signals.SiteLockState | Should -Be 'NoAccess'
        }

        It 'is recognized from the English message when the HRESULT is another one' {
            $site = New-NoAccessSite @{ ReadLockedError = $script:Failure; IsReadLockedValue = $false }

            (Get-Lock -Site $site).Signals.SiteLockState | Should -Be 'NoAccess'
        }

        It 'is recognized from IsReadLocked when the flag raises an error that is not the blocked one' {
            $site = New-NoAccessSite @{ ReadLockedError = $script:AccessDenied; ErrorMessage = 'Access is denied.' }

            (Get-Lock -Site $site).Signals.SiteLockState | Should -Be 'NoAccess'
        }

        It 'is recognized when ReadLocked can be read and is true' {
            $site = New-LockSite @{ ReadLockedValue = $true; WriteLockedValue = $true; ReadOnlyValue = $true }

            $signals = (Get-Lock -Site $site).Signals

            $signals.SiteLockState | Should -Be 'NoAccess'
            $signals.HasNoAccessLock | Should -BeTrue
        }
    }

    Context 'the other lock states, read from the properties of a real .NET type' {
        It 'reports a site collection with no lock as Unlock' {
            $signals = (Get-Lock -Site (New-LockSite)).Signals

            $signals.SiteLockState | Should -Be 'Unlock'
            $signals.IsLockedSite | Should -BeFalse
            $signals.HasNoAccessLock | Should -BeFalse
            $signals.CustomizationInventoryComplete | Should -BeTrue
        }

        It 'reports a NoAdditions lock as NoAdditions, locked and not blocking' {
            $signals = (Get-Lock -Site (New-LockSite @{ WriteLockedValue = $true })).Signals

            $signals.SiteLockState | Should -Be 'NoAdditions'
            $signals.IsLockedSite | Should -BeTrue
            $signals.HasNoAccessLock | Should -BeFalse
        }

        It 'reports a ReadOnly lock as ReadOnly even though SharePoint also sets the write lock' {
            $signals = (Get-Lock -Site (New-LockSite @{ ReadOnlyValue = $true; WriteLockedValue = $true })).Signals

            $signals.SiteLockState | Should -Be 'ReadOnly'
            $signals.IsLockedSite | Should -BeTrue
            $signals.HasNoAccessLock | Should -BeFalse
        }
    }

    Context 'a lock flag that cannot be read for another reason' {
        It 'leaves the state Unknown, marks the site collection partial and says why, for <Flag>' -ForEach @(
            @{ Flag = 'ReadLockedError' }
            @{ Flag = 'WriteLockedError' }
            @{ Flag = 'ReadOnlyError' }
        ) {
            $site = New-LockSite @{ $Flag = $script:AccessDenied; ErrorMessage = 'Access is denied.' }

            $lock = Get-Lock -Site $site

            $lock.Signals.SiteLockState | Should -Be 'Unknown'
            $lock.Signals.IsLockedSite | Should -BeFalse
            $lock.Signals.HasNoAccessLock | Should -BeFalse
            $lock.Signals.CustomizationInventoryComplete | Should -BeFalse
            ($lock.Warning -join ' ') | Should -Match "Could not read lock state for site collection 'https://intranet.contoso.com/sites/locked': Access is denied"
        }

        It 'does not take the error of a NoAdditions lock for a NoAccess lock' {
            $site = New-LockSite @{ WriteLockedError = $script:AdditionsBlocked; ErrorMessage = 'Additions to this Web site have been blocked.' }

            $lock = Get-Lock -Site $site

            $lock.Signals.SiteLockState | Should -Be 'Unknown'
            $lock.Signals.HasNoAccessLock | Should -BeFalse
        }

        It 'does not take a site collection for NoAccess because the rest of it cannot be read' {
            $site = New-LockSite @{ OtherError = $script:Blocked }

            $signals = (Get-Lock -Site $site).Signals

            $signals.SiteLockState | Should -Be 'Unlock'
            $signals.HasNoAccessLock | Should -BeFalse
        }
    }
}
