# Behavior tests for Test-SPSBlockedAccessException (pure classification, no farm needed).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    function Test-Blocked {
        param ([AllowNull()][System.Exception]$Exception)
        & $script:Module { param ($Value) Test-SPSBlockedAccessException -Exception $Value } $Exception
    }

    # The HRESULTs that SharePoint returns, as the signed numbers that Exception.HResult gives.
    $script:Blocked = -2130575247       # 0x81020071, Access to this Web site has been blocked
    $script:AdditionsBlocked = -2130245274  # 0x81070966, Additions to this Web site have been blocked
    $script:AccessDenied = -2147024891  # 0x80070005, E_ACCESSDENIED
    $script:Failure = -2147467259       # 0x80004005, E_FAIL
}

Describe 'Test-SPSBlockedAccessException' {
    It 'recognizes the error of a NoAccess lock by its HRESULT, whatever the language of the message' {
        Test-Blocked -Exception ([System.Runtime.InteropServices.COMException]::new('Access to this Web site has been blocked. Please contact the administrator to resolve this problem.', $script:Blocked)) | Should -BeTrue
        Test-Blocked -Exception ([System.Runtime.InteropServices.COMException]::new("L'acces a ce site Web a ete bloque.", $script:Blocked)) | Should -BeTrue
        Test-Blocked -Exception ([System.Runtime.InteropServices.COMException]::new('', $script:Blocked)) | Should -BeTrue
    }

    It 'recognizes the English message when the HRESULT was lost' {
        Test-Blocked -Exception ([System.InvalidOperationException]::new('Access to this Web site has been blocked. Please contact the administrator.')) | Should -BeTrue
        Test-Blocked -Exception ([System.Runtime.InteropServices.COMException]::new('ACCESS TO THIS WEB SITE HAS BEEN BLOCKED', $script:Failure)) | Should -BeTrue
    }

    It 'recognizes the error under the exceptions that wrap it' {
        $inner = [System.Runtime.InteropServices.COMException]::new('inner', $script:Blocked)
        $wrapped = [System.Reflection.TargetInvocationException]::new('Exception has been thrown by the target of an invocation.', $inner)
        $twice = [System.InvalidOperationException]::new('The following exception occurred while trying to enumerate the collection', $wrapped)

        Test-Blocked -Exception $wrapped | Should -BeTrue
        Test-Blocked -Exception $twice | Should -BeTrue
    }

    It 'writes each HRESULT of the fixtures as the signed number of the code that its comment names' {
        $codes = @{
            Blocked          = '81020071'
            AdditionsBlocked = '81070966'
            AccessDenied     = '80070005'
            Failure          = '80004005'
        }
        foreach ($name in $codes.Keys) {
            $signed = [BitConverter]::ToInt32([BitConverter]::GetBytes([Convert]::ToUInt32($codes[$name], 16)), 0)
            (Get-Variable -Name $name -Scope Script -ValueOnly) | Should -Be $signed -Because "the fixture $name is 0x$($codes[$name])"
        }
    }

    It 'does not take another error for a NoAccess lock' {
        # A NoAdditions lock, an access denied, a plain failure and a message that only looks alike.
        Test-Blocked -Exception ([System.Runtime.InteropServices.COMException]::new('Additions to this Web site have been blocked. Please contact the administrator.', $script:AdditionsBlocked)) | Should -BeFalse
        Test-Blocked -Exception ([System.UnauthorizedAccessException]::new('Attempted to perform an unauthorized operation.')) | Should -BeFalse
        Test-Blocked -Exception ([System.Runtime.InteropServices.COMException]::new('Access is denied.', $script:AccessDenied)) | Should -BeFalse
        Test-Blocked -Exception ([System.InvalidOperationException]::new('The alert data could not be loaded.')) | Should -BeFalse
        Test-Blocked -Exception ([System.InvalidOperationException]::new('Access to this list has been blocked.')) | Should -BeFalse
    }

    It 'says that no exception is not the blocked error' {
        Test-Blocked -Exception $null | Should -BeFalse
    }

    It 'returns a boolean' {
        Test-Blocked -Exception ([System.Runtime.InteropServices.COMException]::new('x', $script:Blocked)) | Should -BeOfType [bool]
        Test-Blocked -Exception ([System.InvalidOperationException]::new('x')) | Should -BeOfType [bool]
    }
}
