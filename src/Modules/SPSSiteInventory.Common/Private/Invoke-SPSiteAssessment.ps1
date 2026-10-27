function Invoke-SPSiteAssessment {
    <#
        .SYNOPSIS
        Collects customization signals and scores each site while preserving failed rows.

        .DESCRIPTION
        Processes the site records from Get-SPSSiteInventory. A failed site is retained
        without a score and does not prevent the remaining sites from being assessed.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Inventory,

        [Parameter()]
        [System.String[]]
        $CustomFeatureId = @(),

        [Parameter()]
        [System.String[]]
        $FullTrustFeatureId = @(),

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Scoring,

        [Parameter()]
        [System.Collections.IDictionary]
        $LargeContentThresholds = @{},

        [Parameter()]
        [System.Collections.IDictionary]
        $PermissionLevels = @{},

        [Parameter()]
        [System.Collections.IDictionary]
        $SharePointAlertSettings = @{}
    )

    # Fail before any site is read when the alert settings are invalid.
    $null = Get-SPSSharePointAlertOption -Settings $SharePointAlertSettings

    $contentTypes = [System.Collections.Generic.List[object]]::new()
    $managedMetadataLists = [System.Collections.Generic.List[object]]::new()
    $externalLists = [System.Collections.Generic.List[object]]::new()
    $sharePointAlerts = [System.Collections.Generic.List[object]]::new()
    $scored = [System.Collections.Generic.List[object]]::new()
    $siteTotal = $Inventory.Count
    $siteIndex = 0
    $largeSiteSizeThresholdGb = Get-SPSNumericThreshold -Thresholds $LargeContentThresholds -Name 'LargeSiteSizeGB' -DefaultValue 100 -MinimumValue 0

    try {
        foreach ($item in $Inventory) {
            $siteIndex++
            $inventoryScope = 'SiteCollection'
            if ($null -ne $item.PSObject.Properties['InventoryScope']) {
                $inventoryScope = [string]$item.InventoryScope
            }
            $percentComplete = if ($siteTotal -gt 0) { [int](($siteIndex / $siteTotal) * 100) } else { 0 }
            $progressStatus = '{0}/{1}: {2}' -f $siteIndex, $siteTotal, $item.Url
            Write-Progress -Id 2 -Activity 'Collecting customization and scoring site collections' -Status $progressStatus -PercentComplete $percentComplete
            if ($siteIndex -eq 1 -or $siteIndex % 10 -eq 0 -or $siteIndex -eq $siteTotal) {
                Add-SPSInventoryEvent -Message "Collecting customization signals ($progressStatus)." -Level Information | Out-Host
            }

            $site = $null
            $siteWarnings = [System.Collections.Generic.List[string]]::new()
            $siteInventoryComplete = $true
            if ($null -ne $item.PSObject.Properties['SiteInventoryComplete']) {
                $siteInventoryComplete = [bool]$item.SiteInventoryComplete
            }
            if ($inventoryScope -ne 'WebApplication' -and -not $siteInventoryComplete -and $item.SiteInventoryWarnings) {
                $siteWarnings.Add("Site inventory partial: $($item.SiteInventoryWarnings)")
            }

            try {
                if ($inventoryScope -eq 'WebApplication') {
                    throw "Site collection enumeration failed for web application '$($item.WebApp)': $($item.SiteInventoryWarnings)"
                }
                $site = Get-SPSite -Identity $item.Url -ErrorAction Stop
                if ($null -eq $site) {
                    throw "SharePoint did not return a site collection for '$($item.Url)'."
                }
                $customizationWarnings = @()
                # HTML files only matter where browser file handling is Permissive; SharePoint Online enforces Strict.
                $scanHtmlFile = [string]$item.BrowserFileHandling -eq 'Permissive'
                $signals = Get-SPSSiteCustomization -Site $site -CustomFeatureId $CustomFeatureId -FullTrustFeatureId $FullTrustFeatureId -LargeContentThresholds $LargeContentThresholds -PermissionLevels $PermissionLevels -SharePointAlertSettings $SharePointAlertSettings -ScanHtmlFile:$scanHtmlFile -WarningVariable customizationWarnings
                foreach ($warning in $customizationWarnings) {
                    $siteWarnings.Add([string]$warning)
                }
                $signals['SizeGB'] = $item.SizeGB
                $signals['HasFbaZone'] = $item.HasFbaZone
                $signals['IsUnsupportedSiteTemplate'] = $item.IsUnsupportedSiteTemplate
                $signals['TemplateLanguageReviewRequired'] = $item.TemplateLanguageReviewRequired
                $signals['IsLargeSite'] = $false
                if ($null -ne $item.SizeGB) {
                    try {
                        if ([double]$item.SizeGB -ge $largeSiteSizeThresholdGb) {
                            $signals['IsLargeSite'] = $true
                        }
                    }
                    catch {
                        $signals['IsLargeSite'] = $false
                    }
                }
                foreach ($contentType in $signals.ContentTypes) {
                    $contentTypes.Add($contentType)
                }
                foreach ($managedMetadataList in $signals.ManagedMetadataLists) {
                    $managedMetadataLists.Add($managedMetadataList)
                }
                foreach ($externalList in $signals.ExternalLists) {
                    $externalLists.Add($externalList)
                }
                foreach ($sharePointAlert in $signals.SharePointAlerts) {
                    $sharePointAlerts.Add($sharePointAlert)
                }

                $result = Measure-SPSSiteComplexity -Signals $signals -Scoring $Scoring
                $customizationComplete = $true
                if ($null -ne $signals['CustomizationInventoryComplete']) {
                    $customizationComplete = [bool]$signals['CustomizationInventoryComplete']
                }
                $contentTypeComplete = [bool]$signals['ContentTypeInventoryComplete']
                if (-not $customizationComplete) {
                    $siteWarnings.Add('Customization inventory partial; some signals may be missing.')
                }
                if (-not $contentTypeComplete) {
                    $siteWarnings.Add('Content-type inventory partial; content-type counts may be incomplete.')
                }

                $assessmentStatus = if ($siteInventoryComplete -and $customizationComplete -and $contentTypeComplete) { 'Complete' } else { 'Partial' }
                $reasons = @($result.Reasons) + @($siteWarnings.ToArray())
                $scored.Add([PSCustomObject]@{
                    InventoryScope = $inventoryScope
                    Url = $item.Url
                    Title = $item.Title
                    WebApp = $item.WebApp
                    WebAppUrl = $item.WebAppUrl
                    AuthenticationModes = $item.AuthenticationModes
                    AuthenticationZones = $item.AuthenticationZones
                    FbaMembershipProviders = $item.FbaMembershipProviders
                    FbaRoleProviders = $item.FbaRoleProviders
                    HasFbaZone = $item.HasFbaZone
                    AuthenticationReviewRequired = $item.AuthenticationReviewRequired
                    BrowserFileHandling = $item.BrowserFileHandling
                    WebAppPolicyCount = $item.WebAppPolicyCount
                    WebAppPolicyExamples = $item.WebAppPolicyExamples
                    ContentDb = $item.ContentDb
                    Template = $item.Template
                    IsUnsupportedSiteTemplate = $item.IsUnsupportedSiteTemplate
                    TemplateCompatibility = $item.TemplateCompatibility
                    TemplateCompatibilityReason = $item.TemplateCompatibilityReason
                    TemplateLanguageLcid = $item.TemplateLanguageLcid
                    TemplateLanguageTag = $item.TemplateLanguageTag
                    TemplateLanguageName = $item.TemplateLanguageName
                    TemplateLanguageReviewRequired = $item.TemplateLanguageReviewRequired
                    TemplateLanguageReason = $item.TemplateLanguageReason
                    SizeGB = $item.SizeGB
                    SubWebCount = $item.SubWebCount
                    SubsiteCount = $signals['SubsiteCount']
                    MaxSubsiteDepth = $signals['MaxSubsiteDepth']
                    SubsiteExamples = $signals['SubsiteExamples']
                    LastModified = $item.LastModified
                    SiteInventoryComplete = $siteInventoryComplete
                    SiteInventoryWarnings = $item.SiteInventoryWarnings
                    CustomizationInventoryComplete = $customizationComplete
                    ContentTypeInventoryComplete = $contentTypeComplete
                    AssessmentStatus = $assessmentStatus
                    AssessmentWarnings = $siteWarnings -join '; '
                    Workflow2010Count = $signals['Workflow2010Count']
                    Workflow2010RunningInstanceCount = $signals['Workflow2010RunningInstanceCount']
                    Workflow2013Count = $signals['Workflow2013Count']
                    Workflow2013RunningInstanceCount = $signals['Workflow2013RunningInstanceCount']
                    AppInstanceCount = $signals['AppInstanceCount']
                    AppWebCount = $signals['AppWebCount']
                    AppInstanceExamples = $signals['AppInstanceExamples']
                    PublishingInfrastructureEnabled = $signals['PublishingInfrastructureEnabled']
                    PublishingWebCount = $signals['PublishingWebCount']
                    PublishingPageCount = $signals['PublishingPageCount']
                    PublishingPageLayoutCount = $signals['PublishingPageLayoutCount']
                    PublishingPageLayoutExamples = $signals['PublishingPageLayoutExamples']
                    CustomizedPageCount = $signals['CustomizedPageCount']
                    CustomizedPageExamples = $signals['CustomizedPageExamples']
                    CustomPermissionLevelCount = $signals['CustomPermissionLevelCount']
                    CustomPermissionLevelExamples = $signals['CustomPermissionLevelExamples']
                    EmailEnabledListCount = $signals['EmailEnabledListCount']
                    EmailEnabledListExamples = $signals['EmailEnabledListExamples']
                    HtmlFileCount = $signals['HtmlFileCount']
                    HtmlFileExamples = $signals['HtmlFileExamples']
                    ManagedMetadataListCount = $signals['ManagedMetadataListCount']
                    ManagedMetadataColumnCount = $signals['ManagedMetadataColumnCount']
                    ManagedMetadataTermSetCount = $signals['ManagedMetadataTermSetCount']
                    ManagedMetadataExamples = $signals['ManagedMetadataExamples']
                    ExternalListCount = $signals['ExternalListCount']
                    ExternalListExamples = $signals['ExternalListExamples']
                    SharePointAlertCount = $signals['SharePointAlertCount']
                    InfoPathFormCount = $signals['InfoPathFormCount']
                    IrmEnabledListCount = $signals['IrmEnabledListCount']
                    IsLargeSite = $signals['IsLargeSite']
                    LargeListCount = $signals['LargeListCount']
                    LargeListExamples = $signals['LargeListExamples']
                    LargeListViewCount = $signals['LargeListViewCount']
                    LargeListViewExamples = $signals['LargeListViewExamples']
                    CheckedOutFileCount = $signals['CheckedOutFileCount']
                    CheckedOutFileExamples = $signals['CheckedOutFileExamples']
                    FileVersionCount = $signals['FileVersionCount']
                    FileVersionExamples = $signals['FileVersionExamples']
                    IsLockedSite = $signals['IsLockedSite']
                    HasNoAccessLock = $signals['HasNoAccessLock']
                    SiteLockState = $signals['SiteLockState']
                    UsesFullTrustCode = $signals['UsesFullTrustCode']
                    UsesCustomFarmFeature = $signals['UsesCustomFarmFeature']
                    SandboxSolutions = $signals['SandboxSolutions']
                    CustomMasterPage = $signals['CustomMasterPage']
                    EventReceivers = $signals['EventReceivers']
                    UniquePermissionsCount = $signals['UniquePermissionsCount']
                    ContentTypeCount = $signals['ContentTypeCount']
                    ListContentTypeBindingCount = $signals['ListContentTypeBindingCount']
                    Category = $result.Category
                    CategoryName = $result.CategoryName
                    Score = $result.Score
                    Reasons = ($reasons -join '; ')
                })
            }
            catch {
                $errorMessage = $_.Exception.Message
                $siteWarnings.Add("Assessment failed: $errorMessage")
                $null = Add-SPSInventoryEvent -Message "Assessment failed for '$($item.Url)'; continuing with the next site. $errorMessage" -Level Warning
                $scored.Add([PSCustomObject]@{
                    InventoryScope = $inventoryScope
                    Url = $item.Url
                    Title = $item.Title
                    WebApp = $item.WebApp
                    WebAppUrl = $item.WebAppUrl
                    AuthenticationModes = $item.AuthenticationModes
                    AuthenticationZones = $item.AuthenticationZones
                    FbaMembershipProviders = $item.FbaMembershipProviders
                    FbaRoleProviders = $item.FbaRoleProviders
                    HasFbaZone = $item.HasFbaZone
                    AuthenticationReviewRequired = $item.AuthenticationReviewRequired
                    BrowserFileHandling = $item.BrowserFileHandling
                    WebAppPolicyCount = $item.WebAppPolicyCount
                    WebAppPolicyExamples = $item.WebAppPolicyExamples
                    ContentDb = $item.ContentDb
                    Template = $item.Template
                    IsUnsupportedSiteTemplate = $item.IsUnsupportedSiteTemplate
                    TemplateCompatibility = $item.TemplateCompatibility
                    TemplateCompatibilityReason = $item.TemplateCompatibilityReason
                    TemplateLanguageLcid = $item.TemplateLanguageLcid
                    TemplateLanguageTag = $item.TemplateLanguageTag
                    TemplateLanguageName = $item.TemplateLanguageName
                    TemplateLanguageReviewRequired = $item.TemplateLanguageReviewRequired
                    TemplateLanguageReason = $item.TemplateLanguageReason
                    SizeGB = $item.SizeGB
                    SubWebCount = $item.SubWebCount
                    SubsiteCount = $null
                    MaxSubsiteDepth = $null
                    SubsiteExamples = $null
                    LastModified = $item.LastModified
                    SiteInventoryComplete = $siteInventoryComplete
                    SiteInventoryWarnings = $item.SiteInventoryWarnings
                    CustomizationInventoryComplete = $false
                    ContentTypeInventoryComplete = $false
                    AssessmentStatus = 'Failed'
                    AssessmentWarnings = $siteWarnings -join '; '
                    Workflow2010Count = $null
                    Workflow2010RunningInstanceCount = $null
                    Workflow2013Count = $null
                    Workflow2013RunningInstanceCount = $null
                    AppInstanceCount = $null
                    AppWebCount = $null
                    AppInstanceExamples = $null
                    PublishingInfrastructureEnabled = $null
                    PublishingWebCount = $null
                    PublishingPageCount = $null
                    PublishingPageLayoutCount = $null
                    PublishingPageLayoutExamples = $null
                    CustomizedPageCount = $null
                    CustomizedPageExamples = $null
                    CustomPermissionLevelCount = $null
                    CustomPermissionLevelExamples = $null
                    EmailEnabledListCount = $null
                    EmailEnabledListExamples = $null
                    HtmlFileCount = $null
                    HtmlFileExamples = $null
                    ManagedMetadataListCount = $null
                    ManagedMetadataColumnCount = $null
                    ManagedMetadataTermSetCount = $null
                    ManagedMetadataExamples = $null
                    ExternalListCount = $null
                    ExternalListExamples = $null
                    SharePointAlertCount = $null
                    InfoPathFormCount = $null
                    IrmEnabledListCount = $null
                    IsLargeSite = $null
                    LargeListCount = $null
                    LargeListExamples = $null
                    LargeListViewCount = $null
                    LargeListViewExamples = $null
                    CheckedOutFileCount = $null
                    CheckedOutFileExamples = $null
                    FileVersionCount = $null
                    FileVersionExamples = $null
                    IsLockedSite = $null
                    HasNoAccessLock = $null
                    SiteLockState = $null
                    UsesFullTrustCode = $null
                    UsesCustomFarmFeature = $null
                    SandboxSolutions = $null
                    CustomMasterPage = $null
                    EventReceivers = $null
                    UniquePermissionsCount = $null
                    ContentTypeCount = $null
                    ListContentTypeBindingCount = $null
                    Category = $null
                    CategoryName = 'Not assessed'
                    Score = $null
                    Reasons = $siteWarnings -join '; '
                })
            }
            finally {
                if ($null -ne $site) {
                    try {
                        $site.Dispose()
                    }
                    catch {
                        $null = Add-SPSInventoryEvent -Message "Could not dispose site collection '$($item.Url)': $($_.Exception.Message)" -Level Warning
                    }
                }
            }
        }
    }
    finally {
        Write-Progress -Id 2 -Activity 'Collecting customization and scoring site collections' -Completed
    }

    [PSCustomObject]@{
        Inventory = $scored.ToArray()
        ContentTypes = $contentTypes.ToArray()
        ManagedMetadataLists = $managedMetadataLists.ToArray()
        ExternalLists = $externalLists.ToArray()
        SharePointAlerts = $sharePointAlerts.ToArray()
    }
}
