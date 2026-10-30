# Behavior tests for Resolve-SPSOutputFolder (no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    # Resolve-SPSOutputFolder is private; reach it inside the module scope.
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:ScriptRoot = Join-Path -Path $TestDrive -ChildPath 'toolkit'
    New-Item -Path $script:ScriptRoot -ItemType Directory -Force | Out-Null

    function Resolve-Folder {
        param ($OutputFolder, $ScriptRoot, [switch]$Create)
        & $script:Module {
            param ($Folder, $Root, $CreateFolder)
            Resolve-SPSOutputFolder -OutputFolder $Folder -ScriptRoot $Root -Create:$CreateFolder
        } $OutputFolder $ScriptRoot ([bool]$Create)
    }
}

Describe 'Resolve-SPSOutputFolder' {
    It 'writes the reports in a Reports folder next to the script when OutputFolder is <Case>' -ForEach @(
        @{ Case = 'empty'; Value = '' }
        @{ Case = 'missing'; Value = $null }
        @{ Case = 'blank'; Value = '   ' }
    ) {
        $result = Resolve-Folder -OutputFolder $Value -ScriptRoot $script:ScriptRoot

        $result.Path | Should -Be (Join-Path -Path $script:ScriptRoot -ChildPath 'Reports')
        $result.IsDefault | Should -BeTrue
    }

    It 'uses a folder that is set as it is, whatever the script root, so that a settings file of an earlier version behaves as before' -ForEach @(
        @{ Value = 'C:\SPSSiteInventory\Reports' }
        @{ Value = '.\Out' }
        @{ Value = 'D:\Inventory' }
    ) {
        $result = Resolve-Folder -OutputFolder $Value -ScriptRoot $script:ScriptRoot

        $result.Path | Should -Be $Value
        $result.IsDefault | Should -BeFalse
    }

    It 'puts the default in the current folder when the script root is not given, as the logs do' {
        Push-Location -Path $script:ScriptRoot
        try {
            $result = Resolve-Folder -OutputFolder '' -ScriptRoot $null
        }
        finally {
            Pop-Location
        }

        $result.Path | Should -Be (Join-Path -Path (Resolve-Path -LiteralPath $script:ScriptRoot).Path -ChildPath 'Reports')
        $result.IsDefault | Should -BeTrue
    }

    It 'puts the default in the current folder when the script root is blank' {
        Push-Location -Path $script:ScriptRoot
        try {
            $result = Resolve-Folder -OutputFolder '' -ScriptRoot '   '
        }
        finally {
            Pop-Location
        }

        $result.Path | Should -Be (Join-Path -Path (Resolve-Path -LiteralPath $script:ScriptRoot).Path -ChildPath 'Reports')
    }

    It 'neither reads nor writes anything without -Create' {
        $root = Join-Path -Path $TestDrive -ChildPath 'untouched'

        $null = Resolve-Folder -OutputFolder '' -ScriptRoot $root
        $null = Resolve-Folder -OutputFolder (Join-Path -Path $TestDrive -ChildPath 'elsewhere\Reports') -ScriptRoot $root

        Test-Path -LiteralPath $root | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $TestDrive -ChildPath 'elsewhere') | Should -BeFalse
    }

    It 'creates the default folder with -Create, and the folder that is set, with its parents' {
        $root = Join-Path -Path $TestDrive -ChildPath 'created'
        $set = Join-Path -Path $TestDrive -ChildPath 'set\deeper\Reports'

        $default = Resolve-Folder -OutputFolder '' -ScriptRoot $root -Create
        $chosen = Resolve-Folder -OutputFolder $set -ScriptRoot $root -Create

        Test-Path -LiteralPath $default.Path -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $chosen.Path -PathType Container | Should -BeTrue
        $chosen.Path | Should -Be $set
    }

    It 'leaves a folder that exists, and what it holds, alone with -Create' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'existing'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'keep.txt') -Value 'x'

        $result = Resolve-Folder -OutputFolder $folder -ScriptRoot $script:ScriptRoot -Create

        $result.Path | Should -Be $folder
        Get-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'keep.txt') | Should -Be 'x'
    }

    It 'raises an error that names the folder when it cannot be created, so that the run stops before the scan' {
        $file = Join-Path -Path $TestDrive -ChildPath 'AFile.txt'
        Set-Content -Path $file -Value 'x'

        { Resolve-Folder -OutputFolder (Join-Path -Path $file -ChildPath 'Reports') -ScriptRoot $script:ScriptRoot -Create } | Should -Throw "*The report folder '*AFile.txt*Reports' cannot be created:*"
        { Resolve-Folder -OutputFolder '' -ScriptRoot $file -Create } | Should -Throw "*The report folder '*AFile.txt*Reports' cannot be created:*"
    }

    It 'gives the reason that PowerShell gives when it cannot create the folder' {
        # A path with a null character is refused by every platform, with a message of its own.
        $bad = $TestDrive + [System.IO.Path]::DirectorySeparatorChar + 'bad' + [char]0 + 'name'
        $expected = $null
        try {
            $null = New-Item -Path $bad -ItemType Directory -Force -ErrorAction Stop
        }
        catch {
            $expected = $_.Exception.Message
        }
        if ([System.String]::IsNullOrEmpty($expected)) {
            Set-ItResult -Skipped -Because 'this platform creates a folder whose name has a null character, or says nothing'
            return
        }

        $message = $null
        try {
            $null = Resolve-Folder -OutputFolder $bad -ScriptRoot $script:ScriptRoot -Create
        }
        catch {
            $message = $_.Exception.Message
        }

        $message | Should -BeLike ('*cannot be created: ' + $expected + '*')
        $message | Should -Not -Match 'afterwards'
    }

    It 'always gives a reason when the folder cannot be created, even when PowerShell does not say why' {
        $file = Join-Path -Path $TestDrive -ChildPath 'AFile2.txt'
        Set-Content -Path $file -Value 'x'

        $message = $null
        try {
            $null = Resolve-Folder -OutputFolder (Join-Path -Path $file -ChildPath 'Reports') -ScriptRoot $script:ScriptRoot -Create
        }
        catch {
            $message = $_.Exception.Message
        }

        $message | Should -Match "cannot be created: \S"
    }
}
