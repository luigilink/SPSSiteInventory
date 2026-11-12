# Behavior tests for Save-SPSFarmSolutionPackage (saves the package of each farm solution in a folder). The farm solutions are
# stand-ins, compiled classes with the members that SharePoint gives them (Name, SolutionFile.SaveAs), so that no farm is needed.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # SaveAs copies a file, as SharePoint writes the file of the solution. It refuses a path that is not full, as the .NET method does
    # not read it from the location of PowerShell, and it refuses to replace a file, so that a test sees a package that is overwritten.
    if (-not ('SPSTestSolutionFile' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
public class SPSTestSolutionFile
{
    public string Source { get; set; }
    public string FailWith { get; set; }
    public bool LeavePartial { get; set; }
    public bool WriteNothing { get; set; }
    public void SaveAs(string filename)
    {
        if (!Path.IsPathRooted(filename))
        {
            throw new ArgumentException("SaveAs got a path that is not full: " + filename);
        }
        if (FailWith != null)
        {
            if (LeavePartial)
            {
                File.WriteAllText(filename, "partial");
            }
            throw new InvalidOperationException(FailWith);
        }
        if (WriteNothing)
        {
            return;
        }
        File.Copy(Source, filename, false);
    }
}
public class SPSTestFarmSolution
{
    public string Name { get; set; }
    public SPSTestSolutionFile SolutionFile { get; set; }
}
'@
    }

    $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spssave-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:Dir -ItemType Directory -Force

    function New-Solution {
        param ([string]$Name, [string]$Content = 'the package', [string]$FailWith = '', [switch]$LeavePartial, [switch]$WriteNothing, [switch]$NoFile)
        $source = Join-Path -Path $script:Dir -ChildPath ('source-' + [guid]::NewGuid().ToString('N') + '.bin')
        [System.IO.File]::WriteAllText($source, $Content)
        $solution = [SPSTestFarmSolution]::new()
        $solution.Name = $Name
        if (-not $NoFile) {
            $file = [SPSTestSolutionFile]::new()
            $file.Source = $source
            # A string parameter is never null in PowerShell: the stand-in only fails when it is given a reason.
            if ($FailWith) { $file.FailWith = $FailWith }
            $file.LeavePartial = [bool]$LeavePartial
            $file.WriteNothing = [bool]$WriteNothing
            $solution.SolutionFile = $file
        }
        return $solution
    }

    function Save-Package {
        param ([string]$Path, [object[]]$Solution, [switch]$FromFarm)
        & $script:Module {
            param ($Path, $Solution, $FromFarm)
            if ($FromFarm) { Save-SPSFarmSolutionPackage -Path $Path } else { Save-SPSFarmSolutionPackage -Path $Path -Solution $Solution }
        } $Path $Solution ([bool]$FromFarm)
    }

    # The names of the files of a folder, a name that starts with a dot included (Unix hides it), in ordinal order: Sort-Object follows the culture.
    function Get-Saved {
        param ([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return @() }
        $name = [string[]]@(Get-ChildItem -LiteralPath $Path -File -Force | ForEach-Object { $_.Name })
        [System.Array]::Sort($name, [System.StringComparer]::Ordinal)
        return $name
    }

    # The solutions that Get-SPSolution gives, and a failure of that command. It fails as a cmdlet does, with a non-terminating error that
    # only -ErrorAction Stop turns into an exception, which is what the function relies on.
    function global:Get-SPSolution {
        [CmdletBinding()]
        param ()
        if ($global:SPSTestFarmFails) {
            Write-Error -Message 'The configuration database cannot be read.'
            return
        }
        $global:SPSTestFarmSolutions
    }

    # The stub of the expansion runs in the scope of the module: it reads the folder to return from a global variable.
    $script:Expanded = Join-Path -Path $script:Dir -ChildPath 'Contoso.Intranet'
    New-TestPackageFolder -Path $script:Expanded
}

AfterAll {
    Remove-Item -Path Function:\Get-SPSolution -ErrorAction SilentlyContinue
    Remove-Variable -Name SPSTestFarmFails, SPSTestFarmSolutions, SPSStubFolder -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:Dir) {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Save-SPSFarmSolutionPackage' {
    BeforeEach {
        $script:Out = Join-Path -Path $script:Dir -ChildPath ('out-' + [guid]::NewGuid().ToString('N'))
        $global:SPSTestFarmFails = $false
        $global:SPSTestFarmSolutions = @()
    }

    It 'saves the package of each solution in the folder, under the name of the solution, and says how many' {
        $result = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'contoso.intranet.wsp' -Content 'one'), (New-Solution -Name 'contoso.hr.wsp' -Content 'two'))

        $result.Requested | Should -Be 2
        $result.Saved | Should -Be 2
        @($result.Failure) | Should -HaveCount 0
        Get-Saved $script:Out | Should -Be @('contoso.hr.wsp', 'contoso.intranet.wsp')
        Get-Content -LiteralPath (Join-Path $script:Out 'contoso.intranet.wsp') -Raw | Should -Be 'one'
        Get-Content -LiteralPath (Join-Path $script:Out 'contoso.hr.wsp') -Raw | Should -Be 'two'
    }

    It 'creates the folder, and the folders above it, when they are missing' {
        $deep = Join-Path -Path $script:Out -ChildPath 'one/two'

        $null = Save-Package -Path $deep -Solution @((New-Solution -Name 'a.wsp'))

        Get-Saved $deep | Should -Be @('a.wsp')
    }

    It 'returns the path of the folder' {
        (Save-Package -Path $script:Out -Solution @((New-Solution -Name 'a.wsp'))).Path | Should -Be $script:Out
    }

    It 'gives SaveAs a full path, and returns the full path of the folder, when the folder is relative' {
        Push-Location -LiteralPath $script:Dir
        try {
            $relative = 'relative-' + [guid]::NewGuid().ToString('N')
            $result = Save-Package -Path $relative -Solution @((New-Solution -Name 'a.wsp'))
        }
        finally {
            Pop-Location
        }

        $result.Saved | Should -Be 1
        [System.IO.Path]::IsPathRooted($result.Path) | Should -BeTrue
        $result.Path | Should -Be (Join-Path $script:Dir $relative)
        Get-Saved $result.Path | Should -Be @('a.wsp')
    }

    It 'creates nothing, and saves nothing, when there is no solution' -ForEach @(
        @{ Case = 'an empty list'; Given = @() }
        @{ Case = 'a null'; Given = $null }
        @{ Case = 'a list that has only a null'; Given = @($null) }
    ) {
        # The farm has solutions: a farm that is read instead of the list that was given would save them.
        $global:SPSTestFarmSolutions = @((New-Solution -Name 'farm.wsp'))

        $result = Save-Package -Path $script:Out -Solution $Given

        $result.Requested | Should -Be 0
        $result.Saved | Should -Be 0
        @($result.Failure) | Should -HaveCount 0
        Test-Path -LiteralPath $script:Out | Should -BeFalse -Because $Case
    }

    It 'adds .wsp to a name that does not end with it, and keeps one that does, whatever its case' {
        $null = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'noextension'), (New-Solution -Name 'Upper.WSP'), (New-Solution -Name 'contoso.wsp.bak'))

        Get-Saved $script:Out | Should -BeExactly @('Upper.WSP', 'contoso.wsp.bak.wsp', 'noextension.wsp')
    }

    It 'replaces the characters that a file name cannot hold, and never writes outside the folder' {
        $out = Join-Path -Path $script:Out -ChildPath 'inner'
        $names = @('..\..\evil.wsp', '../../evil2.wsp', 'a/b.wsp', 'what?.wsp', 'c:x.wsp', 'p|q<r>s.wsp', 'quote"d.wsp', 'star*.wsp')

        $result = Save-Package -Path $out -Solution @($names | ForEach-Object { New-Solution -Name $_ })

        $result.Saved | Should -Be $names.Count
        @($result.Failure) | Should -HaveCount 0
        Get-Saved $out | Should -BeExactly @('.._.._evil.wsp', '.._.._evil2.wsp', 'a_b.wsp', 'c_x.wsp', 'p_q_r_s.wsp', 'quote_d.wsp', 'star_.wsp', 'what_.wsp')
        Get-Saved $script:Out | Should -HaveCount 0
        Get-Saved $script:Dir | Where-Object { $_ -like 'evil*' } | Should -HaveCount 0
    }

    It 'trims a name, and falls back on solution.wsp when nothing is left of it' {
        $null = Save-Package -Path $script:Out -Solution @((New-Solution -Name '  spaced name.wsp  '), (New-Solution -Name '...'), (New-Solution -Name ''))

        Get-Saved $script:Out | Should -BeExactly @('solution-2.wsp', 'solution.wsp', 'spaced name.wsp')
    }

    It 'does not replace a package, and numbers the one whose name is taken' {
        $result = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'a/b.wsp' -Content 'first'), (New-Solution -Name 'a\b.wsp' -Content 'second'), (New-Solution -Name 'a:b.wsp' -Content 'third'))

        $result.Saved | Should -Be 3
        Get-Saved $script:Out | Should -BeExactly @('a_b-2.wsp', 'a_b-3.wsp', 'a_b.wsp')
        Get-Content -LiteralPath (Join-Path $script:Out 'a_b.wsp') -Raw | Should -Be 'first'
        Get-Content -LiteralPath (Join-Path $script:Out 'a_b-2.wsp') -Raw | Should -Be 'second'
        Get-Content -LiteralPath (Join-Path $script:Out 'a_b-3.wsp') -Raw | Should -Be 'third'
    }

    It 'does not replace a file that was in the folder before' {
        $null = New-Item -Path $script:Out -ItemType Directory -Force
        [System.IO.File]::WriteAllText((Join-Path $script:Out 'a.wsp'), 'old')

        $result = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'a.wsp' -Content 'new'))

        $result.Saved | Should -Be 1
        Get-Content -LiteralPath (Join-Path $script:Out 'a.wsp') -Raw | Should -Be 'old'
        Get-Content -LiteralPath (Join-Path $script:Out 'a-2.wsp') -Raw | Should -Be 'new'
    }

    It 'lists a package that cannot be saved, with the reason, and goes on with the others' {
        $result = Save-Package -Path $script:Out -Solution @(
            (New-Solution -Name 'first.wsp')
            (New-Solution -Name 'broken.wsp' -FailWith 'The configuration database cannot be read.')
            (New-Solution -Name 'last.wsp')
        )

        $result.Requested | Should -Be 3
        $result.Saved | Should -Be 2
        @($result.Failure) | Should -HaveCount 1
        $result.Failure[0].Name | Should -Be 'broken.wsp'
        $result.Failure[0].Reason | Should -Be 'The configuration database cannot be read.'
        Get-Saved $script:Out | Should -Be @('first.wsp', 'last.wsp')
    }

    It 'removes the partial file that a failed save leaves, and only that file' {
        $null = New-Item -Path $script:Out -ItemType Directory -Force
        [System.IO.File]::WriteAllText((Join-Path $script:Out 'broken.wsp'), 'kept')

        $result = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'broken.wsp' -FailWith 'disk full' -LeavePartial))

        $result.Saved | Should -Be 0
        $result.Failure[0].Reason | Should -Be 'disk full'
        Get-Saved $script:Out | Should -Be @('broken.wsp')
        Get-Content -LiteralPath (Join-Path $script:Out 'broken.wsp') -Raw | Should -Be 'kept'
    }

    It 'lists a solution that has no package file' {
        $result = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'nofile.wsp' -NoFile), (New-Solution -Name 'ok.wsp'))

        $result.Saved | Should -Be 1
        $result.Failure[0].Name | Should -Be 'nofile.wsp'
        $result.Failure[0].Reason | Should -Be 'The solution has no package file.'
    }

    It 'lists a save that returned without writing the file, and does not count it' {
        $result = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'nothing.wsp' -WriteNothing))

        $result.Saved | Should -Be 0
        $result.Failure[0].Reason | Should -Be 'The package file was not written.'
    }

    It 'ignores a null in the list of solutions' {
        $result = Save-Package -Path $script:Out -Solution @($null, (New-Solution -Name 'a.wsp'), $null)

        $result.Requested | Should -Be 1
        $result.Saved | Should -Be 1
    }

    It 'reads the solutions of the farm with Get-SPSolution when none is given' {
        $global:SPSTestFarmSolutions = @((New-Solution -Name 'farm.one.wsp'), (New-Solution -Name 'farm.two.wsp'))

        $result = Save-Package -Path $script:Out -FromFarm

        $result.Saved | Should -Be 2
        Get-Saved $script:Out | Should -Be @('farm.one.wsp', 'farm.two.wsp')
    }

    It 'does not read the farm when the solutions are given' {
        $global:SPSTestFarmFails = $true

        $result = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'a.wsp'))

        $result.Saved | Should -Be 1
    }

    It 'throws, and creates nothing, when the solutions of the farm cannot be read' {
        $global:SPSTestFarmFails = $true

        { Save-Package -Path $script:Out -FromFarm } | Should -Throw '*configuration database*'

        Test-Path -LiteralPath $script:Out | Should -BeFalse
    }

    It 'throws once, and does not blame every solution, when the folder cannot be created' {
        $blocked = Join-Path -Path $script:Dir -ChildPath ('a-file-' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($blocked, 'not a folder')

        { Save-Package -Path (Join-Path $blocked 'inside') -Solution @((New-Solution -Name 'a.wsp'), (New-Solution -Name 'b.wsp')) } | Should -Throw
    }

    It 'gives the message of the error of SaveAs as the reason, not the text that PowerShell puts around it' {
        $result = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'broken.wsp' -FailWith 'Access to the path is denied.'))

        $result.Failure[0].Reason | Should -BeExactly 'Access to the path is denied.'
        $result.Failure[0].Reason | Should -Not -Match 'Exception calling'
    }

    It 'fills a folder that Get-SPSSolutionPackageInfo reads, one package for each file that it saved' {
        $null = Save-Package -Path $script:Out -Solution @((New-Solution -Name 'Contoso.Intranet.wsp'), (New-Solution -Name 'noextension'))
        $global:SPSStubFolder = $script:Expanded
        Mock -ModuleName SPSSiteInventory.Common Expand-SPSSolutionPackage -MockWith {
            $null = New-Item -Path $WorkFolder -ItemType Directory -Force
            [PSCustomObject]@{ Path = $global:SPSStubFolder; FileCount = 9; DeclaredBytes = 1 }
        }

        $info = @(Get-SPSSolutionPackageInfo -Path $script:Out -TemporaryFolder $script:Dir)

        @($info | ForEach-Object { $_.PackageName } | Sort-Object) | Should -Be @('Contoso.Intranet.wsp', 'noextension.wsp')
        @($info | ForEach-Object { $_.Source } | Sort-Object -Unique) | Should -Be @('Cabinet')
    }
}
