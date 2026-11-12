# Behavior tests for the Solution packages section of ConvertTo-SPSInventoryHtml (pure HTML rendering, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/SolutionPackageFixture.ps1')

    $script:Site = [PSCustomObject]@{
        InventoryScope = 'SiteCollection'; Url = 'https://intranet/sites/team'; Title = 'Team'; WebApp = 'Intranet'
        AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = ''
    }

    function New-Package {
        param (
            [string]$Name = 'Contoso.Intranet', [string]$Status = 'Inspected', $IsCustom = $true, [string]$IsCustomSource = 'Assembly', $IsFullTrust = $false,
            [int]$Assemblies = 3, [int]$CustomAssemblies = 2, [int]$Features = 4, [int]$Receivers = 0, [string[]]$Frameworks = @('.NETFramework,Version=v4.8'), [int]$Legacy = 0,
            $InFarm = $null, [string]$FarmName = '', [string]$FarmMatch = '', [string[]]$Difference = @(), [string]$Detail = ''
        )
        [PSCustomObject]@{
            PackageName = $Name; Status = $Status; Detail = $Detail; IsCustom = $IsCustom; IsCustomSource = $IsCustomSource; IsFullTrustCode = $IsFullTrust
            AssemblyCount = $Assemblies; CustomAssemblyCount = $CustomAssemblies; FeatureCount = $Features; FeatureReceiverCount = $Receivers
            TargetFrameworks = $Frameworks; LegacyFrameworkAssemblyCount = $Legacy; InFarm = $InFarm; FarmSolutionName = $FarmName; FarmMatch = $FarmMatch; Difference = $Difference
        }
    }

    function New-Solution {
        param ([string]$Name)
        [PSCustomObject]@{
            SolutionName = $Name; Deployed = $true; DeploymentState = 'GlobalDeployed'; IsCustom = $true; IsFullTrustCode = $false
            ContainsCasPolicy = $false; ContainsWebApplicationResource = $false; FeatureCount = 0; FeatureScopes = @()
        }
    }

    function Get-Report {
        param ([object[]]$Package, [object[]]$Solution = @(), [hashtable]$Extra = @{})
        $parameters = @{ InputObject = @($script:Site); SolutionPackages = $Package }
        if ($Solution.Count -gt 0) { $parameters['SolutionMap'] = $Solution }
        foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
        ConvertTo-SPSInventoryHtml @parameters
    }

    function Get-Section {
        param ([string]$Html)
        [regex]::Match($Html, '(?s)<h2 id="solution-packages">.*?(?=<h2 |<div class="footer">)').Value
    }

    function Get-Row {
        param ([string]$Section)
        @([regex]::Matches($Section, '(?s)<tr><td>.*?</tr>') | ForEach-Object { $_.Value })
    }

    function Get-Cell {
        param ([string]$Row)
        @([regex]::Matches($Row, '(?s)<td[^>]*>(.*?)</td>') | ForEach-Object { $_.Groups[1].Value })
    }

    # The cells of the first row of the section. A function that returns one row gives a string, so the rows are collected first.
    function Get-FirstRowCell {
        param ([string]$Html)
        $row = @(Get-Row -Section (Get-Section -Html $Html))
        return @(Get-Cell -Row $row[0])
    }
}

