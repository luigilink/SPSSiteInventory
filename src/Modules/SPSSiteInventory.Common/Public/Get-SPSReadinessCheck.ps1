function Get-SPSReadinessCheck {
    <#
        .SYNOPSIS
        Runs the readiness checks of SPSSiteInventory and returns one result per check.

        .DESCRIPTION
        Checks, without changing anything, that the host can run Invoke-SPSSiteInventory: the
        PowerShell host, the settings file, and the SharePoint installation and farm. A check
        that needs the farm is not attempted when the SharePoint commands are not available.

        Every result has a Section, a Name, a Status, a Detail and IsBlocking. The Status is:

        - OK: the check passed.
        - Warning: the scan can run, but the result deserves a look.
        - Error: the scan cannot run, or would fail, until this is fixed. IsBlocking is $true.
        - Skipped: the check could not run, because a check it depends on failed or because
          it was skipped on request.

        The only side effect is that the SharePoint commands are loaded into the session when
        SharePoint is installed, as Invoke-SPSSiteInventory does. Write-SPSReadinessReport
        displays the results.

        .PARAMETER ConfigPath
        Path to the inventory settings .psd1 file.

        .PARAMETER ExampleConfigPath
        Path to the example settings file of the toolkit. When it exists, the settings are
        compared with it, to show the blocking signals and the weights that an older settings
        file does not have yet. When a path is given but the file does not exist, the
        'Comparison with the example' check is Skipped, with the path in its detail. Without
        a path, the settings are not compared and no result is added.

        .PARAMETER OnPremExampleConfigPath
        Path to the example settings file for the on-premises modernization mode. When the
        settings file has TargetMode = 'SharePointOnPrem', the settings are compared with this
        example instead of ExampleConfigPath, since the blocking signals and the weights are not
        the same in the two modes. Without this path, or in the default mode, ExampleConfigPath
        is used.

        .PARAMETER SkipSharePoint
        Skips the checks that need SharePoint, to check the host and the settings file on a
        machine that is not a farm server.

        .EXAMPLE
        Get-SPSReadinessCheck -ConfigPath .\config\inventory-settings.psd1 | Where-Object { $_.IsBlocking }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ConfigPath,

        [Parameter()]
        [System.String]
        $ExampleConfigPath,

        [Parameter()]
        [System.String]
        $OnPremExampleConfigPath,

        [Parameter()]
        [switch]
        $SkipSharePoint
    )

    $results = New-Object -TypeName 'System.Collections.Generic.List[System.Object]'

    function Add-ReadinessResult {
        param
        (
            [System.String] $Section,
            [System.String] $Name,
            [System.String] $Status,
            [System.String] $Detail = ''
        )

        $results.Add([PSCustomObject]@{
                Section    = $Section
                Name       = $Name
                Status     = $Status
                Detail     = $Detail
                IsBlocking = ($Status -eq 'Error')
            })
    }

    function ConvertTo-ReadinessList {
        param ([System.Object[]] $Item)

        $text = (@($Item | Select-Object -First 8) -join ', ')
        if (@($Item).Count -gt 8) {
            $text += (', and {0} more' -f (@($Item).Count - 8))
        }
        return $text
    }

    # Toolkit
    $moduleVersion = if ($null -ne $MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { 'unknown' }
    Add-ReadinessResult -Section 'Toolkit' -Name 'SPSSiteInventory.Common module' -Status 'OK' -Detail ('Version {0}' -f $moduleVersion)

    # PowerShell
    $hostInfo = Get-SPSHostEnvironment
    if ($hostInfo.Edition -eq 'Desktop' -and $hostInfo.VersionMajor -eq 5 -and $hostInfo.VersionMinor -eq 1) {
        Add-ReadinessResult -Section 'PowerShell' -Name 'Windows PowerShell 5.1' -Status 'OK' -Detail ('Version {0}' -f $hostInfo.Version)
    }
    elseif ($hostInfo.Edition -eq 'Desktop') {
        Add-ReadinessResult -Section 'PowerShell' -Name 'Windows PowerShell 5.1' -Status 'Warning' -Detail ('Windows PowerShell {0} found; 5.1 is expected.' -f $hostInfo.Version)
    }
    else {
        Add-ReadinessResult -Section 'PowerShell' -Name 'Windows PowerShell 5.1' -Status 'Error' -Detail ('PowerShell {0} ({1}) cannot load the SharePoint snap-in. Start Windows PowerShell 5.1 (powershell.exe), for example from the SharePoint Management Shell, not pwsh.' -f $hostInfo.Version, $hostInfo.Edition)
    }

    if ($null -eq $hostInfo.IsElevated) {
        Add-ReadinessResult -Section 'PowerShell' -Name 'Elevated session' -Status 'Skipped' -Detail 'Whether the session is elevated cannot be determined on this platform.'
    }
    elseif ($hostInfo.IsElevated) {
        Add-ReadinessResult -Section 'PowerShell' -Name 'Elevated session' -Status 'OK' -Detail ('Running as {0}.' -f $hostInfo.UserName)
    }
    else {
        Add-ReadinessResult -Section 'PowerShell' -Name 'Elevated session' -Status 'Error' -Detail 'The session is not elevated. Start the shell with Run as administrator: the SharePoint commands need it.'
    }

    # Settings
    $settings = $null
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Add-ReadinessResult -Section 'Settings' -Name 'Settings file' -Status 'Error' -Detail ("Not found: '{0}'. Copy config\inventory-settings.example.psd1 to inventory-settings.psd1 and adjust it." -f $ConfigPath)
    }
    else {
        Add-ReadinessResult -Section 'Settings' -Name 'Settings file' -Status 'OK' -Detail $ConfigPath
        try {
            $settings = Get-SPSInventorySetting -Path $ConfigPath
            Add-ReadinessResult -Section 'Settings' -Name 'Settings content' -Status 'OK' -Detail 'The file loads and has its Scoring section.'
        }
        catch {
            Add-ReadinessResult -Section 'Settings' -Name 'Settings content' -Status 'Error' -Detail $_.Exception.Message
        }
    }

    if ($null -ne $settings) {
        $outputFolder = [System.String]$settings['OutputFolder']
        if ([System.String]::IsNullOrWhiteSpace($outputFolder)) {
            Add-ReadinessResult -Section 'Settings' -Name 'Output folder' -Status 'Error' -Detail 'OutputFolder is not set, so the reports could not be written at the end of the scan.'
        }
        elseif (-not (Test-Path -Path $outputFolder -IsValid)) {
            Add-ReadinessResult -Section 'Settings' -Name 'Output folder' -Status 'Error' -Detail ("'{0}' is not a valid path." -f $outputFolder)
        }
        elseif (Test-Path -LiteralPath $outputFolder -PathType Container) {
            Add-ReadinessResult -Section 'Settings' -Name 'Output folder' -Status 'OK' -Detail $outputFolder
        }
        elseif (Test-Path -LiteralPath $outputFolder -PathType Leaf) {
            Add-ReadinessResult -Section 'Settings' -Name 'Output folder' -Status 'Error' -Detail ("'{0}' is a file, not a folder." -f $outputFolder)
        }
        else {
            $ancestor = Split-Path -Path $outputFolder -Parent
            while (-not [System.String]::IsNullOrEmpty($ancestor) -and -not (Test-Path -LiteralPath $ancestor)) {
                $ancestor = Split-Path -Path $ancestor -Parent
            }
            if ([System.String]::IsNullOrEmpty($ancestor) -and [System.IO.Path]::IsPathRooted($outputFolder)) {
                Add-ReadinessResult -Section 'Settings' -Name 'Output folder' -Status 'Error' -Detail ("'{0}' cannot be created: no part of that path exists. Is the drive there?" -f $outputFolder)
            }
            elseif (-not [System.String]::IsNullOrEmpty($ancestor) -and -not (Test-Path -LiteralPath $ancestor -PathType Container)) {
                Add-ReadinessResult -Section 'Settings' -Name 'Output folder' -Status 'Error' -Detail ("'{0}' cannot be created: '{1}' is a file, not a folder." -f $outputFolder, $ancestor)
            }
            else {
                Add-ReadinessResult -Section 'Settings' -Name 'Output folder' -Status 'OK' -Detail ("'{0}' does not exist yet; the scan creates it." -f $outputFolder)
            }
        }

        $targetMode = (Get-SPSTargetProfile -TargetMode $(if ($settings.ContainsKey('TargetMode')) { $settings['TargetMode'] } else { 'SharePointOnline' })).TargetMode
        if ($targetMode -eq 'SharePointOnPrem' -and -not [System.String]::IsNullOrEmpty($OnPremExampleConfigPath)) {
            $ExampleConfigPath = $OnPremExampleConfigPath
        }
        if (-not [System.String]::IsNullOrEmpty($ExampleConfigPath) -and (Test-Path -LiteralPath $ExampleConfigPath -PathType Leaf)) {
            $example = $null
            try {
                $example = Get-SPSInventorySetting -Path $ExampleConfigPath
            }
            catch {
                Add-ReadinessResult -Section 'Settings' -Name 'Comparison with the example' -Status 'Skipped' -Detail ('The example settings file could not be read: {0}' -f $_.Exception.Message)
            }

            if ($null -ne $example) {
                $settingsBlocking = @($settings.Scoring.BlockingSignals | Where-Object { $_ })
                $missingBlocking = @($example.Scoring.BlockingSignals | Where-Object { $_ -and ($settingsBlocking -notcontains $_) })
                # IsLockedSite blocks on every lock, so it covers HasNoAccessLock.
                if ($settingsBlocking -contains 'IsLockedSite') {
                    $missingBlocking = @($missingBlocking | Where-Object { $_ -ne 'HasNoAccessLock' })
                }
                if ($missingBlocking.Count -gt 0) {
                    Add-ReadinessResult -Section 'Settings' -Name 'Blocking signals' -Status 'Warning' -Detail ('{0} blocking signal(s) of the example configuration are not in Scoring.BlockingSignals: {1}. Sites that have them are not classified as Blocking.' -f $missingBlocking.Count, (ConvertTo-ReadinessList -Item $missingBlocking))
                }
                else {
                    Add-ReadinessResult -Section 'Settings' -Name 'Blocking signals' -Status 'OK' -Detail 'Every blocking signal of the example configuration is in Scoring.BlockingSignals.'
                }

                $settingsWeights = @()
                if ($settings.Scoring.Weights -is [System.Collections.IDictionary]) {
                    $settingsWeights = @($settings.Scoring.Weights.Keys)
                }
                $missingWeights = @()
                if ($example.Scoring.Weights -is [System.Collections.IDictionary]) {
                    $missingWeights = @($example.Scoring.Weights.Keys | Where-Object { $settingsWeights -notcontains $_ } | Sort-Object)
                }
                if ($missingWeights.Count -gt 0) {
                    Add-ReadinessResult -Section 'Settings' -Name 'Signal weights' -Status 'Warning' -Detail ('{0} signal(s) of the example configuration have no entry in Scoring.Weights: {1}. They are collected and reported, but they do not change the score.' -f $missingWeights.Count, (ConvertTo-ReadinessList -Item $missingWeights))
                }
                else {
                    Add-ReadinessResult -Section 'Settings' -Name 'Signal weights' -Status 'OK' -Detail 'Every signal of the example configuration has a weight.'
                }
            }
        }
        elseif (-not [System.String]::IsNullOrEmpty($ExampleConfigPath)) {
            Add-ReadinessResult -Section 'Settings' -Name 'Comparison with the example' -Status 'Skipped' -Detail ('The example settings file was not found at {0}: the blocking signals and the weights were not compared.' -f $ExampleConfigPath)
        }
    }

    # SharePoint
    if ($SkipSharePoint) {
        Add-ReadinessResult -Section 'SharePoint' -Name 'SharePoint checks' -Status 'Skipped' -Detail 'Skipped on request (-SkipSharePoint).'
        return $results.ToArray()
    }

    $productVersion = Get-SPSInstalledProductVersion
    if ($null -eq $productVersion) {
        Add-ReadinessResult -Section 'SharePoint' -Name 'SharePoint installed' -Status 'Error' -Detail 'SharePoint is not installed on this host. Run the toolkit on a SharePoint farm server.'
        Add-ReadinessResult -Section 'SharePoint' -Name 'SharePoint commands' -Status 'Skipped' -Detail 'SharePoint is not installed.'
        Add-ReadinessResult -Section 'SharePoint' -Name 'Farm connection' -Status 'Skipped' -Detail 'SharePoint is not installed.'
        return $results.ToArray()
    }

    Add-ReadinessResult -Section 'SharePoint' -Name 'SharePoint installed' -Status 'OK' -Detail ('Build {0}.{1}.{2}.{3}' -f $productVersion.ProductMajorPart, $productVersion.ProductMinorPart, $productVersion.ProductBuildPart, $productVersion.ProductPrivatePart)

    $commandsLoaded = $false
    try {
        Import-SPSSharePointCommand
        $commandsLoaded = $null -ne (Get-Command -Name 'Get-SPWebApplication' -ErrorAction SilentlyContinue)
        if ($commandsLoaded) {
            Add-ReadinessResult -Section 'SharePoint' -Name 'SharePoint commands' -Status 'OK' -Detail 'The SharePoint commands are loaded.'
        }
        else {
            Add-ReadinessResult -Section 'SharePoint' -Name 'SharePoint commands' -Status 'Error' -Detail 'Get-SPWebApplication is not available after loading the SharePoint commands.'
        }
    }
    catch {
        Add-ReadinessResult -Section 'SharePoint' -Name 'SharePoint commands' -Status 'Error' -Detail ('The SharePoint commands could not be loaded: {0}' -f $_.Exception.Message)
    }

    if (-not $commandsLoaded) {
        Add-ReadinessResult -Section 'SharePoint' -Name 'Farm connection' -Status 'Skipped' -Detail 'The SharePoint commands are not available.'
        return $results.ToArray()
    }

    $farm = $null
    try {
        $farm = Get-SPFarm -ErrorAction Stop
        Add-ReadinessResult -Section 'SharePoint' -Name 'Farm connection' -Status 'OK' -Detail ("Configuration database '{0}'." -f $farm.Name)
    }
    catch {
        Add-ReadinessResult -Section 'SharePoint' -Name 'Farm connection' -Status 'Error' -Detail ('The farm cannot be reached: {0}' -f $_.Exception.Message)
        Add-ReadinessResult -Section 'SharePoint' -Name 'Farm administrator' -Status 'Skipped' -Detail 'The farm cannot be reached.'
        Add-ReadinessResult -Section 'SharePoint' -Name 'Web applications' -Status 'Skipped' -Detail 'The farm cannot be reached.'
        return $results.ToArray()
    }

    try {
        if ($farm.CurrentUserIsAdministrator()) {
            Add-ReadinessResult -Section 'SharePoint' -Name 'Farm administrator' -Status 'OK' -Detail 'The current account is a farm administrator.'
        }
        else {
            Add-ReadinessResult -Section 'SharePoint' -Name 'Farm administrator' -Status 'Warning' -Detail 'The current account is not a farm administrator. The scan needs read access to every site collection: run it as the farm account.'
        }
    }
    catch {
        Add-ReadinessResult -Section 'SharePoint' -Name 'Farm administrator' -Status 'Warning' -Detail ('Whether the current account is a farm administrator could not be determined: {0}' -f $_.Exception.Message)
    }

    # The scan passes every entry to Get-SPWebApplication, so a blank entry is checked, not dropped:
    # only a missing value or an empty list means that every content web application is scanned.
    $configuredUrl = @()
    if ($null -ne $settings -and $null -ne $settings['WebApplicationUrl']) {
        $configuredUrl = @($settings['WebApplicationUrl'])
    }

    if ($configuredUrl.Count -gt 0) {
        foreach ($url in $configuredUrl) {
            if ([System.String]::IsNullOrWhiteSpace([System.String]$url)) {
                Add-ReadinessResult -Section 'SharePoint' -Name 'Web application (empty entry)' -Status 'Error' -Detail 'WebApplicationUrl has an empty entry, and the scan fails on it. Remove it, or leave the setting empty to scan every content web application.'
                continue
            }
            try {
                $null = Get-SPWebApplication -Identity $url -ErrorAction Stop
                Add-ReadinessResult -Section 'SharePoint' -Name ("Web application '{0}'" -f $url) -Status 'OK' -Detail 'Found.'
            }
            catch {
                Add-ReadinessResult -Section 'SharePoint' -Name ("Web application '{0}'" -f $url) -Status 'Error' -Detail ('Not found: {0}' -f $_.Exception.Message)
            }
        }
    }
    else {
        try {
            $webApplication = @(Get-SPWebApplication -ErrorAction Stop)
            if ($webApplication.Count -gt 0) {
                Add-ReadinessResult -Section 'SharePoint' -Name 'Web applications' -Status 'OK' -Detail ('{0} content web application(s) will be scanned.' -f $webApplication.Count)
            }
            else {
                Add-ReadinessResult -Section 'SharePoint' -Name 'Web applications' -Status 'Error' -Detail 'The farm has no content web application to scan.'
            }
        }
        catch {
            Add-ReadinessResult -Section 'SharePoint' -Name 'Web applications' -Status 'Error' -Detail ('The web applications could not be listed: {0}' -f $_.Exception.Message)
        }
    }

    return $results.ToArray()
}
