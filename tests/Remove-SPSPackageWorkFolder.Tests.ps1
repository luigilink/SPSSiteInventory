# Behavior tests for Remove-SPSPackageWorkFolder (removes the temporary folder in which the scan saved the packages of the farm solutions).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # The folder of the scan is directly in the temporary folder of the system, so the folders of these tests are, and they are removed at the end.
    $script:Root = [System.IO.Path]::GetTempPath()
    $script:Dir = Join-Path -Path $script:Root -ChildPath ('spsremove-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force
    $script:Made = [System.Collections.Generic.List[string]]::new()

    function New-ScanName {
        'SPSSiteInventory-packages-' + [guid]::NewGuid().ToString('N')
    }

    function New-WorkFolder {
        param ([string]$Name = (New-ScanName), [string]$Parent = $script:Root)
        $path = Join-Path -Path $Parent -ChildPath $Name
        $null = New-Item -Path (Join-Path $path 'sub') -ItemType Directory -Force
        [System.IO.File]::WriteAllText((Join-Path $path 'a.wsp'), 'package')
        [System.IO.File]::WriteAllText((Join-Path $path 'sub/b.wsp'), 'package')
        $script:Made.Add($path)
        return $path
    }

    # The result and the warnings of the function, which reads the path that it is given. An error that it would write fails the test.
    function Remove-WorkFolder {
        param ([string]$Path, [switch]$WhatIf)
        & $script:Module {
            param ($Path, $WhatIf)
            $warning = @()
            if ($WhatIf) {
                $result = Remove-SPSPackageWorkFolder -Path $Path -WhatIf -WarningVariable warning -WarningAction SilentlyContinue -ErrorAction Stop
            }
            else {
                $result = Remove-SPSPackageWorkFolder -Path $Path -WarningVariable warning -WarningAction SilentlyContinue -ErrorAction Stop
            }
            [PSCustomObject]@{ Result = $result; Warning = @($warning | ForEach-Object { [string]$_ }) }
        } $Path ([bool]$WhatIf)
    }
}

