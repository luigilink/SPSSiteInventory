function Initialize-SPSScript {
    <#
        .SYNOPSIS
        Common bootstrap for SPSSiteInventory scripts: admin check, transcript, banner.

        .DESCRIPTION
        Performs the boilerplate shared by the entry-point scripts: validates the process
        runs as Administrator (required to create the Event Log source and to call most
        SharePoint commands), sets the window title, creates the log folder, starts a
        transcript, and prints a banner. When -Version is omitted it reads the
        SPSSiteInventory.Common manifest version so every consumer reports the same
        single source of truth.

        Returns a PSCustomObject with LogFolder, LogFile, CurrentUser, Version,
        DateStarted and ServerTarget.

        .PARAMETER ScriptName
        Short name of the calling script (used in the banner, log file name and title).

        .PARAMETER Version
        Optional version string. Defaults to the SPSSiteInventory.Common module version.

        .PARAMETER ScriptRoot
        Root folder of the calling script (typically $PSScriptRoot). Used to place the
        Logs folder next to the entry-point script.

        .PARAMETER LogFolder
        Explicit log folder. Defaults to a 'Logs' folder under -ScriptRoot.

        .EXAMPLE
        $ctx = Initialize-SPSScript -ScriptName 'Invoke-SPSSiteInventory' -ScriptRoot $PSScriptRoot
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ScriptName,

        [Parameter()]
        [System.String]
        $Version,

        [Parameter()]
        [System.String]
        $ScriptRoot,

        [Parameter()]
        [System.String]
        $LogFolder
    )

    if ([string]::IsNullOrEmpty($Version)) {
        $moduleVersion = $MyInvocation.MyCommand.Module.Version
        if ($null -eq $moduleVersion) {
            $moduleVersion = (Get-Module -Name SPSSiteInventory.Common -ErrorAction SilentlyContinue).Version
        }
        $Version = if ($null -ne $moduleVersion) { $moduleVersion.ToString() } else { 'unknown' }
    }

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        throw "You do not have Administrator rights to run $ScriptName. Please re-run this script as an Administrator."
    }

    if ([string]::IsNullOrEmpty($LogFolder)) {
        $callerRoot = $ScriptRoot
        if ([string]::IsNullOrEmpty($callerRoot)) {
            $callerRoot = Get-Location | Select-Object -ExpandProperty Path
        }
        $LogFolder = Join-Path -Path $callerRoot -ChildPath 'Logs'
    }

    if (-not (Test-Path -Path $LogFolder)) {
        $null = New-Item -Path $LogFolder -ItemType Directory -Force
    }

    $dateStarted = Get-Date
    $currentUser = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
    $psVersion = ($host).Version.ToString()
    $serverTarget = $env:COMPUTERNAME
    $pathLogFile = Join-Path -Path $LogFolder -ChildPath ($ScriptName + (Get-Date -Format yyyyMMdd-HHmm) + '.log')

    $Host.UI.RawUI.WindowTitle = "$ScriptName script running on $serverTarget"

    Start-Transcript -Path $pathLogFile -IncludeInvocationHeader | Out-Null

    Write-Output '-----------------------------------------------'
    Write-Output "| SPSSiteInventory - $ScriptName $Version |"
    Write-Output "| Started on         - $dateStarted by $currentUser |"
    Write-Output "| PowerShell Version - $psVersion |"
    Write-Output "| SharePoint Server  - $serverTarget |"
    Write-Output '-----------------------------------------------'

    return [PSCustomObject]@{
        LogFolder    = $LogFolder
        LogFile      = $pathLogFile
        CurrentUser  = $currentUser
        Version      = $Version
        DateStarted  = $dateStarted
        ServerTarget = $serverTarget
    }
}
