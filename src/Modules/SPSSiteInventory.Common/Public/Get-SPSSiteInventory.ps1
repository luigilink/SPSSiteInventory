function Get-SPSSiteInventory {
    <#
        .SYNOPSIS
        Enumerates SharePoint site collections and returns their identity and volumetry.

        .DESCRIPTION
        Walks the requested web applications (or all content web applications when none
        is specified) and returns one record per site collection with the fields that
        drive the migration plan: URL, title, content database, root-web template, template
        compatibility/language signals, size, sub-web count and last activity date.
        Progress is displayed as sites are visited.
        Individual metadata failures are returned as partial records with warning details.

        This collector returns volumetry, identity and authentication configuration
        across every web application zone. FBA configured
        on any zone is surfaced on every collection in that web application; this does
        not measure actual sign-in usage. Authentication read errors stop collection.
        Customization signals that feed the complexity score are collected separately by
        Get-SPSSiteCustomization, so a fast "identity + size" pass can run on its own.

        Web application policies and the browser file handling setting are read once per
        web application and surfaced on each of its site collections. A failed read does
        not stop collection: the policy fields stay empty and the site records are marked
        partial, so an unreadable setting is never reported as no policies.

        Personal sites (My Sites, template SPSPERS) and site masters (the hidden site
        collections that SharePoint creates to speed up the creation of personal sites, with
        a host name of sitemaster- followed by a GUID) are not sites to migrate, so they are
        left out by default: they get no record and no warning. A site master is skipped
        before it is opened, a personal site as soon as the template of its root web is read.
        The My Site host (SPSMSITEHOST) stays in the scan.

        Requires the SharePoint commands (see Import-SPSSharePointCommand) and to run as
        the farm account on a farm server.

        .PARAMETER WebApplicationUrl
        Optional list of web application URLs to limit the scan. When omitted, all
        content web applications are scanned.

        .PARAMETER IncludePersonalSite
        Keeps the personal sites in the scan.

        .PARAMETER IncludeSiteMaster
        Keeps the site masters in the scan.

        .PARAMETER Exclusion
        Optional dictionary that the function fills with the number of site collections that
        it left out: PersonalSites and SiteMasters, both set to 0 when the scan starts.

        .EXAMPLE
        Get-SPSSiteInventory

        .EXAMPLE
        Get-SPSSiteInventory -WebApplicationUrl 'https://intranet.contoso.com'
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter()]
        [System.String[]]
        $WebApplicationUrl = @(),

        [Parameter()]
        [System.Collections.IDictionary]
        $TemplateParity = @{},

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $IncludePersonalSite,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $IncludeSiteMaster,

        [Parameter()]
        [System.Collections.IDictionary]
        $Exclusion = @{}
    )

    $Exclusion['PersonalSites'] = 0
    $Exclusion['SiteMasters'] = 0

    $webApps = if ($WebApplicationUrl.Count -gt 0) {
        $WebApplicationUrl | ForEach-Object { Get-SPWebApplication -Identity $_ -ErrorAction Stop }
    }
    else {
        Get-SPWebApplication -ErrorAction Stop
    }

    $inventory = [System.Collections.Generic.List[object]]::new()
    foreach ($webApp in $webApps) {
        $authentication = Get-SPSWebApplicationAuthentication -WebApplication $webApp
        $policy = $null
        $policyWarning = ''
        try {
            $policy = Get-SPSWebApplicationPolicy -WebApplication $webApp
        }
        catch {
            $policyWarning = "Web application policies could not be read: $($_.Exception.Message)"
            $null = Add-SPSInventoryEvent -Message "Could not read the policies of web application '$($webApp.Url)': $($_.Exception.Message)" -Level Warning
        }
        Write-Progress -Id 1 -Activity 'Enumerating site collections' -Status "Opening the site collection list for $($webApp.Url)" -PercentComplete 0
        Add-SPSInventoryEvent -Message "Starting site collection enumeration for web application '$($webApp.Url)'." -Level Information | Out-Host
        $addEnumerationFailure = {
            param ([string]$Message)
            $null = $inventory.Add([PSCustomObject]@{
                InventoryScope = 'WebApplication'
                Url = [string]$webApp.Url
                Title = 'Site collection enumeration failed'
                WebApp = $webApp.Name
                WebAppUrl = [string]$webApp.Url
                AuthenticationModes = $authentication.AuthenticationModes
                AuthenticationZones = $authentication.AuthenticationZones
                FbaMembershipProviders = $authentication.FbaMembershipProviders
                FbaRoleProviders = $authentication.FbaRoleProviders
                HasFbaZone = $authentication.HasFbaZone
                AuthenticationReviewRequired = $authentication.AuthenticationReviewRequired
                BrowserFileHandling = if ($null -ne $policy) { $policy.BrowserFileHandling } else { $null }
                WebAppPolicyCount = if ($null -ne $policy) { $policy.WebAppPolicyCount } else { $null }
                WebAppPolicyExamples = if ($null -ne $policy) { $policy.WebAppPolicyExamples } else { $null }
                ContentDb = ''
                Template = ''
                IsUnsupportedSiteTemplate = $null
                TemplateCompatibility = 'NotCollected'
                TemplateCompatibilityReason = 'Site collection enumeration failed before template collection.'
                TemplateLanguageLcid = $null
                TemplateLanguageTag = ''
                TemplateLanguageName = ''
                TemplateLanguageReviewRequired = $null
                TemplateLanguageReason = ''
                SizeGB = $null
                SubWebCount = $null
                LastModified = $null
                SiteInventoryComplete = $false
                SiteInventoryWarnings = (@($Message, $policyWarning) | Where-Object { $_ }) -join '; '
            })
        }
        try {
            $sites = $webApp.Sites
            if ($null -eq $sites) {
                throw "The site collection list is unavailable for web application '$($webApp.Url)'."
            }
        }
        catch {
            $failureMessage = "Site collection list could not be accessed: $($_.Exception.Message)"
            $null = Add-SPSInventoryEvent -Message "Could not access site collections for web application '$($webApp.Url)': $failureMessage" -Level Warning
            & $addEnumerationFailure $failureMessage
            Write-Progress -Id 1 -Activity 'Enumerating site collections' -Completed
            continue
        }

        $siteCount = $null
        try {
            $siteCount = [int]$sites.Count
        }
        catch {
            $null = Add-SPSInventoryEvent -Message "Could not determine the site count for web application '$($webApp.Url)'; progress will show an unknown total. $($_.Exception.Message)" -Level Warning
        }

        $siteIndex = 0
        try {
            foreach ($site in $sites) {
                $siteIndex++
                $siteUrl = ''
                $warnings = [System.Collections.Generic.List[string]]::new()
                if ($policyWarning) {
                    $warnings.Add($policyWarning)
                }
                try {
                    $siteUrl = [string]$site.Url
                }
                catch {
                    $warnings.Add("Site URL could not be read: $($_.Exception.Message)")
                }

                $progressStatus = if ($null -ne $siteCount) {
                    '{0}/{1}: {2}' -f $siteIndex, $siteCount, $siteUrl
                }
                else {
                    'Site {0} (total unknown): {1}' -f $siteIndex, $siteUrl
                }
                $percentComplete = if ($null -ne $siteCount -and $siteCount -gt 0) {
                    [int](($siteIndex / $siteCount) * 100)
                }
                else {
                    0
                }
                Write-Progress -Id 1 -Activity "Enumerating site collections in $($webApp.Url)" -Status $progressStatus -PercentComplete $percentComplete

                if ($siteIndex -eq 1 -or $siteIndex % 10 -eq 0 -or
                    ($null -ne $siteCount -and $siteIndex -eq $siteCount)) {
                    Add-SPSInventoryEvent -Message "Enumerating site collections in '$($webApp.Url)' ($progressStatus)." -Level Information | Out-Host
                }

                $exclusionReason = Get-SPSSiteExclusionReason -Url $siteUrl -IncludePersonalSite ([bool]$IncludePersonalSite) -IncludeSiteMaster ([bool]$IncludeSiteMaster)
                if ($exclusionReason -eq 'SiteMaster') {
                    $Exclusion['SiteMasters'] = [int]$Exclusion['SiteMasters'] + 1
                    try {
                        $site.Dispose()
                    }
                    catch {
                        $null = Add-SPSInventoryEvent -Message "Site collection disposal failed for '$siteUrl': $($_.Exception.Message)" -Level Warning
                    }
                    continue
                }

                $rootWeb = $null
                $record = [ordered]@{
                    InventoryScope = 'SiteCollection'
                    Url = $siteUrl
                    Title = ''
                    WebApp = $webApp.Name
                    WebAppUrl = [string]$webApp.Url
                    AuthenticationModes = $authentication.AuthenticationModes
                    AuthenticationZones = $authentication.AuthenticationZones
                    FbaMembershipProviders = $authentication.FbaMembershipProviders
                    FbaRoleProviders = $authentication.FbaRoleProviders
                    HasFbaZone = $authentication.HasFbaZone
                    AuthenticationReviewRequired = $authentication.AuthenticationReviewRequired
                    BrowserFileHandling = if ($null -ne $policy) { $policy.BrowserFileHandling } else { $null }
                    WebAppPolicyCount = if ($null -ne $policy) { $policy.WebAppPolicyCount } else { $null }
                    WebAppPolicyExamples = if ($null -ne $policy) { $policy.WebAppPolicyExamples } else { $null }
                    ContentDb = ''
                    Template = ''
                    IsUnsupportedSiteTemplate = $false
                    TemplateCompatibility = 'Review'
                    TemplateCompatibilityReason = 'Template value is missing.'
                    TemplateLanguageLcid = $null
                    TemplateLanguageTag = ''
                    TemplateLanguageName = ''
                    TemplateLanguageReviewRequired = $true
                    TemplateLanguageReason = 'Template language could not be collected.'
                    SizeGB = $null
                    SubWebCount = $null
                    LastModified = $null
                    SiteInventoryComplete = $true
                    SiteInventoryWarnings = ''
                }

                $templateRead = $false
                $languageRead = $false
                try {
                    try {
                        $rootWeb = $site.RootWeb
                        if ($null -eq $rootWeb) {
                            throw "The root web is unavailable."
                        }

                        # PowerShell turns the exception of a property getter into $null. A root web that cannot be read
                        # (a site collection locked with NoAccess) would then give the template '#' and the language 0, with
                        # no error. Get-SPSPropertyValue keeps the error, and what could not be read stays empty.
                        $rootWebValue = @{}
                        $unreadableProperty = [System.Collections.Generic.List[string]]::new()
                        $firstReadError = ''
                        foreach ($propertyName in @('Title', 'WebTemplate', 'Configuration', 'Language', 'LastItemModifiedDate')) {
                            try {
                                $rootWebValue[$propertyName] = Get-SPSPropertyValue -InputObject $rootWeb -Name $propertyName
                            }
                            catch {
                                $unreadableProperty.Add($propertyName)
                                if ([string]::IsNullOrEmpty($firstReadError)) {
                                    $firstReadError = $_.Exception.Message
                                }
                            }
                        }
                        if ($unreadableProperty.Count -gt 0) {
                            $warnings.Add(('Root web metadata could not be fully read ({0}): {1}' -f ($unreadableProperty -join ', '), $firstReadError))
                        }

                        if ($rootWebValue.ContainsKey('Title')) {
                            $record.Title = $rootWebValue['Title']
                        }
                        if ($rootWebValue.ContainsKey('WebTemplate') -and $rootWebValue.ContainsKey('Configuration')) {
                            $record.Template = '{0}#{1}' -f $rootWebValue['WebTemplate'], $rootWebValue['Configuration']
                            $templateRead = $true
                        }
                        $exclusionReason = Get-SPSSiteExclusionReason -Url $siteUrl -Template $record.Template -IncludePersonalSite ([bool]$IncludePersonalSite) -IncludeSiteMaster ([bool]$IncludeSiteMaster)
                        if ($exclusionReason -eq 'PersonalSite') {
                            $Exclusion['PersonalSites'] = [int]$Exclusion['PersonalSites'] + 1
                            continue
                        }
                        if ($rootWebValue.ContainsKey('LastItemModifiedDate')) {
                            $record.LastModified = $rootWebValue['LastItemModifiedDate']
                        }
                        if ($rootWebValue.ContainsKey('Language')) {
                            $record.TemplateLanguageLcid = [int]$rootWebValue['Language']
                            $languageRead = $true
                        }
                    }
                    catch {
                        $warnings.Add("Root web metadata could not be fully read: $($_.Exception.Message)")
                    }

                    try {
                        $parity = Get-SPSSiteTemplateParity -Template $record.Template -LanguageLcid $record.TemplateLanguageLcid -TemplateParity $TemplateParity
                        # A template or a language that could not be read is not one to review: the site collection is
                        # partial, and the warning and the AssessmentPartial alert say so.
                        if ($templateRead) {
                            $record.IsUnsupportedSiteTemplate = [bool]$parity.IsUnsupportedSiteTemplate
                            $record.TemplateCompatibility = $parity.TemplateCompatibility
                            $record.TemplateCompatibilityReason = $parity.TemplateCompatibilityReason
                        }
                        else {
                            $record.TemplateCompatibility = 'NotCollected'
                            $record.TemplateCompatibilityReason = 'Template could not be collected.'
                        }
                        if ($languageRead) {
                            $record.TemplateLanguageTag = $parity.TemplateLanguageTag
                            $record.TemplateLanguageName = $parity.TemplateLanguageName
                            $record.TemplateLanguageReviewRequired = [bool]$parity.TemplateLanguageReviewRequired
                            $record.TemplateLanguageReason = $parity.TemplateLanguageReason
                        }
                        else {
                            $record.TemplateLanguageReviewRequired = $null
                            $record.TemplateLanguageReason = 'Template language could not be collected.'
                        }
                    }
                    catch {
                        $warnings.Add("Template compatibility mapping failed: $($_.Exception.Message)")
                    }

                    try {
                        $record.ContentDb = $site.ContentDatabase.Name
                    }
                    catch {
                        $warnings.Add("Content database could not be read: $($_.Exception.Message)")
                    }

                    try {
                        $storageBytes = $site.Usage.Storage
                        if ($null -eq $storageBytes) {
                            throw 'Storage usage is unavailable.'
                        }
                        # Four decimals (about 100 KB): with two, every site collection under 5 MB is 0 and so is their total.
                        $record.SizeGB = [math]::Round($storageBytes / 1GB, 4)
                    }
                    catch {
                        $warnings.Add("Storage usage could not be read: $($_.Exception.Message)")
                    }

                    try {
                        $siteWebs = $site.AllWebs
                        if ($null -eq $siteWebs) {
                            throw "The web collection is unavailable."
                        }
                        $record.SubWebCount = $siteWebs.Count
                    }
                    catch {
                        $warnings.Add("Sub-web count could not be read: $($_.Exception.Message)")
                    }
                }
                finally {
                    if ($null -ne $rootWeb) {
                        try {
                            $rootWeb.Dispose()
                        }
                        catch {
                            $warnings.Add("Root web disposal failed: $($_.Exception.Message)")
                        }
                    }
                    try {
                        $site.Dispose()
                    }
                    catch {
                        $warnings.Add("Site collection disposal failed: $($_.Exception.Message)")
                    }
                }

                $record.SiteInventoryComplete = ($warnings.Count -eq 0)
                $record.SiteInventoryWarnings = $warnings -join '; '
                if (-not $record.SiteInventoryComplete) {
                    $null = Add-SPSInventoryEvent -Message "Site inventory is partial for '$siteUrl': $($record.SiteInventoryWarnings)" -Level Warning
                }
                $inventory.Add([PSCustomObject]$record)
            }
        }
        catch {
            $failureMessage = "Site collection enumeration stopped early after $siteIndex site collection(s): $($_.Exception.Message)"
            $null = Add-SPSInventoryEvent -Message "Site enumeration stopped early for web application '$($webApp.Url)': $failureMessage" -Level Warning
            & $addEnumerationFailure $failureMessage
        }
        finally {
            Write-Progress -Id 1 -Activity "Enumerating site collections in $($webApp.Url)" -Completed
        }
    }

    return $inventory.ToArray()
}
