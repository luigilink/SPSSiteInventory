# Behavior tests for Hide-SPSTemporaryPackagePath (takes the temporary folders of the scan out of the text of the package records, which are sent).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spshide-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force
    $script:Folder = Join-Path -Path $script:Dir -ChildPath ('SPSSiteInventory-packages-' + [guid]::NewGuid().ToString('N'))
    $script:WorkRoot = Join-Path -Path $script:Dir -ChildPath 'work'
    $script:WorkName = 'spswsp-' + [guid]::NewGuid().ToString('N')

    # The records are hidden in the module, as the scan does, and come back changed.
    function Hide-Path {
        param ([object[]]$Record, [string]$Folder = $script:Folder, [string]$WorkRoot = $script:WorkRoot)
        & $script:Module {
            param ($Record, $Folder, $WorkRoot)
            Hide-SPSTemporaryPackagePath -Record $Record -Folder $Folder -WorkRoot $WorkRoot
        } $Record $Folder $WorkRoot
    }

    function New-Record {
        param ([string]$Name = 'contoso.wsp', [string]$Path = $null, [string]$Detail = '', [object[]]$Difference = @(), [object[]]$Assembly = @())
        if (-not $Path) { $Path = Join-Path $script:Folder $Name }
        [PSCustomObject]@{ PackageName = $Name; PackagePath = $Path; Source = 'Cabinet'; Status = 'Failed'; Detail = $Detail; Difference = $Difference; FeatureCount = 3; IsCustom = $true; Assemblies = $Assembly; Features = @() }
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Hide-SPSTemporaryPackagePath' {
    It 'says that a package was saved from the farm, and gives its name, instead of its temporary path' {
        $record = New-Record -Name 'contoso.intranet.wsp'

        Hide-Path -Record @($record)

        $record.PackagePath | Should -Be '(saved from the farm) contoso.intranet.wsp'
        $record.PackageName | Should -Be 'contoso.intranet.wsp'
    }

    It 'finds the folder of the scan by its name, whatever its case, and keeps the path of a package that the user gave, also in the temporary folder' {
        $saved = New-Record -Name 'a.wsp' -Path (Join-Path $script:Folder.ToUpperInvariant() 'a.wsp')
        $given = New-Record -Name 'b.wsp' -Path (Join-Path $script:Dir 'given/b.wsp')
        $other = New-Record -Name 'c.wsp' -Path (Join-Path $script:Dir 'SPSSiteInventory-reports/c.wsp')

        Hide-Path -Record @($saved, $given, $other)

        $saved.PackagePath | Should -Be '(saved from the farm) a.wsp'
        $given.PackagePath | Should -Be (Join-Path $script:Dir 'given/b.wsp')
        $other.PackagePath | Should -Be (Join-Path $script:Dir 'SPSSiteInventory-reports/c.wsp')
    }

    It 'takes the folder out of the Detail that quotes the path that could not be read, and keeps the rest of the text' {
        $path = Join-Path $script:Folder 'contoso.wsp'
        $record = New-Record -Detail ("Access to the path '{0}' is denied." -f $path)

        Hide-Path -Record @($record)

        $record.Detail | Should -Be "Access to the path '(saved from the farm)$([System.IO.Path]::DirectorySeparatorChar)contoso.wsp' is denied."
        $record.Detail | Should -Not -Match 'SPSSiteInventory-packages'
        $record.Detail | Should -Not -Match ([regex]::Escape($script:Dir))
    }

    It 'takes the folder out of every text of a record: a list of texts, and the texts of its assemblies' {
        $path = Join-Path $script:Folder 'contoso.wsp'
        $assembly = [PSCustomObject]@{ Location = 'a.dll'; Status = 'Failed'; Detail = "Could not read '$path'."; IsManaged = $false }
        $record = New-Record -Difference @("The package '$path' differs.", 'A plain text.') -Assembly @($assembly)

        Hide-Path -Record @($record)

        @($record.Difference) | Should -HaveCount 2
        $record.Difference[0] | Should -Be "The package '(saved from the farm)$([System.IO.Path]::DirectorySeparatorChar)contoso.wsp' differs."
        $record.Difference[1] | Should -Be 'A plain text.'
        $record.Assemblies[0].Detail | Should -Be "Could not read '(saved from the farm)$([System.IO.Path]::DirectorySeparatorChar)contoso.wsp'."
        $record.Assemblies[0].IsManaged | Should -BeFalse
    }

    It 'takes the work folder of the expansion out of a text, and says that it is a work folder' {
        $work = Join-Path (Join-Path $script:WorkRoot $script:WorkName) 'Contoso.dll'
        $record = New-Record -Detail ("Could not read '{0}'." -f $work)

        Hide-Path -Record @($record)

        $record.Detail | Should -Be "Could not read '(work folder)$([System.IO.Path]::DirectorySeparatorChar)Contoso.dll'."
    }

    It 'does the same for a package that the user gave: its path stays, and the work folder is gone from its text' {
        $given = New-Record -Name 'b.wsp' -Path (Join-Path $script:Dir 'given/b.wsp') -Detail ("Failed in '{0}'." -f (Join-Path $script:WorkRoot $script:WorkName))

        Hide-Path -Record @($given) -Folder ''

        $given.PackagePath | Should -Be (Join-Path $script:Dir 'given/b.wsp')
        $given.Detail | Should -Be "Failed in '(work folder)'."
    }

    It 'does not touch a folder that only looks like the work folder' -ForEach @(
        @{ Text = 'The folder spswsp-0123456789abcdef0123456789abcdef is not under the work root.' }
        @{ Text = 'spswsp-0123' }
    ) {
        $record = New-Record -Detail $Text

        Hide-Path -Record @($record)

        $record.Detail | Should -Be $Text
    }

    It 'leaves what is not text as it is, and a text that has no path' {
        $record = New-Record -Detail 'No path here.'

        Hide-Path -Record @($record)

        $record.Detail | Should -Be 'No path here.'
        $record.FeatureCount | Should -Be 3
        $record.IsCustom | Should -BeTrue
        @($record.Features) | Should -HaveCount 0
    }

    It 'goes through a record that has no PackagePath, a null and an empty list, and an empty folder, without a failure' {
        $bare = [PSCustomObject]@{ PackageName = 'x'; Detail = 'x' }

        { Hide-Path -Record @($bare, $null) } | Should -Not -Throw
        { Hide-Path -Record @() } | Should -Not -Throw
        { Hide-Path -Record $null } | Should -Not -Throw
        { Hide-Path -Record @((New-Record)) -Folder '' } | Should -Not -Throw
    }

    It 'changes the records themselves, and does not return anything' {
        $record = New-Record

        $result = Hide-Path -Record @($record)

        $result | Should -BeNullOrEmpty
        $record.PackagePath | Should -Be '(saved from the farm) contoso.wsp'
    }

    It 'hides the path that Get-SPSSolutionPackageInfo quotes in the Detail of a package that could not be read' {
        New-Item -Path $script:Folder -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:Folder 'locked.wsp'), 'a package that a virus scanner holds')
        Mock -ModuleName SPSSiteInventory.Common Expand-SPSSolutionPackage -MockWith {
            throw ("Access to the path '{0}' is denied." -f $Path)
        }

        $info = @(Get-SPSSolutionPackageInfo -Path $script:Folder -TemporaryFolder $script:WorkRoot)
        $before = $info[0].Detail
        Hide-Path -Record $info

        $before | Should -Match 'SPSSiteInventory-packages-'
        $info[0].Status | Should -Be 'Failed'
        $info[0].PackagePath | Should -Be '(saved from the farm) locked.wsp'
        $info[0].Detail | Should -Not -Match 'SPSSiteInventory-packages-'
        $info[0].Detail | Should -Not -Match ([regex]::Escape($script:Dir))
        $info[0].Detail | Should -Match 'is denied\.$'
        ($info | ConvertTo-Json -Depth 6) | Should -Not -Match ([regex]::Escape($script:Dir).Replace('\\', '\\\\'))
    }

    It 'takes a path out of a text also when it has characters that mean something in a pattern, such as a profile with parentheses' {
        $folder = 'C:\Users\Jean+Dupont (x86)\AppData\Local\Temp\SPSSiteInventory-packages-' + [guid]::NewGuid().ToString('N')
        $root = 'C:\Users\Jean+Dupont (x86)\AppData\Local\Temp'
        $work = $root + '\' + $script:WorkName
        $record = New-Record -Name 'a.wsp' -Path ($folder + '\a.wsp') -Detail ("Access to '{0}\a.wsp' is denied, and '{1}\Contoso.dll' is not readable." -f $folder, $work)

        Hide-Path -Record @($record) -Folder $folder -WorkRoot $root

        $record.Detail | Should -BeExactly "Access to '(saved from the farm)\a.wsp' is denied, and '(work folder)\Contoso.dll' is not readable."
        $record.PackagePath | Should -BeExactly '(saved from the farm) a.wsp'
    }

    It 'finds the folder when it is given with a separator at its end, and keeps the separator that the text has after it' {
        $separator = [System.IO.Path]::DirectorySeparatorChar
        $record = New-Record -Detail ("Access to '{0}{1}contoso.wsp' is denied." -f $script:Folder, $separator)
        $root = New-Record -Detail ("Failed in '{0}{1}{2}{1}Contoso.dll'." -f $script:WorkRoot, $separator, $script:WorkName)

        Hide-Path -Record @($record, $root) -Folder ($script:Folder + $separator) -WorkRoot ($script:WorkRoot + $separator)

        $record.Detail | Should -BeExactly "Access to '(saved from the farm)${separator}contoso.wsp' is denied."
        $root.Detail | Should -BeExactly "Failed in '(work folder)${separator}Contoso.dll'."
    }

    It 'finds a path in a text whatever its case, as Windows does for a path' {
        $separator = [System.IO.Path]::DirectorySeparatorChar
        $record = New-Record -Detail ("Access to '{0}{1}contoso.wsp' is denied, and '{2}{1}Contoso.dll' is not readable." -f $script:Folder.ToUpperInvariant(), $separator, (Join-Path $script:WorkRoot $script:WorkName).ToUpperInvariant())

        Hide-Path -Record @($record)

        $record.Detail | Should -BeExactly "Access to '(saved from the farm)${separator}contoso.wsp' is denied, and '(work folder)${separator}Contoso.dll' is not readable."
    }

    It 'takes the work folder out of a text with the temporary folder of the system when it is not told another, and only a folder that has 32 hexadecimal digits' {
        $separator = [System.IO.Path]::DirectorySeparatorChar
        $temporary = [System.IO.Path]::GetTempPath()
        $short = 'spswsp-' + ([guid]::NewGuid().ToString('N')).Substring(1)
        $record = New-Record -Detail ("Failed in '{0}{1}{2}Contoso.dll', not in '{0}{3}{2}Contoso.dll'." -f $temporary, $script:WorkName, $separator, $short)

        & $script:Module {
            param ($Record)
            Hide-SPSTemporaryPackagePath -Record $Record -Folder ''
        } @($record)

        $record.Detail | Should -BeExactly ("Failed in '(work folder){0}Contoso.dll', not in '{1}{2}{0}Contoso.dll'." -f $separator, $temporary, $short)
    }

    It 'does not change a text when it is not told the work root, and does not change a folder that is not the work root of the system' {
        $separator = [System.IO.Path]::DirectorySeparatorChar
        $text = "Failed in '{0}{1}{2}{1}Contoso.dll'." -f $script:Dir, $separator, $script:WorkName
        $without = New-Record -Detail $text
        $elsewhere = New-Record -Detail $text

        Hide-Path -Record @($without) -Folder '' -WorkRoot ''
        Hide-Path -Record @($elsewhere) -Folder '' -WorkRoot (Join-Path $script:Dir 'other')

        $without.Detail | Should -BeExactly $text
        $elsewhere.Detail | Should -BeExactly $text
    }

    It 'does not take a work folder out of a text when its name has fewer than 32 hexadecimal digits' {
        $separator = [System.IO.Path]::DirectorySeparatorChar
        $text = "Failed in '{0}{1}spswsp-{2}{1}Contoso.dll'." -f $script:WorkRoot, $separator, ([guid]::NewGuid().ToString('N')).Substring(1)
        $record = New-Record -Detail $text

        Hide-Path -Record @($record)

        $record.Detail | Should -BeExactly $text
    }

    It 'keeps a text a text, and not a list of one text, when it changes it' {
        $record = New-Record -Detail ("Access to '{0}' is denied." -f (Join-Path $script:Folder 'contoso.wsp'))

        Hide-Path -Record @($record)

        ($record.Detail -is [System.String]) | Should -BeTrue
        ($record.Detail -is [System.Array]) | Should -BeFalse
    }

    It 'goes through an object that a record holds, as well as a list of them' {
        $path = Join-Path $script:Folder 'contoso.wsp'
        $record = New-Record
        $record | Add-Member -NotePropertyName Manifest -NotePropertyValue ([PSCustomObject]@{ Detail = "Could not read '$path'."; Count = 2 })

        Hide-Path -Record @($record)

        $record.Manifest.Detail | Should -BeExactly "Could not read '(saved from the farm)$([System.IO.Path]::DirectorySeparatorChar)contoso.wsp'."
        $record.Manifest.Count | Should -Be 2
    }

    It 'goes down four levels of nested objects below a record, and leaves what is deeper as it is' {
        $path = Join-Path $script:Folder 'contoso.wsp'
        $deepest = [PSCustomObject]@{ Detail = "Level 6 '$path'." }
        $level = $deepest
        foreach ($depth in 5, 4, 3, 2, 1) {
            $level = [PSCustomObject]@{ Detail = "Level $depth '$path'."; Next = $level }
        }
        $record = New-Record
        $record | Add-Member -NotePropertyName Next -NotePropertyValue $level

        Hide-Path -Record @($record)

        $hidden = "'(saved from the farm)$([System.IO.Path]::DirectorySeparatorChar)contoso.wsp'."
        $record.Next.Detail | Should -BeExactly "Level 1 $hidden"
        $record.Next.Next.Detail | Should -BeExactly "Level 2 $hidden"
        $record.Next.Next.Next.Detail | Should -BeExactly "Level 3 $hidden"
        $record.Next.Next.Next.Next.Detail | Should -BeExactly "Level 4 $hidden"
        $record.Next.Next.Next.Next.Next.Detail | Should -BeExactly "Level 5 '$path'."
        $deepest.Detail | Should -BeExactly "Level 6 '$path'."
    }

    It 'changes every package that was saved from the farm, whatever their position, and none of the other ones' {
        $given = New-Record -Name 'given.wsp' -Path (Join-Path $script:Dir 'given/given.wsp')
        $first = New-Record -Name 'first.wsp'
        $second = New-Record -Name 'second.wsp'
        $third = New-Record -Name 'third.wsp'

        Hide-Path -Record @($given, $first, $second, $third)

        $given.PackagePath | Should -Be (Join-Path $script:Dir 'given/given.wsp')
        $first.PackagePath | Should -Be '(saved from the farm) first.wsp'
        $second.PackagePath | Should -Be '(saved from the farm) second.wsp'
        $third.PackagePath | Should -Be '(saved from the farm) third.wsp'
    }
}
