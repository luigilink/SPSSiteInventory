# Export-SPSInventoryReport writes the HTML report as one file, or as an entry page and table pages for a
# farm with many site collections, and lists the pages in the manifest.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-Site {
        param ([string]$Name, [int]$Category, [string]$CategoryName)
        [PSCustomObject]@{
            InventoryScope = 'SiteCollection'; Url = "https://intranet/sites/$Name"; Title = $Name; WebApp = 'Intranet'
            AssessmentStatus = 'Complete'; Category = $Category; CategoryName = $CategoryName; Score = 0
            Wave = $Category; WaveName = "Wave $Category"; SizeGB = 0.5; Template = 'STS#0'; Reasons = ''
        }
    }

    $script:Small = @((New-Site -Name 'a' -Category 1 -CategoryName 'Simple'), (New-Site -Name 'b' -Category 2 -CategoryName 'Moderate'))
    $script:Large = @(
        foreach ($index in 0..119) { New-Site -Name ('s{0:000}' -f $index) -Category 1 -CategoryName 'Simple' }
        foreach ($index in 0..1) { New-Site -Name ('m{0}' -f $index) -Category 2 -CategoryName 'Moderate' }
    )

    function Get-Manifest {
        param ([string]$Path)
        Get-Content -Path $Path -Raw | ConvertFrom-Json
    }
}

Describe 'Export-SPSInventoryReport HTML pages' {
    It 'writes one HTML file, and lists no page, for a farm that is not above the threshold' {
        $folder = Join-Path $TestDrive 'small'

        $output = Export-SPSInventoryReport -InputObject $script:Small -OutputFolder $folder -BaseName 'One'

        @($output.HtmlPagePaths) | Should -HaveCount 0
        @(Get-ChildItem -Path $folder -Filter '*.html') | Should -HaveCount 1
        (Get-ChildItem -Path $folder -Filter '*.html').FullName | Should -Be $output.HtmlPath
        (Get-Content -Path $output.HtmlPath -Raw) | Should -Match '<table id="inv">'
        $manifest = Get-Manifest -Path $output.ManifestJsonPath
        $manifest.Files.InventoryHtml | Should -Be $output.HtmlPath
        @($manifest.Files.InventoryHtmlPages | Where-Object { $_ }) | Should -HaveCount 0
    }

    It 'writes an entry page, named as the single file, and the table pages in the same folder above the threshold, and lists them in the manifest' {
        $folder = Join-Path $TestDrive 'large'

        $output = Export-SPSInventoryReport -InputObject $script:Large -OutputFolder $folder -BaseName 'Many' -HtmlSplitThreshold 100 -HtmlRowsPerPage 50

        $entryName = Split-Path -Path $output.HtmlPath -Leaf
        $entryName | Should -Match '^Many-\d{8}-\d{4}\.html$'
        @($output.HtmlPagePaths) | Should -HaveCount 4
        $base = [System.IO.Path]::GetFileNameWithoutExtension($entryName)
        @($output.HtmlPagePaths | ForEach-Object { Split-Path -Path $_ -Leaf }) | Should -Be @(
            "$base-sites-moderate-1.html", "$base-sites-simple-1.html", "$base-sites-simple-2.html", "$base-sites-simple-3.html"
        )
        foreach ($path in @($output.HtmlPath) + @($output.HtmlPagePaths)) {
            (Split-Path -Path $path -Parent) | Should -Be $folder
            Test-Path -Path $path -PathType Leaf | Should -BeTrue
            (Get-Content -Path $path -Raw) | Should -Match '^\s*<!DOCTYPE html>'
        }
        (Get-Content -Path $output.HtmlPath -Raw) | Should -Not -Match '<table id="inv">'
        $manifest = Get-Manifest -Path $output.ManifestJsonPath
        $manifest.Files.InventoryHtml | Should -Be $output.HtmlPath
        @($manifest.Files.InventoryHtmlPages) | Should -Be @($output.HtmlPagePaths)
    }

    It 'links the pages with names that resolve in the folder, so that it can be moved' {
        $folder = Join-Path $TestDrive 'moved'
        $output = Export-SPSInventoryReport -InputObject $script:Large -OutputFolder $folder -BaseName 'Move' -HtmlSplitThreshold 100 -HtmlRowsPerPage 50
        $elsewhere = Join-Path $TestDrive 'elsewhere'
        $null = New-Item -Path $elsewhere -ItemType Directory
        Get-ChildItem -Path $folder -Filter '*.html' | Copy-Item -Destination $elsewhere

        $names = @(Get-ChildItem -Path $elsewhere -Filter '*.html' | ForEach-Object { $_.Name })
        $names | Should -HaveCount 5
        foreach ($name in $names) {
            $html = Get-Content -Path (Join-Path $elsewhere $name) -Raw
            foreach ($link in @([regex]::Matches($html, 'href="([^"#]+)') | ForEach-Object { $_.Groups[1].Value })) {
                if ($link.StartsWith('https://')) { continue }
                $names | Should -Contain ([System.Uri]::UnescapeDataString($link)) -Because "$name links to $link"
            }
        }
    }

    It 'rejects a page size or a threshold out of range' {
        { Export-SPSInventoryReport -InputObject $script:Small -OutputFolder (Join-Path $TestDrive 'bad') -HtmlRowsPerPage 10 } | Should -Throw
        { Export-SPSInventoryReport -InputObject $script:Small -OutputFolder (Join-Path $TestDrive 'bad') -HtmlSplitThreshold -1 } | Should -Throw
    }
}
