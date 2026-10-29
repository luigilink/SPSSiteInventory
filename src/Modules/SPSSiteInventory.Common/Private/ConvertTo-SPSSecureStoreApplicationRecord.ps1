function ConvertTo-SPSSecureStoreApplicationRecord {
    <#
        .SYNOPSIS
        Projects a Secure Store target application into a portable inventory row.

        .DESCRIPTION
        A target application is the Secure Store definition of a set of credentials that maps the
        identity of a user or a group to the credentials of an external system. The row holds what
        the SMAT Secure Store report holds, which is enough to create the application again in the
        target: the name (the unique application ID, the one that solutions refer to), the display
        name, the contact e-mail address, the type, the credential management URL and the ticket
        time-out in minutes. The fields of the application and the credentials themselves are not
        read.

        The member names of the object that Get-SPSecureStoreApplication returns are not documented.
        The row is read with the names of the contract of the Secure Store service (appId,
        friendlyName, contactEmail, credentialManagementUrl, ticketTimeout, type) and the names of the
        parameters of New-SPSecureStoreTargetApplication (Name, FriendlyName, ContactEmail,
        ApplicationType, SetCredentialsUri, TimeoutInMinutes), on the object itself and on the
        TargetApplication that it may wrap. The name and the type are required: when one is not a
        member of the object, the error lists the members that the object has, so that the first run
        on a farm tells what to correct. The other values are left empty when no member has them.

        A member that exists but cannot be read raises an error instead of being read as an empty
        value (PowerShell turns a failing .NET getter into $null), so the caller can mark the Secure
        Store inventory incomplete.

        Private because it is an implementation detail of Get-SPSSecureStoreApplication.

        .PARAMETER Application
        A Secure Store application, as Get-SPSecureStoreApplication returns it.

        .EXAMPLE
        Get-SPSecureStoreApplication -ServiceContext $context -All | ForEach-Object { ConvertTo-SPSSecureStoreApplicationRecord -Application $_ }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Application
    )

    # The object itself first, then the target application that it wraps, if it does.
    $sources = [System.Collections.Generic.List[object]]::new()
    $sources.Add($Application)
    if ($null -ne $Application.PSObject.Properties['TargetApplication']) {
        $wrapped = Get-SPSPropertyValue -InputObject $Application -Name 'TargetApplication'
        if ($null -ne $wrapped) {
            $sources.Add($wrapped)
        }
    }

    $read = {
        param ([System.String[]] $Names)
        foreach ($source in $sources) {
            foreach ($candidate in $Names) {
                if ($null -ne $source.PSObject.Properties[$candidate]) {
                    return [PSCustomObject]@{ Found = $true; Value = (Get-SPSPropertyValue -InputObject $source -Name $candidate) }
                }
            }
        }
        return [PSCustomObject]@{ Found = $false; Value = $null }
    }

    $memberNames = {
        $names = foreach ($source in $sources) { $source.PSObject.Properties.Name }
        return (@($names | Sort-Object -Unique) -join ', ')
    }

    $nameMember = & $read @('Name', 'ApplicationId')
    if (-not $nameMember.Found -or [string]::IsNullOrWhiteSpace([string]$nameMember.Value)) {
        throw ('A Secure Store application has no readable name (members: {0}).' -f (& $memberNames))
    }
    $name = ([string]$nameMember.Value).Trim()

    $typeMember = & $read @('Type', 'ApplicationType')
    if (-not $typeMember.Found -or $null -eq $typeMember.Value -or [string]::IsNullOrWhiteSpace([string]$typeMember.Value)) {
        throw ("The type of Secure Store application '{0}' could not be read (members: {1})." -f $name, (& $memberNames))
    }

    $friendlyName = & $read @('FriendlyName')
    $contactEmail = & $read @('ContactEmail')
    $credentialUrl = & $read @('CredentialManagementUrl', 'CredentialManagementUri', 'SetCredentialsUri')
    $timeout = & $read @('TicketTimeoutInMinutes', 'TimeoutInMinutes', 'TicketTimeout')

    $timeoutMinutes = $null
    if ($timeout.Found -and $null -ne $timeout.Value -and -not [string]::IsNullOrWhiteSpace([string]$timeout.Value)) {
        $parsed = 0
        if (-not [int]::TryParse([string]$timeout.Value, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            throw ("The ticket time-out of Secure Store application '{0}' is not a number of minutes: '{1}'." -f $name, [string]$timeout.Value)
        }
        $timeoutMinutes = $parsed
    }

    [PSCustomObject]@{
        Name                    = $name
        FriendlyName            = if ($friendlyName.Found -and $null -ne $friendlyName.Value) { ([string]$friendlyName.Value).Trim() } else { '' }
        ContactEmail            = if ($contactEmail.Found -and $null -ne $contactEmail.Value) { ([string]$contactEmail.Value).Trim() } else { '' }
        ApplicationType         = ([string]$typeMember.Value).Trim()
        CredentialManagementUrl = if ($credentialUrl.Found -and $null -ne $credentialUrl.Value) { ([string]$credentialUrl.Value).Trim() } else { '' }
        TicketTimeoutMinutes    = $timeoutMinutes
    }
}