AfterAll {
    Remove-TestLink
    Remove-Variable -Name SPSRemoveCount -Scope Global -ErrorAction SilentlyContinue
    foreach ($path in @($script:Made)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Remove-SPSPackageWorkFolder' {
    It 'removes the folder with its content, and returns true, without a warning' {
        $folder = New-WorkFolder

        $outcome = Remove-WorkFolder -Path $folder

        $outcome.Result | Should -BeTrue
        $outcome.Warning | Should -HaveCount 0
        Test-Path -LiteralPath $folder | Should -BeFalse
    }

    It 'returns true, and does nothing, when the folder does not exist' {
        $outcome = Remove-WorkFolder -Path (Join-Path $script:Root (New-ScanName))

        $outcome.Result | Should -BeTrue
        $outcome.Warning | Should -HaveCount 0
    }

    It 'accepts the name of the folder whatever its case, and a path that ends with a separator' {
        $upper = New-WorkFolder -Name ('SPSSITEINVENTORY-PACKAGES-' + [guid]::NewGuid().ToString('N').ToUpperInvariant())
        $slash = New-WorkFolder

        (Remove-WorkFolder -Path $upper).Result | Should -BeTrue
        (Remove-WorkFolder -Path ($slash + [System.IO.Path]::DirectorySeparatorChar)).Result | Should -BeTrue
        Test-Path -LiteralPath $upper | Should -BeFalse
        Test-Path -LiteralPath $slash | Should -BeFalse
    }

    It 'accepts the temporary folder of the system whatever its case, as Windows does for a path' {
        $upper = $script:Root.ToUpperInvariant()
        if ($upper -ceq $script:Root) {
            Set-ItResult -Skipped -Because 'the temporary folder has no letter that changes with the case'
            return
        }

        $outcome = Remove-WorkFolder -Path (Join-Path $upper (New-ScanName))

        $outcome.Result | Should -BeTrue
        $outcome.Warning | Should -HaveCount 0
    }

    It 'resolves a relative path against the current folder of PowerShell, not the one of the process' {
        $folder = New-WorkFolder
        Push-Location -LiteralPath $script:Root
        try {
            $outcome = Remove-WorkFolder -Path (Split-Path -Path $folder -Leaf)
        }
        finally {
            Pop-Location
        }

        $outcome.Result | Should -BeTrue
        $outcome.Warning | Should -HaveCount 0
        Test-Path -LiteralPath $folder | Should -BeFalse
    }

    # The names are new for each run, because the folders are in the temporary folder, which a run of these tests may share with another one.
    It 'refuses a folder whose name is not exactly the name that the scan gives, such as the reports folder, and keeps it' -ForEach @(
        @{ Name = 'Reports-' + [guid]::NewGuid().ToString('N') }
        @{ Name = 'SPSSiteInventory-reports-' + [guid]::NewGuid().ToString('N') }
        @{ Name = 'SPSSiteInventory-packages-' + [guid]::NewGuid().ToString('N').Substring(1) }
        @{ Name = 'SPSSiteInventory-packages-' + [guid]::NewGuid().ToString('N') + '0' }
        @{ Name = 'SPSSiteInventory-packages-' + [guid]::NewGuid().ToString('N').Substring(0, 31) + 'g' }
        @{ Name = 'SPSSiteInventory-packages-' + [guid]::NewGuid().ToString('N') + '-old' }
        @{ Name = 'packages-SPSSiteInventory-' + [guid]::NewGuid().ToString('N') }
        @{ Name = 'xSPSSiteInventory-packages-' + [guid]::NewGuid().ToString('N') }
    ) {
        $folder = New-WorkFolder -Name $Name

        $outcome = Remove-WorkFolder -Path $folder

        $outcome.Result | Should -BeFalse
        $outcome.Warning | Should -HaveCount 1
        $outcome.Warning[0] | Should -Match 'is not a temporary folder of the packages of the scan, so it is not removed'
        Test-Path -LiteralPath (Join-Path $folder 'sub/b.wsp') | Should -BeTrue
    }

    It 'refuses a folder that has the right name but is not directly in the temporary folder, and one that is inside such a folder, and keeps them' {
        $elsewhere = New-WorkFolder -Parent $script:Dir
        $outer = New-WorkFolder
        $inner = New-WorkFolder -Parent $outer

        foreach ($folder in @($elsewhere, $inner)) {
            $outcome = Remove-WorkFolder -Path $folder

            $outcome.Result | Should -BeFalse
            $outcome.Warning | Should -HaveCount 1
            Test-Path -LiteralPath (Join-Path $folder 'a.wsp') | Should -BeTrue
        }
        Test-Path -LiteralPath (Join-Path $outer 'a.wsp') | Should -BeTrue
    }

    It 'refuses the name of the scan without its digits, and removes nothing' {
        Mock -ModuleName SPSSiteInventory.Common Remove-Item { }

        $outcome = Remove-WorkFolder -Path (Join-Path $script:Root 'SPSSiteInventory-packages-')

        $outcome.Result | Should -BeFalse
        $outcome.Warning | Should -HaveCount 1
        $outcome.Warning[0] | Should -Match 'is not a temporary folder of the packages of the scan, so it is not removed'
        Should -Invoke Remove-Item -ModuleName SPSSiteInventory.Common -Times 0 -Exactly
    }

    It 'refuses the temporary folder itself, and the folder that holds this one' {
        foreach ($folder in @($script:Root, $script:Dir)) {
            $outcome = Remove-WorkFolder -Path $folder

            $outcome.Result | Should -BeFalse
            $outcome.Warning | Should -HaveCount 1
        }
        Test-Path -LiteralPath $script:Dir | Should -BeTrue
    }

    It 'refuses the root of a drive, and does not even try to remove it' {
        Mock -ModuleName SPSSiteInventory.Common Remove-Item { }
        $root = [System.IO.Path]::GetPathRoot($script:Dir)

        $outcome = Remove-WorkFolder -Path $root

        $outcome.Result | Should -BeFalse
        $outcome.Warning | Should -HaveCount 1
        Should -Invoke Remove-Item -ModuleName SPSSiteInventory.Common -Times 0 -Exactly
    }

    It 'refuses a link that has the right name, and leaves what the link points to' {
        $target = New-WorkFolder -Name 'target' -Parent $script:Dir
        $link = Join-Path -Path $script:Root -ChildPath (New-ScanName)
        if (-not (New-TestLink -Path $link -Target $target)) {
            Set-ItResult -Skipped -Because 'a link cannot be made here'
            return
        }

        $outcome = Remove-WorkFolder -Path $link

        $outcome.Result | Should -BeFalse
        $outcome.Warning | Should -HaveCount 1
        $outcome.Warning[0] | Should -Match 'is a link, not a folder that the scan made, so it is not removed'
        Test-Path -LiteralPath (Join-Path $target 'sub/b.wsp') | Should -BeTrue
        Test-Path -LiteralPath $link | Should -BeTrue
        Remove-TestLink
    }

    It 'removes the folder that it is given, and not its parent or its neighbours' {
        $folder = New-WorkFolder
        $neighbour = New-WorkFolder

        $null = Remove-WorkFolder -Path $folder

        Test-Path -LiteralPath $script:Dir | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $neighbour 'a.wsp') | Should -BeTrue
    }

    It 'removes nothing, and returns false, with -WhatIf' {
        $folder = New-WorkFolder

        $outcome = Remove-WorkFolder -Path $folder -WhatIf

        $outcome.Result | Should -BeFalse
        $outcome.Warning | Should -HaveCount 0
        Test-Path -LiteralPath (Join-Path $folder 'a.wsp') | Should -BeTrue
    }

    It 'tries three times, then returns false and gives the path in a warning, when the folder cannot be removed' {
        $folder = New-WorkFolder
        $script:CurrentFolder = $folder
        Mock -ModuleName SPSSiteInventory.Common Remove-Item { }
        Mock -ModuleName SPSSiteInventory.Common Start-Sleep { }

        $outcome = Remove-WorkFolder -Path $folder

        $outcome.Result | Should -BeFalse
        $outcome.Warning | Should -HaveCount 1
        $outcome.Warning[0] | Should -Be ("The temporary folder '{0}' could not be removed. It holds the packages of the farm solutions: remove it by hand." -f $folder)
        Should -Invoke Remove-Item -ModuleName SPSSiteInventory.Common -Times 3 -Exactly
        Should -Invoke Remove-Item -ModuleName SPSSiteInventory.Common -Times 3 -Exactly -ParameterFilter { $LiteralPath -eq $script:CurrentFolder -and $Recurse -and $Force -and $PesterBoundParameters.ErrorAction -eq 'SilentlyContinue' }
        Should -Invoke Start-Sleep -ModuleName SPSSiteInventory.Common -Times 3 -Exactly
        Test-Path -LiteralPath $folder | Should -BeTrue
    }

    It 'stops trying as soon as the folder is gone, and does not warn' {
        $folder = New-WorkFolder
        $global:SPSRemoveCount = 0
        Mock -ModuleName SPSSiteInventory.Common Remove-Item {
            $global:SPSRemoveCount++
            if ($global:SPSRemoveCount -ge 2) { Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse -Force }
        }
        Mock -ModuleName SPSSiteInventory.Common Start-Sleep { }

        $outcome = Remove-WorkFolder -Path $folder

        $outcome.Result | Should -BeTrue
        $outcome.Warning | Should -HaveCount 0
        Should -Invoke Remove-Item -ModuleName SPSSiteInventory.Common -Times 2 -Exactly
        Should -Invoke Start-Sleep -ModuleName SPSSiteInventory.Common -Times 1 -Exactly
        Test-Path -LiteralPath $folder | Should -BeFalse
    }
}
