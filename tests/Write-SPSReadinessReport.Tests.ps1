BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function New-Check {
        param
        (
            [System.String] $Section,
            [System.String] $Name,
            [System.String] $Status,
            [System.String] $Detail = ''
        )

        return [PSCustomObject]@{ Section = $Section; Name = $Name; Status = $Status; Detail = $Detail; IsBlocking = ($Status -eq 'Error') }
    }

    # Write-Host goes to the information stream: read the text and the color of every line.
    function Invoke-Report {
        param ([System.Object[]] $Check)

        $output = @(Write-SPSReadinessReport -Check $Check 6>&1)
        $records = @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
        return [PSCustomObject]@{
            Lines   = @($records | ForEach-Object { [PSCustomObject]@{ Text = [System.String]$_.MessageData.Message; Color = [System.String]$_.MessageData.ForegroundColor } })
            Summary = @($output | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })[0]
        }
    }

    function Get-Line {
        param
        (
            [System.Object[]] $Line,
            [System.String] $Pattern
        )

        return @($Line | Where-Object { $_.Text -match $Pattern })
    }
}

Describe 'Write-SPSReadinessReport' {
    BeforeAll {
        $script:Checks = @(
            New-Check -Section 'PowerShell' -Name 'Windows PowerShell 5.1' -Status 'OK' -Detail 'Version 5.1.14393.6343'
            New-Check -Section 'PowerShell' -Name 'Elevated session' -Status 'Error' -Detail 'The session is not elevated.'
            New-Check -Section 'SharePoint' -Name 'Farm administrator' -Status 'Warning' -Detail 'Not a farm administrator.'
            New-Check -Section 'SharePoint' -Name 'Web applications' -Status 'Skipped' -Detail 'The farm cannot be reached.'
            New-Check -Section 'SharePoint' -Name 'Nothing to add' -Status 'OK'
        )
        $script:Report = Invoke-Report -Check $script:Checks
    }

    It 'gives each status its own mark and color' {
        $ok = Get-Line -Line $script:Report.Lines -Pattern '^\[ OK \]  Windows PowerShell 5\.1'
        $ok.Text | Should -Be '[ OK ]  Windows PowerShell 5.1 - Version 5.1.14393.6343'
        $ok.Color | Should -Be 'Green'

        $warning = Get-Line -Line $script:Report.Lines -Pattern '^\[WARN\]'
        $warning.Text | Should -Be '[WARN]  Farm administrator - Not a farm administrator.'
        $warning.Color | Should -Be 'Yellow'

        $failure = Get-Line -Line $script:Report.Lines -Pattern '^\[ERR \]'
        $failure.Text | Should -Be '[ERR ]  Elevated session - The session is not elevated.'
        $failure.Color | Should -Be 'Red'

        $skipped = Get-Line -Line $script:Report.Lines -Pattern '^\[SKIP\]'
        $skipped.Text | Should -Be '[SKIP]  Web applications - The farm cannot be reached.'
        $skipped.Color | Should -Be 'DarkGray'
    }

    It 'writes the name alone when a check has no detail' {
        $line = Get-Line -Line $script:Report.Lines -Pattern 'Nothing to add'

        $line.Text | Should -Be '[ OK ]  Nothing to add'
    }

    It 'writes one heading per section, in the order of the checks' {
        $headings = @($script:Report.Lines | Where-Object { $_.Text -match '^== .* ==$' } | ForEach-Object { $_.Text })

        $headings | Should -Be @('== PowerShell ==', '== SharePoint ==')
    }

    It 'writes the checks under the heading of their section' {
        $texts = @($script:Report.Lines | ForEach-Object { $_.Text })

        $texts.IndexOf('== PowerShell ==') | Should -BeLessThan $texts.IndexOf('[ OK ]  Windows PowerShell 5.1 - Version 5.1.14393.6343')
        $texts.IndexOf('[ERR ]  Elevated session - The session is not elevated.') | Should -BeLessThan $texts.IndexOf('== SharePoint ==')
        $texts.IndexOf('== SharePoint ==') | Should -BeLessThan $texts.IndexOf('[WARN]  Farm administrator - Not a farm administrator.')
    }

    It 'opens with a banner and ends with the number of checks per status' {
        $script:Report.Lines[1].Text | Should -Be ('=' * 60)
        $script:Report.Lines[2].Text | Should -Be ' SPSSiteInventory - Readiness Check'
        (Get-Line -Line $script:Report.Lines -Pattern 'Computer :') | Should -Not -BeNullOrEmpty
        (Get-Line -Line $script:Report.Lines -Pattern 'Date     :') | Should -Not -BeNullOrEmpty
        (Get-Line -Line $script:Report.Lines -Pattern 'Summary : ').Text | Should -Be ' Summary : 2 OK, 1 warning(s), 1 error(s), 1 skipped'
    }

    It 'says that the scan cannot run when there is an error, and that a warning does not block it' {
        $verdict = Get-Line -Line $script:Report.Lines -Pattern '^ Not ready'

        $verdict.Text | Should -Match 'fix the error\(s\) above'
        $verdict.Text | Should -Match 'Warnings do not block the scan'
        $verdict.Color | Should -Be 'Red'
    }

    It 'returns the counts, IsReady and the checks' {
        $script:Report.Summary.OkCount | Should -Be 2
        $script:Report.Summary.WarningCount | Should -Be 1
        $script:Report.Summary.ErrorCount | Should -Be 1
        $script:Report.Summary.SkippedCount | Should -Be 1
        $script:Report.Summary.IsReady | Should -BeFalse
        @($script:Report.Summary.Checks).Count | Should -Be 5
    }

    It 'says that the scan can run, with the warnings to review, when there is no error' {
        $report = Invoke-Report -Check @(
            New-Check -Section 'A' -Name 'One' -Status 'OK'
            New-Check -Section 'A' -Name 'Two' -Status 'Warning' -Detail 'Look at this.'
            New-Check -Section 'A' -Name 'Three' -Status 'Skipped'
        )

        $verdict = Get-Line -Line $report.Lines -Pattern '^ Ready'
        $verdict.Text | Should -Be ' Ready, with warning(s): the scan can run. Review the warning(s) above first.'
        $verdict.Color | Should -Be 'Yellow'
        $report.Summary.IsReady | Should -BeTrue
    }

    It 'tells the operator to run the scan when every check is OK' {
        $report = Invoke-Report -Check @(New-Check -Section 'A' -Name 'One' -Status 'OK')

        $verdict = Get-Line -Line $report.Lines -Pattern '^ Ready'
        $verdict.Text | Should -Be ' Ready: run Invoke-SPSSiteInventory.ps1.'
        $verdict.Color | Should -Be 'Green'
        (Get-Line -Line $report.Lines -Pattern 'Summary : ').Text | Should -Be ' Summary : 1 OK, 0 warning(s), 0 error(s), 0 skipped'
    }

    It 'accepts an empty list of checks' {
        $report = Invoke-Report -Check @()

        $report.Summary.IsReady | Should -BeTrue
        $report.Summary.OkCount | Should -Be 0
        @($report.Summary.Checks).Count | Should -Be 0
    }

    It 'does not count a skipped check as a problem' {
        $report = Invoke-Report -Check @(New-Check -Section 'A' -Name 'One' -Status 'Skipped' -Detail 'Skipped on request.')

        $report.Summary.IsReady | Should -BeTrue
        $report.Summary.ErrorCount | Should -Be 0
        $report.Summary.WarningCount | Should -Be 0
    }
}
