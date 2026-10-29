# Behavior tests for the helpers that keep the readers of a package inside it: Resolve-SPSPackagePath, Test-SPSFileSystemLink and Get-SPSPackageFile.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    $script:Module = Get-Module -Name SPSSiteInventory.Common
    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spsres-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force
    $script:OnWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)

    $script:Resolve = {
        param ([System.String] $Root, [System.String] $Base, [System.String] $Location)
        & $script:Module { param ($r, $b, $l) Resolve-SPSPackagePath -Root $r -Base $b -Location $l } $Root $Base $Location
    }
    $script:Walk = {
        param ([System.String] $Root)
        & $script:Module { param ($r) Get-SPSPackageFile -Root $r } $Root
    }
    $script:NewRoot = {
        $root = Join-Path -Path $script:Dir -ChildPath ('pkg-' + [guid]::NewGuid().ToString('N'))
        Write-TestFile -Path (Join-Path $root 'manifest.xml') -Text '<Solution />'
        Write-TestFile -Path (Join-Path $root 'Feature/Feature.xml') -Text '<Feature />'
        return $root
    }
}

AfterAll {
    Remove-TestLink
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Resolve-SPSPackagePath' {
    It 'resolves a location in the package, with either separator, relative to its base' {
        $root = & $script:NewRoot

        $first = & $script:Resolve $root $root 'Feature\Feature.xml'
        $second = & $script:Resolve $root (Join-Path $root 'Feature') 'Feature.xml'
        $third = & $script:Resolve $root $root 'Feature/Feature.xml'

        $first.Problem | Should -Be ''
        $first.Path | Should -Be (Join-Path (Join-Path $root 'Feature') 'Feature.xml')
        $second.Path | Should -Be $first.Path
        $third.Path | Should -Be $first.Path
    }

    It 'does not mind a file that does not exist: the caller says that it is missing' {
        $root = & $script:NewRoot

        $result = & $script:Resolve $root $root 'Nothing\here.xml'

        $result.Problem | Should -Be ''
        $result.Path | Should -Not -BeNullOrEmpty
    }

    It 'refuses an empty location' {
        $root = & $script:NewRoot

        (& $script:Resolve $root $root '').Problem | Should -Be 'Empty'
        (& $script:Resolve $root $root '   ').Problem | Should -Be 'Empty'
        (& $script:Resolve $root $root $null).Problem | Should -Be 'Empty'
    }

    It 'refuses a location that goes up out of the package' {
        $root = & $script:NewRoot

        $result = & $script:Resolve $root $root '..\outside.xml'

        $result.Problem | Should -Be 'Outside'
        $result.Path | Should -BeNullOrEmpty
        $result.Detail | Should -Match 'outside of the package'
    }

    It 'refuses a location that is the folder of the package itself' {
        $root = & $script:NewRoot

        (& $script:Resolve $root $root '.').Problem | Should -Be 'Outside'
    }

    It 'refuses a rooted location' {
        $root = & $script:NewRoot
        $rooted = if ($script:OnWindows) { 'C:\Windows\win.ini' } else { '/etc/hostname' }

        (& $script:Resolve $root $root $rooted).Problem | Should -Be 'Outside'
    }

    It 'tells a folder that differs only by its case from the package, except where the file system ignores the case' {
        $root = Join-Path -Path $script:Dir -ChildPath ('case-' + [guid]::NewGuid().ToString('N'))
        $package = Join-Path -Path $root -ChildPath 'package'
        Write-TestFile -Path (Join-Path $package 'manifest.xml') -Text '<Solution />'
        Write-TestFile -Path (Join-Path $root 'PACKAGE-other/Feature.xml') -Text '<Feature />'

        # '..\PACKAGE-other' is a sibling of 'package' whose name starts with the name of the package in capitals.
        $sibling = & $script:Resolve $package $package '..\PACKAGE-other\Feature.xml'
        # '..\PACKAGE\Feature.xml' is the same name as the package, with another case.
        $recased = & $script:Resolve $package $package '..\PACKAGE\manifest.xml'

        $sibling.Problem | Should -Be 'Outside'
        if ($script:OnWindows) {
            $recased.Problem | Should -Be ''
        }
        else {
            $recased.Problem | Should -Be 'Outside'
            $recased.Path | Should -BeNullOrEmpty
        }
    }

    It 'refuses a location that goes through a link, and a location that is one' {
        $root = & $script:NewRoot
        $outside = Join-Path -Path $script:Dir -ChildPath ('outside-' + [guid]::NewGuid().ToString('N'))
        Write-TestFile -Path (Join-Path $outside 'secret.xml') -Text '<Feature />'
        if (-not (New-TestLink -Path (Join-Path $root 'linked') -Target $outside)) {
            Set-ItResult -Skipped -Because 'a link cannot be created here'
            return
        }

        $through = & $script:Resolve $root $root 'linked\secret.xml'
        $itself = & $script:Resolve $root $root 'linked'

        $through.Problem | Should -Be 'Link'
        $through.Path | Should -BeNullOrEmpty
        $through.Detail | Should -Match 'goes through a link'
        $itself.Problem | Should -Be 'Link'
    }

    It 'does not check the root itself: it is the folder that the caller chose, and may be a link' {
        $real = & $script:NewRoot
        $alias = Join-Path -Path $script:Dir -ChildPath ('alias-' + [guid]::NewGuid().ToString('N'))
        if (-not (New-TestLink -Path $alias -Target $real)) {
            Set-ItResult -Skipped -Because 'a link cannot be created here'
            return
        }

        $result = & $script:Resolve $alias $alias 'Feature\Feature.xml'

        $result.Problem | Should -Be ''
        $result.Path | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test-SPSFileSystemLink' {
    It 'says that a plain file and a plain folder are not links, and that nothing is not one' {
        $root = & $script:NewRoot

        & $script:Module { param ($i) Test-SPSFileSystemLink -Item $i } (Get-Item -LiteralPath (Join-Path $root 'manifest.xml')) | Should -BeFalse
        & $script:Module { param ($i) Test-SPSFileSystemLink -Item $i } (Get-Item -LiteralPath (Join-Path $root 'Feature')) | Should -BeFalse
        & $script:Module { Test-SPSFileSystemLink -Item $null } | Should -BeFalse
    }

    It 'says that a link to a file and a link to a folder are links' {
        $root = & $script:NewRoot
        if (-not (New-TestLink -Path (Join-Path $root 'file-link') -Target (Join-Path $root 'manifest.xml'))) {
            Set-ItResult -Skipped -Because 'a link to a file cannot be created here'
            return
        }
        $null = New-TestLink -Path (Join-Path $root 'folder-link') -Target (Join-Path $root 'Feature')

        & $script:Module { param ($i) Test-SPSFileSystemLink -Item $i } (Get-Item -LiteralPath (Join-Path $root 'file-link') -Force) | Should -BeTrue
        & $script:Module { param ($i) Test-SPSFileSystemLink -Item $i } (Get-Item -LiteralPath (Join-Path $root 'folder-link') -Force) | Should -BeTrue
    }
}

Describe 'Get-SPSPackageFile' {
    It 'lists every file of the package and its subfolders' {
        $root = & $script:NewRoot
        Write-TestFile -Path (Join-Path $root 'a/b/c/deep.dll') -Text 'x'

        $result = & $script:Walk $root

        @($result.File | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @('deep.dll', 'Feature.xml', 'manifest.xml')
        $result.Link | Should -HaveCount 0
    }

    It 'lists a hidden file and a file in a hidden folder' {
        $root = & $script:NewRoot
        Write-TestFile -Path (Join-Path $root '.hidden-folder/inside.dll') -Text 'x'
        Write-TestFile -Path (Join-Path $root '.hidden.dll') -Text 'x'

        $result = & $script:Walk $root

        @($result.File | ForEach-Object { $_.Name }) | Should -Contain '.hidden.dll'
        @($result.File | ForEach-Object { $_.Name }) | Should -Contain 'inside.dll'
    }

    It 'leaves a link alone, whatever it leads to, and does not loop' {
        $root = & $script:NewRoot
        $outside = Join-Path -Path $script:Dir -ChildPath ('outside-' + [guid]::NewGuid().ToString('N'))
        Write-TestFile -Path (Join-Path $outside 'outside.dll') -Text 'x'
        if (-not (New-TestLink -Path (Join-Path $root 'to-outside') -Target $outside)) {
            Set-ItResult -Skipped -Because 'a link cannot be created here'
            return
        }
        $null = New-TestLink -Path (Join-Path $root 'Feature/loop') -Target $root

        $result = & $script:Walk $root

        @($result.File | ForEach-Object { $_.Name }) | Should -Not -Contain 'outside.dll'
        @($result.File) | Should -HaveCount 2
        @($result.Link) | Should -HaveCount 2
    }
}
