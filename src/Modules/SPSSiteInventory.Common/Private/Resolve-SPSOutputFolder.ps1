function Resolve-SPSOutputFolder {
    <#
        .SYNOPSIS
        Says which folder the reports are written to.

        .DESCRIPTION
        OutputFolder in the settings is optional. When it is empty, or missing, the reports go to a
        Reports folder next to the entry-point script, as the logs go to a Logs folder next to it
        (Initialize-SPSScript). A value that is set is used as it is, so a settings file of an earlier
        version behaves as before, and a relative value keeps resolving against the current folder.

        With -Create the folder is created when it does not exist, and a folder that cannot be created
        is an error that names it: the orchestrator does it when the run starts, so that the problem
        stops the run before the scan and not at the end of it, when the reports are written. Without
        -Create the function reads nothing and writes nothing, which the readiness check relies on.

        Private because it is an implementation detail of the orchestrator and of the readiness check,
        which share it so that the default lives in one place.

        .PARAMETER OutputFolder
        The OutputFolder of the settings, or nothing when the settings file has none.

        .PARAMETER ScriptRoot
        The folder of the entry-point script (typically $PSScriptRoot). The current folder when it is
        omitted, as for the logs.

        .PARAMETER Create
        Creates the folder when it does not exist.

        .OUTPUTS
        A PSCustomObject with Path (the folder) and IsDefault ($true when OutputFolder was empty).

        .EXAMPLE
        (Resolve-SPSOutputFolder -OutputFolder $settings['OutputFolder'] -ScriptRoot $PSScriptRoot -Create).Path
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $OutputFolder,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $ScriptRoot,

        [Parameter()]
        [switch]
        $Create
    )

    $isDefault = [System.String]::IsNullOrWhiteSpace($OutputFolder)
    if ($isDefault) {
        $root = $ScriptRoot
        if ([System.String]::IsNullOrWhiteSpace($root)) {
            $root = (Get-Location).Path
        }
        $path = Join-Path -Path $root -ChildPath 'Reports'
    }
    else {
        $path = $OutputFolder
    }

    if ($Create -and -not (Test-Path -LiteralPath $path -PathType Container -ErrorAction SilentlyContinue)) {
        $reason = ''
        try {
            $null = New-Item -Path $path -ItemType Directory -Force -ErrorAction Stop
        }
        catch {
            $reason = $_.Exception.Message
        }
        # PowerShell does not always say so when it cannot create a folder (under a file, for example): the folder is looked for.
        if (-not (Test-Path -LiteralPath $path -PathType Container -ErrorAction SilentlyContinue)) {
            if ([System.String]::IsNullOrEmpty($reason)) {
                $reason = 'the folder does not exist afterwards, so a part of the path is probably a file.'
            }
            throw "The report folder '$path' cannot be created: $reason"
        }
    }

    [PSCustomObject]@{
        Path      = $path
        IsDefault = $isDefault
    }
}
