# Behavior tests for Get-SPSCabinetEntry (reads the table of files of a cabinet, extracts nothing).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spscab-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force

    $script:Entry = {
        param ([System.String] $Path)
        & $script:Module { param ($p) Get-SPSCabinetEntry -Path $p } $Path
    }
    $script:Save = {
        param ([System.Byte[]] $Byte)
        $path = Join-Path -Path $script:Dir -ChildPath ([guid]::NewGuid().ToString('N') + '.cab')
        [System.IO.File]::WriteAllBytes($path, $Byte)
        return $path
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-SPSCabinetEntry' {
    It 'lists the name and the declared size of every file of a cabinet' {
        $path = & $script:Save (New-TestCabinetBytes -File @(
                @{ Name = 'manifest.xml'; Content = [System.Text.Encoding]::UTF8.GetBytes('<Solution />') }
                @{ Name = 'FeatureA\Feature.xml'; Content = [System.Byte[]](1, 2, 3, 4, 5) }
            ))

        $entry = @(& $script:Entry $path)

        $entry | Should -HaveCount 2
        $entry[0].Name | Should -Be 'manifest.xml'
        $entry[0].Size | Should -Be 12
        $entry[1].Name | Should -Be 'FeatureA\Feature.xml'
        $entry[1].Size | Should -Be 5
        @($entry | Where-Object { -not $_.Safe }) | Should -HaveCount 0
    }

    It 'reads a name that is flagged as UTF-8 as UTF-8' {
        $path = & $script:Save (New-TestCabinetBytes -File @(
                @{ Name = ([System.String]([char]0xE9) + 'l' + [char]0xE9 + 'ment.xml'); Content = [System.Byte[]](1); Utf8 = $true }
            ))

        @(& $script:Entry $path)[0].Name | Should -Be ([System.String]([char]0xE9) + 'l' + [char]0xE9 + 'ment.xml')
    }

    It 'says that <Name> is safe: <Safe>' -ForEach @(
        @{ Name = 'manifest.xml'; Safe = $true }
        @{ Name = 'FeatureA\Feature.xml'; Safe = $true }
        @{ Name = 'Feature A/Feature (1).xml'; Safe = $true }
        @{ Name = '..hidden\file.txt'; Safe = $true }
        @{ Name = '..\evil.txt'; Safe = $false }
        @{ Name = 'a\..\..\evil.txt'; Safe = $false }
        @{ Name = 'a/../../evil.txt'; Safe = $false }
        @{ Name = '\evil.txt'; Safe = $false }
        @{ Name = '/etc/passwd'; Safe = $false }
        @{ Name = 'C:\Windows\evil.txt'; Safe = $false }
        @{ Name = 'file.txt:stream'; Safe = $false }
        @{ Name = 'bad*name.txt'; Safe = $false }
        @{ Name = 'bad|name.txt'; Safe = $false }
        @{ Name = "tab`there.txt"; Safe = $false }
    ) {
        $path = & $script:Save (New-TestCabinetBytes -File @(@{ Name = $Name; Content = [System.Byte[]](1) }))

        $entry = @(& $script:Entry $path)[0]

        $entry.Safe | Should -Be $Safe
        if (-not $Safe) {
            $entry.Problem | Should -Not -BeNullOrEmpty
        }
    }

    It 'throws for a file that is not a cabinet' {
        $path = & $script:Save ([System.Text.Encoding]::ASCII.GetBytes('This is not a cabinet, only a text file that is long enough to have a header.'))

        { & $script:Entry $path } | Should -Throw '*not a cabinet*'
    }

    It 'throws for a file that is too short' {
        $path = & $script:Save ([System.Byte[]](0x4D, 0x53, 0x43, 0x46, 0, 0, 0, 0))

        { & $script:Entry $path } | Should -Throw '*too short*'
    }

    It 'throws for a cabinet that is a part of a set of cabinets' {
        $path = & $script:Save (New-TestCabinetBytes -File @(@{ Name = 'a.xml'; Content = [System.Byte[]](1) }) -Flags 2)

        { & $script:Entry $path } | Should -Throw '*set of cabinets*'
    }

    It 'throws for a cabinet version that is not supported' {
        $path = & $script:Save (New-TestCabinetBytes -File @(@{ Name = 'a.xml'; Content = [System.Byte[]](1) }) -MajorVersion 2)

        { & $script:Entry $path } | Should -Throw '*version*'
    }

    It 'throws for a table of files that is cut short' {
        $bytes = New-TestCabinetBytes -File @(
            @{ Name = 'first.xml'; Content = [System.Byte[]](1) }
            @{ Name = 'second-file-with-a-long-name.xml'; Content = [System.Byte[]](2) }
        )
        $cut = [System.Byte[]]$bytes[0..70]
        $path = & $script:Save $cut

        { & $script:Entry $path } | Should -Throw '*cut short*'
    }

    It 'throws for a table of files that is outside of the file' {
        $bytes = New-TestCabinetBytes -File @(@{ Name = 'a.xml'; Content = [System.Byte[]](1) })
        [System.BitConverter]::GetBytes([System.UInt32]100000).CopyTo($bytes, 16)
        $path = & $script:Save $bytes

        { & $script:Entry $path } | Should -Throw '*outside of the file*'
    }

    It 'lists the files of a cabinet that a real tool built' {
        $source = Join-Path -Path $script:Dir -ChildPath 'source'
        New-TestPackageFolder -Path $source
        $path = Join-Path -Path $script:Dir -ChildPath 'real.wsp'
        if (-not (New-TestCabinet -SourceFolder $source -Path $path)) {
            Set-ItResult -Skipped -Because 'no tool to build a cabinet (makecab or gcab) is available'
            return
        }

        $entry = @(& $script:Entry $path)

        $entry | Should -HaveCount 9
        $name = @($entry | ForEach-Object { $_.Name -replace '/', '\' })
        $name | Should -Contain 'manifest.xml'
        $name | Should -Contain 'FeatureWebParts\Feature.xml'
        $name | Should -Contain 'TEMPLATE\page.aspx'
        @($entry | Where-Object { -not $_.Safe }) | Should -HaveCount 0
        ($entry | Where-Object { $_.Name -eq 'Contoso.Fixture.Custom.dll' }).Size | Should -Be (Get-Item (Join-Path $source 'Contoso.Fixture.Custom.dll')).Length
    }
}
