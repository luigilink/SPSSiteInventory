function Get-SPSWebApplicationAuthentication {
    <#
        .SYNOPSIS
        Summarizes configured authentication across all zones of a web application.

        .DESCRIPTION
        Reads each configured IIS zone, including non-default zones and mixed
        Windows/forms authentication. HasFbaZone means that FBA is configured,
        not that a particular site or user actually uses that sign-in method.
        Provider names are configuration identifiers; no credentials are read.

        Authentication read errors terminate collection rather than reporting
        an unreadable configuration as Windows-only. Unrecognized providers are
        surfaced for review; HasFbaZone is unknown unless FBA was positively found.

        .PARAMETER WebApplication
        An SPWebApplication object returned by Get-SPWebApplication.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $WebApplication
    )

    $zones = @($WebApplication.IisSettings.Keys | Sort-Object)
    if ($zones.Count -eq 0) {
        throw "No configured authentication zones could be read for '$($WebApplication.Url)'."
    }
    if ($null -eq $WebApplication.UseClaimsAuthentication) {
        throw "Could not determine the authentication model for '$($WebApplication.Url)'."
    }

    $modes = [System.Collections.Generic.List[string]]::new()
    $zoneDescriptions = [System.Collections.Generic.List[string]]::new()
    $memberships = [System.Collections.Generic.List[string]]::new()
    $roles = [System.Collections.Generic.List[string]]::new()
    $hasFba = $false
    $hasUnknown = $false
    $reviewRequired = $false

    foreach ($zone in $zones) {
        if (-not $WebApplication.UseClaimsAuthentication) {
            $modes.Add('Classic Windows')
            $zoneDescriptions.Add(('{0}: Classic Windows' -f $zone))
            continue
        }

        $providers = @(Get-SPAuthenticationProvider -WebApplication $WebApplication.Url -Zone $zone -ErrorAction Stop |
            Where-Object { $null -ne $_ })
        if ($providers.Count -eq 0) {
            throw "No authentication providers were returned for '$($WebApplication.Url)' zone '$zone'."
        }

        foreach ($provider in $providers) {
            $mode = switch ([string]$provider.ClaimProviderName) {
                'AD' { 'Windows' }
                'Forms' { 'FBA' }
                '' { 'Unknown' }
                default { 'Federated / custom' }
            }
            $modes.Add($mode)
            $description = '{0}: {1}' -f $zone, $mode
            if ($provider.DisplayName) { $description += ' (' + $provider.DisplayName + ')' }

            if ($mode -eq 'FBA') {
                $hasFba = $true
                if ($provider.MembershipProvider) { $memberships.Add([string]$provider.MembershipProvider) }
                if ($provider.RoleProvider) { $roles.Add([string]$provider.RoleProvider) }
                $description += ' [membership={0}, roles={1}]' -f $provider.MembershipProvider, $provider.RoleProvider
            }
            elseif ($mode -eq 'Unknown' -or $mode -eq 'Federated / custom') {
                $reviewRequired = $true
                if ($mode -eq 'Unknown') { $hasUnknown = $true }
                Write-Warning -Message "Authentication provider '$($provider.DisplayName)' on '$($WebApplication.Url)' zone '$zone' requires an identity-migration review."
            }
            $zoneDescriptions.Add($description)
        }
    }

    [PSCustomObject]@{
        AuthenticationModes          = (@($modes | Sort-Object -Unique) -join '; ')
        AuthenticationZones          = ($zoneDescriptions -join '; ')
        FbaMembershipProviders       = (@($memberships | Sort-Object -Unique) -join '; ')
        FbaRoleProviders             = (@($roles | Sort-Object -Unique) -join '; ')
        HasFbaZone                   = if ($hasFba) { $true } elseif ($hasUnknown) { $null } else { $false }
        AuthenticationReviewRequired = $reviewRequired
    }
}
