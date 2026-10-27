function Write-SPSReadinessReport {
    <#
        .SYNOPSIS
        Writes the readiness checks as a colored report and returns a summary.

        .DESCRIPTION
        Displays the results of Get-SPSReadinessCheck grouped by section, one line per check with
        a status mark and a color: [ OK ] in green, [WARN] in yellow, [ERR ] in red and [SKIP]
        in gray. The report ends with the number of checks per status and a verdict that tells
        the operator whether the scan can run: an error blocks it, a warning does not.

        The function returns a summary object with the counts, IsReady ($true when there is no
        error) and the checks, so the caller can choose an exit code.

        .PARAMETER Check
        The results returned by Get-SPSReadinessCheck.

        .EXAMPLE
        $summary = Write-SPSReadinessReport -Check (Get-SPSReadinessCheck -ConfigPath .\config\inventory-settings.psd1)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'This is an operator-facing readiness report whose purpose is colored console output.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Check
    )

    $style = @{
        OK      = @{ Mark = '[ OK ]'; Color = 'Green' }
        Warning = @{ Mark = '[WARN]'; Color = 'Yellow' }
        Error   = @{ Mark = '[ERR ]'; Color = 'Red' }
        Skipped = @{ Mark = '[SKIP]'; Color = 'DarkGray' }
    }
    $rule = '============================================================'

    Write-Host ''
    Write-Host $rule -ForegroundColor Cyan
    Write-Host ' SPSSiteInventory - Readiness Check' -ForegroundColor Cyan
    Write-Host ('  Computer : {0}' -f [System.Environment]::MachineName) -ForegroundColor Cyan
    Write-Host ('  Date     : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Cyan
    Write-Host $rule -ForegroundColor Cyan

    $currentSection = $null
    foreach ($item in $Check) {
        if ($item.Section -ne $currentSection) {
            Write-Host ''
            Write-Host ('== {0} ==' -f $item.Section) -ForegroundColor Cyan
            $currentSection = $item.Section
        }

        $mark = $style[[System.String]$item.Status]
        if ($null -eq $mark) {
            $mark = $style['Error']
        }
        $line = '{0}  {1}' -f $mark.Mark, $item.Name
        if (-not [System.String]::IsNullOrEmpty([System.String]$item.Detail)) {
            $line += ' - {0}' -f $item.Detail
        }
        Write-Host $line -ForegroundColor $mark.Color
    }

    $okCount = @($Check | Where-Object { $_.Status -eq 'OK' }).Count
    $warningCount = @($Check | Where-Object { $_.Status -eq 'Warning' }).Count
    $errorCount = @($Check | Where-Object { $_.Status -eq 'Error' }).Count
    $skippedCount = @($Check | Where-Object { $_.Status -eq 'Skipped' }).Count

    Write-Host ''
    Write-Host $rule -ForegroundColor Cyan
    Write-Host (' Summary : {0} OK, {1} warning(s), {2} error(s), {3} skipped' -f $okCount, $warningCount, $errorCount, $skippedCount) -ForegroundColor Cyan
    Write-Host $rule -ForegroundColor Cyan
    if ($errorCount -gt 0) {
        Write-Host ' Not ready: fix the error(s) above before you run Invoke-SPSSiteInventory.ps1. Warnings do not block the scan.' -ForegroundColor Red
    }
    elseif ($warningCount -gt 0) {
        Write-Host ' Ready, with warning(s): the scan can run. Review the warning(s) above first.' -ForegroundColor Yellow
    }
    else {
        Write-Host ' Ready: run Invoke-SPSSiteInventory.ps1.' -ForegroundColor Green
    }

    [PSCustomObject]@{
        OkCount      = $okCount
        WarningCount = $warningCount
        ErrorCount   = $errorCount
        SkippedCount = $skippedCount
        IsReady      = ($errorCount -eq 0)
        Checks       = @($Check)
    }
}