Describe 'ConvertTo-SPSInventoryHtml solution packages' {
    It 'adds no section and no link when no package is given' -ForEach @(
        @{ Case = 'the parameter is left out'; Package = $null }
        @{ Case = 'an empty list'; Package = @() }
        @{ Case = 'a list that has only a null'; Package = @($null) }
    ) {
        $html = if ($null -eq $Package) { ConvertTo-SPSInventoryHtml -InputObject @($script:Site) } else { Get-Report -Package $Package }

        $html | Should -Not -Match 'solution-packages' -Because $Case
        $html | Should -Not -Match 'Solution packages'
    }

    It 'adds the section after the farm solutions, with a link in the navigation' {
        $html = Get-Report -Package @((New-Package)) -Solution @((New-Solution -Name 'Contoso.Intranet'))

        $html | Should -Match '<a href="#farm-solutions">Farm solutions</a>\s*<a href="#solution-packages">Solution packages</a>'
        $html.IndexOf('id="farm-solutions"') | Should -BeLessThan $html.IndexOf('id="solution-packages"')
        $html | Should -Match '<h2 id="solution-packages">Solution packages \(WSP files\)</h2>'
    }

    It 'adds the section, and the link, when there is no farm-solution map' {
        $html = Get-Report -Package @((New-Package))

        $html | Should -Not -Match 'id="farm-solutions"'
        $html | Should -Match '<a href="#solution-packages">Solution packages</a>'
        (Get-Section -Html $html) | Should -Not -Match 'have no inspected package'
    }

    It 'adds the section in the SharePointOnPrem mode too' {
        $html = Get-Report -Package @((New-Package)) -Extra @{ TargetMode = 'SharePointOnPrem' }

        (Get-Section -Html $html) | Should -Match '<strong>1</strong> package\(s\)'
    }

    It 'counts the packages, the custom ones, the ones with full-trust code and the ones that are not read in full' {
        $packages = @(
            (New-Package -Name 'A' -IsFullTrust $true)
            (New-Package -Name 'B')
            (New-Package -Name 'C' -Status 'Partial' -IsCustom $false -Detail 'A feature manifest is missing.')
            (New-Package -Name 'D' -Status 'Failed' -IsCustom $null -Detail 'The package is not a cabinet.')
        )

        $section = Get-Section -Html (Get-Report -Package $packages)

        $section | Should -Match '<div class="summary-total"><strong>4</strong> package\(s\) &middot; <strong>2</strong> custom &middot; <strong>1</strong> full-trust code &middot; <strong>2</strong> not read in full</div>'
        $section | Should -Match '<strong>Partial collection:</strong> 2 package\(s\) could not be read in full'
    }

    It 'does not speak of a partial collection when every package was read' {
        $section = Get-Section -Html (Get-Report -Package @((New-Package -Name 'A'), (New-Package -Name 'B')))

        $section | Should -Match '<strong>0</strong> not read in full'
        $section | Should -Not -Match 'Partial collection'
    }

    It 'lists the packages that could not be read first, then full-trust code, then custom, then the others, by name' {
        $packages = @(
            (New-Package -Name 'Contoso.Plain' -IsCustom $false)
            (New-Package -Name 'Contoso.Custom')
            (New-Package -Name 'Contoso.Partial' -Status 'Partial' -IsCustom $false)
            (New-Package -Name 'Contoso.Failed' -Status 'Failed' -IsCustom $null)
            (New-Package -Name 'Contoso.FullTrust' -IsFullTrust $true)
            (New-Package -Name 'Contoso.Another' -IsCustom $false)
        )

        $row = Get-Row -Section (Get-Section -Html (Get-Report -Package $packages))

        @($row | ForEach-Object { (Get-Cell -Row $_)[0] }) | Should -Be @('Contoso.Failed', 'Contoso.Partial', 'Contoso.FullTrust', 'Contoso.Custom', 'Contoso.Another', 'Contoso.Plain')
    }

    It 'shows what a package holds: status, custom, full-trust code, assemblies, features, framework, farm solution and differences' {
        $package = New-Package -Name 'Contoso.Intranet' -IsFullTrust $true -Assemblies 3 -CustomAssemblies 2 -Features 4 -Receivers 1 `
            -Frameworks @('.NETFramework,Version=v3.5', '.NETFramework,Version=v4.8') -Legacy 1 -InFarm $true -FarmName 'Contoso.Intranet' -FarmMatch 'SolutionId' `
            -Difference @('The farm lists 1 feature(s), the package ships 4.', 'The farm says the solution has a code access security policy: False; the package: True.')

        $cell = Get-FirstRowCell -Html (Get-Report -Package @($package))

        $cell[0] | Should -Be 'Contoso.Intranet'
        $cell[1] | Should -Be '<span class="muted">Inspected</span>'
        $cell[2] | Should -Be '<span class="pill yes">Yes</span>'
        $cell[3] | Should -Be '<span class="pill yes">Yes</span>'
        $cell[4] | Should -Be '2 / 3'
        $cell[5] | Should -Be '4 <span class="muted">(1 with a receiver)</span>'
        $cell[6] | Should -Match '^\.NETFramework,Version=v3\.5; \.NETFramework,Version=v4\.8 <span class="pill warn" title="[^"]+">1 legacy</span>$'
        $cell[7] | Should -Be 'Contoso.Intranet <span class="muted">(by SolutionId)</span>'
        $cell[8] | Should -Be 'The farm lists 1 feature(s), the package ships 4. | The farm says the solution has a code access security policy: False; the package: True.'
    }

    It 'does not mention a receiver or a legacy framework that the package does not have' {
        $cell = Get-FirstRowCell -Html (Get-Report -Package @((New-Package -Receivers 0 -Legacy 0)))

        $cell[5] | Should -Be '4'
        $cell[6] | Should -Be '.NETFramework,Version=v4.8'
    }

    It 'does not call a package that could not be read No: what it cannot say is a dash, and the reason is in the notes' {
        $package = New-Package -Name 'Broken.wsp' -Status 'Failed' -IsCustom $null -IsFullTrust $null -Assemblies 0 -CustomAssemblies 0 -Features 0 -Frameworks @() -Detail 'The path does not exist.'

        $cell = Get-FirstRowCell -Html (Get-Report -Package @($package))

        $cell[1] | Should -Be '<span class="pill yes">Failed</span>'
        foreach ($index in 2, 3, 7) { $cell[$index] | Should -Be '<span class="muted">-</span>' -Because "cell $index" }
        foreach ($index in 4, 5, 6) { $cell[$index] | Should -Be '-' -Because "cell $index" }
        $cell[8] | Should -Be 'The path does not exist.'
    }

    It 'marks a package that was read in part, and gives its reason' {
        $package = New-Package -Name 'Half.wsp' -Status 'Partial' -Detail 'A feature manifest is missing.'

        $cell = Get-FirstRowCell -Html (Get-Report -Package @($package))

        $cell[1] | Should -Be '<span class="pill warn">Partial</span>'
        $cell[8] | Should -Be 'A feature manifest is missing.'
    }

    It 'says when a package was judged on its name, because it has no assembly, and only then' -ForEach @(
        @{ Source = 'Name'; Custom = $true; Expected = '<span class="pill yes">Yes</span> <span class="muted">(by name)</span>' }
        @{ Source = 'Name'; Custom = $false; Expected = '<span class="pill no">No</span> <span class="muted">(by name)</span>' }
        @{ Source = 'Assembly'; Custom = $true; Expected = '<span class="pill yes">Yes</span>' }
        @{ Source = 'Assembly'; Custom = $false; Expected = '<span class="pill no">No</span>' }
    ) {
        $cell = Get-FirstRowCell -Html (Get-Report -Package @((New-Package -IsCustom $Custom -IsCustomSource $Source)))

        $cell[2] | Should -Be $Expected
    }

    It 'shows the farm solution that a package matches and how, that it is not in the farm, or nothing when no farm map was given' -ForEach @(
        @{ InFarm = $true; Name = 'Contoso.Intranet'; Match = 'SolutionId'; Expected = 'Contoso.Intranet <span class="muted">(by SolutionId)</span>' }
        @{ InFarm = $true; Name = 'contoso.intranet.wsp'; Match = 'FileName'; Expected = 'contoso.intranet.wsp <span class="muted">(by FileName)</span>' }
        @{ InFarm = $false; Name = ''; Match = ''; Expected = '<span class="pill no">Not in the farm</span>' }
        @{ InFarm = $null; Name = ''; Match = ''; Expected = '<span class="muted">-</span>' }
    ) {
        $cell = Get-FirstRowCell -Html (Get-Report -Package @((New-Package -InFarm $InFarm -FarmName $Name -FarmMatch $Match)))

        $cell[7] | Should -Be $Expected
    }

    It 'encodes the text of a package, which comes from files that cannot be trusted' {
        $package = New-Package -Name '<script>alert(1)</script>&Co' -InFarm $true -FarmName '"x" onmouseover=''y''' -FarmMatch '<b>' `
            -Frameworks @('<i>fw</i>') -Difference @('<img src=x onerror=alert(1)>')
        $failed = New-Package -Name 'Failed<b>' -Status 'Failed' -IsCustom $null -Detail '<script>boom()</script>'

        $section = Get-Section -Html (Get-Report -Package @($package, $failed))

        $section | Should -Not -Match '<script>'
        $section | Should -Not -Match '<img '
        $section | Should -Not -Match '<i>fw'
        $section | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;&amp;Co'
        $section | Should -Match '&quot;x&quot; onmouseover=&#39;y&#39;'
        $section | Should -Match '\(by &lt;b&gt;\)'
        $section | Should -Not -Match '<b>'
        $section | Should -Match '&lt;img src=x onerror=alert\(1\)&gt;'
        $section | Should -Match 'Failed&lt;b&gt;'
        $section | Should -Match '&lt;script&gt;boom\(\)&lt;/script&gt;'
    }

    It 'shows a status that it does not know as plain text, encoded, between the packages that failed and the ones that were read' {
        $packages = @(
            (New-Package -Name 'Contoso.Read')
            (New-Package -Name 'Contoso.Zodd' -Status '<u>odd</u>')
            (New-Package -Name 'Contoso.Failed' -Status 'Failed' -IsCustom $null)
        )

        $row = Get-Row -Section (Get-Section -Html (Get-Report -Package $packages))

        @($row | ForEach-Object { (Get-Cell -Row $_)[0] }) | Should -Be @('Contoso.Failed', 'Contoso.Zodd', 'Contoso.Read')
        (Get-Cell -Row $row[1])[1] | Should -Be '<span class="muted">&lt;u&gt;odd&lt;/u&gt;</span>'
    }

    It 'shortens a note that is too long for a cell, and says so with dots' {
        $long = 'x' * 400

        $cell = Get-FirstRowCell -Html (Get-Report -Package @((New-Package -Status 'Partial' -Detail $long)))

        $cell[8].Length | Should -Be 300
        $cell[8] | Should -Match '^x{297}\.\.\.$'
    }

    It 'names the farm solutions that no inspected package matches, once, in order' {
        $solution = @('Contoso.C', 'Contoso.A', 'Contoso.B') | ForEach-Object { New-Solution -Name $_ }
        $package = New-Package -Name 'a.wsp' -InFarm $true -FarmName 'Contoso.A' -FarmMatch 'SolutionId'

        $section = Get-Section -Html (Get-Report -Package @($package) -Solution $solution)

        $section | Should -Match '<strong>2</strong> farm solution\(s\) have no inspected package: Contoso\.B, Contoso\.C\. Save their packages'
    }

    It 'matches the name of a farm solution without looking at the case, and does not count a package that failed as a match' {
        $solution = @('Contoso.A', 'Contoso.B') | ForEach-Object { New-Solution -Name $_ }
        $matched = New-Package -Name 'a.wsp' -InFarm $true -FarmName 'CONTOSO.a' -FarmMatch 'FileName'
        $failed = New-Package -Name 'b.wsp' -Status 'Failed' -IsCustom $null -InFarm $null

        $section = Get-Section -Html (Get-Report -Package @($matched, $failed) -Solution $solution)

        $section | Should -Match '<strong>1</strong> farm solution\(s\) have no inspected package: Contoso\.B\.'
    }

    It 'says nothing about farm solutions without a package when every one has its package' {
        $solution = @('Contoso.A', 'Contoso.B') | ForEach-Object { New-Solution -Name $_ }
        $package = @(
            (New-Package -Name 'a.wsp' -InFarm $true -FarmName 'Contoso.A' -FarmMatch 'SolutionId')
            (New-Package -Name 'b.wsp' -InFarm $true -FarmName 'Contoso.B' -FarmMatch 'SolutionId')
        )

        (Get-Section -Html (Get-Report -Package $package -Solution $solution)) | Should -Not -Match 'have no inspected package'
    }

    It 'lists at most twenty farm solutions without a package and counts the others' {
        $solution = 1..25 | ForEach-Object { New-Solution -Name ('Contoso.S{0:00}' -f $_) }

        $section = Get-Section -Html (Get-Report -Package @((New-Package -InFarm $false)) -Solution $solution)

        $section | Should -Match '<strong>25</strong> farm solution\(s\) have no inspected package: Contoso\.S01, '
        $section | Should -Match 'Contoso\.S20 and 5 more\.'
        $section | Should -Not -Match 'Contoso\.S21'
    }

    It 'encodes the names of the farm solutions without a package' {
        $section = Get-Section -Html (Get-Report -Package @((New-Package)) -Solution @((New-Solution -Name '<b>Odd</b>')))

        $section | Should -Match '&lt;b&gt;Odd&lt;/b&gt;'
        $section | Should -Not -Match '<b>Odd'
    }

    It 'shows at most MaxDetailRow packages and says how many are not shown and which files hold them' {
        $packages = 1..3 | ForEach-Object { New-Package -Name ('Contoso.P{0}' -f $_) }

        $section = Get-Section -Html (Get-Report -Package $packages -Extra @{ MaxDetailRow = 2 })

        @(Get-Row -Section $section) | Should -HaveCount 2
        $section | Should -Match '<p class="muted">Showing the first 2 of 3 rows\. The solution packages CSV and JSON files hold all the rows\.</p>'
    }

    It 'shows no note about rows that are not shown when every package is shown' {
        (Get-Section -Html (Get-Report -Package @((New-Package)))) | Should -Not -Match 'Showing the first'
    }

    It 'puts the section in the entry page of a split report, and not in the table pages' {
        $site = 1..3 | ForEach-Object { [PSCustomObject]@{ InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/s$_"; Title = "s$_"; WebApp = 'Intranet'; AssessmentStatus = 'Complete'; Category = 1; CategoryName = 'Simple'; Wave = 1; WaveName = 'Quick wins'; Score = 0; Reasons = '' } }

        $pages = @(ConvertTo-SPSInventoryHtml -InputObject $site -SolutionPackages @((New-Package)) -FileName 'report.html' -SplitThreshold 1 -RowsPerPage 50)

        $pages.Count | Should -BeGreaterThan 1
        ($pages | Where-Object { $_.Kind -eq 'Entry' }).Html | Should -Match 'id="solution-packages"'
        foreach ($page in @($pages | Where-Object { $_.Kind -eq 'Sites' })) {
            $page.Html | Should -Not -Match 'id="solution-packages"'
        }
    }
}

Describe 'ConvertTo-SPSInventoryHtml solution packages, on what Get-SPSSolutionPackageInfo returns' {
    BeforeAll {
        $script:Dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('spshtmlpkg-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $script:Dir -ItemType Directory -Force
        $script:Folder = Join-Path -Path $script:Dir -ChildPath 'Contoso.Intranet'
        New-TestPackageFolder -Path $script:Folder
        $script:Map = @(
            [PSCustomObject]@{ SolutionName = 'Contoso.Intranet'; SolutionId = '6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'; Deployed = $true; DeploymentState = 'GlobalDeployed'; IsCustom = $true; ContainsGlobalAssembly = $true; ContainsCasPolicy = $false; ContainsWebApplicationResource = $false; IsFullTrustCode = $true; FeatureCount = 1; FeatureScopes = @(); FeatureIds = @() }
            [PSCustomObject]@{ SolutionName = 'Contoso.Other'; SolutionId = '99999999-0000-4000-8000-000000000009'; Deployed = $true; DeploymentState = 'GlobalDeployed'; IsCustom = $true; ContainsGlobalAssembly = $false; ContainsCasPolicy = $false; ContainsWebApplicationResource = $false; IsFullTrustCode = $false; FeatureCount = 0; FeatureScopes = @(); FeatureIds = @() }
        )
        $script:Info = @(Get-SPSSolutionPackageInfo -Path $script:Folder -FarmSolutionMap $script:Map -KnownMicrosoftPublicKeyToken $script:GenuineToken) + @(Get-SPSSolutionPackageInfo -Path (Join-Path $script:Dir 'missing.wsp'))
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:Dir) {
            Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'renders the records of a real inspection, with the fields that the inspection gives them' {
        $section = Get-Section -Html (Get-Report -Package $script:Info -Solution $script:Map)
        $row = Get-Row -Section $section

        $row | Should -HaveCount 2
        $failed = Get-Cell -Row $row[0]
        $failed[0] | Should -Be 'missing.wsp'
        $failed[1] | Should -Be '<span class="pill yes">Failed</span>'
        $failed[8] | Should -Be 'The path does not exist.'
        $read = Get-Cell -Row $row[1]
        $read[0] | Should -Be 'Contoso.Intranet'
        $read[1] | Should -Be '<span class="muted">Inspected</span>'
        $read[2] | Should -Be '<span class="pill yes">Yes</span>'
        $read[3] | Should -Be '<span class="pill yes">Yes</span>'
        $read[4] | Should -Be '2 / 3'
        $read[5] | Should -Be '2 <span class="muted">(1 with a receiver)</span>'
        $read[6] | Should -Match '\.NETFramework,Version=v3\.5.*1 legacy'
        $read[7] | Should -Be 'Contoso.Intranet <span class="muted">(by SolutionId)</span>'
        $read[8] | Should -Match '^The farm lists 1 feature\(s\), the package ships 2\.'
        $section | Should -Match '<strong>1</strong> farm solution\(s\) have no inspected package: Contoso\.Other\.'
    }
}
