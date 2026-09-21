function Add-SPSInventoryEvent {
    <#
        .SYNOPSIS
        Writes a message to the console transcript and, when possible, to a dedicated
        Windows Event Log source.

        .DESCRIPTION
        Add-SPSInventoryEvent centralizes logging for the toolkit. It always writes the
        message to the output stream (captured by the script transcript) and additionally
        writes to a Windows Event Log named 'SPSSiteInventory' when the source is
        available. Creating an Event Log source requires Administrator rights on first
        use; when the source cannot be created or written, the function degrades quietly
        to console-only logging so a scan is never blocked by logging.

        .PARAMETER Message
        The message to log.

        .PARAMETER Level
        Severity of the message: Information (default), Warning or Error.

        .PARAMETER EventId
        Numeric Event Log id. Defaults to 1000.

        .EXAMPLE
        Add-SPSInventoryEvent -Message 'Scan started' -Level Information
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Message,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [System.String]
        $Level = 'Information',

        [Parameter()]
        [System.Int32]
        $EventId = 1000
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[{0}] [{1}] {2}' -f $timestamp, $Level.ToUpperInvariant(), $Message

    switch ($Level) {
        'Error' { Write-Error -Message $line -ErrorAction Continue }
        'Warning' { Write-Warning -Message $line }
        default { Write-Output $line }
    }

    $logName = 'SPSSiteInventory'
    $source = 'SPSSiteInventory'

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName $logName -Source $source -ErrorAction Stop
        }
        Write-EventLog -LogName $logName -Source $source -EntryType $Level -EventId $EventId -Message $Message -ErrorAction Stop
    }
    catch {
        Write-Verbose -Message "Event Log write skipped ($($_.Exception.Message)); console logging only."
    }
}
