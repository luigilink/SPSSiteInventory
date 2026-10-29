function Get-SPSInventoryAlert {
    <#
        .SYNOPSIS
        Builds the risk alerts of a scored inventory.

        .DESCRIPTION
        Turns the signals of each scored record into alerts: one per site collection and
        signal, one per web application for the policy and browser file handling signals, and
        one per BCS LOB system, per Secure Store target application and per profile synchronization
        connection that has mappings that SharePoint Online does not have. A failed or partial
        assessment and a failed web application enumeration are alerts too, so a gap in the
        inventory is never silent.

        Each alert gets its severity, explanation, remediation and Microsoft Learn reference
        from the alert catalog (see Get-SPSAlertCatalog), so the same signal always gives the
        same advice. The catalog is the one of the target mode: for SharePointOnPrem, the alerts that
        are only about a migration to SharePoint Online are Low and say so, and the others are worded
        for the modernization of the farm. The function is pure: it reads no farm and writes no file.

        Private because it is an implementation detail of Export-SPSInventoryReport.

        .PARAMETER InputObject
        The scored inventory records: site collection rows and web application failure rows.

        .PARAMETER BcsApplication
        Optional BCS LOB system rows from Get-SPSBcsApplication. One alert is raised per LOB
        system.

        .PARAMETER BcsInventoryComplete
        Whether the BCS inventory could be read in full. It only matters when
        BcsApplication is supplied: when false, a BcsInventoryPartial alert is raised.

        .PARAMETER SecureStoreApplication
        Optional Secure Store target application rows from Get-SPSSecureStoreApplication. One
        alert is raised per target application.

        .PARAMETER SecureStoreInventoryComplete
        Whether the Secure Store inventory could be read in full. It only matters when
        SecureStoreApplication is supplied: when false, a SecureStoreInventoryPartial alert is
        raised.

        .PARAMETER ProfilePropertyMapping
        Optional profile property mapping rows from Get-SPSProfilePropertyMapping. One alert is raised
        per connection that has a mapping of a property that SharePoint Online does not fill and that
        SharePoint does not ship (SynchronizedInSharePointOnline false and BuiltInProperty not true).

        .PARAMETER ProfileInventoryComplete
        Whether the profile property mappings could be read in full. It only matters when
        ProfilePropertyMapping is supplied: when false, a ProfilePropertyMappingInventoryPartial alert is
        raised.

        .PARAMETER TargetMode
        SharePointOnline (the default) or SharePointOnPrem. It chooses the catalog of the alerts.
        Any other value is rejected, also when there is no record to alert on.

        .EXAMPLE
        Get-SPSInventoryAlert -InputObject $scored | Where-Object Severity -eq 'High'
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $InputObject,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $BcsApplication = @(),

        [Parameter()]
        [System.Boolean]
        $BcsInventoryComplete = $true,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $SecureStoreApplication = @(),

        [Parameter()]
        [System.Boolean]
        $SecureStoreInventoryComplete = $true,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $ProfilePropertyMapping = @(),

        [Parameter()]
        [System.Boolean]
        $ProfileInventoryComplete = $true,

        [Parameter()]
        [System.String]
        $TargetMode = 'SharePointOnline'
    )

    $null = Get-SPSTargetProfile -TargetMode $TargetMode
    $alerts = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $InputObject) {
        $scope = if ($null -ne $record.PSObject.Properties['InventoryScope']) { [string]$record.InventoryScope } else { 'SiteCollection' }
        if ($scope -eq 'WebApplication') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'WebApplicationEnumerationFailed' -Url $(if ($record.WebAppUrl) { $record.WebAppUrl } else { $record.Url }) -Value $(if ($record.SiteInventoryWarnings) { $record.SiteInventoryWarnings } else { $record.AssessmentWarnings })))
        }
        if ($record.AssessmentStatus -eq 'Failed') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'AssessmentFailed' -Url $($record.Url) -Value $($record.AssessmentWarnings)))
        }
        if ($record.AssessmentStatus -eq 'Partial') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'AssessmentPartial' -Url $($record.Url) -Value $($record.AssessmentWarnings)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.Workflow2010Count -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'Workflow2010' -Url $($record.Url) -Value $([int]$record.Workflow2010Count)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.Workflow2010RunningInstanceCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'Workflow2010Running' -Url $($record.Url) -Value $([int]$record.Workflow2010RunningInstanceCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.Workflow2013Count -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'Workflow2013' -Url $($record.Url) -Value $([int]$record.Workflow2013Count)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.Workflow2013RunningInstanceCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'Workflow2013Running' -Url $($record.Url) -Value $([int]$record.Workflow2013RunningInstanceCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.AppInstanceCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'AppInstances' -Url $($record.Url) -Value $([int]$record.AppInstanceCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.AppWebCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'AppWebs' -Url $($record.Url) -Value $([int]$record.AppWebCount)))
        }
        if ($scope -eq 'SiteCollection' -and ([bool]$record.PublishingInfrastructureEnabled -or [int]$record.PublishingWebCount -gt 0)) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'PublishingSite' -Url $($record.Url) -Value $([int]$record.PublishingWebCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.PublishingPageCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'PublishingPages' -Url $($record.Url) -Value $([int]$record.PublishingPageCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.CustomizedPageCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'CustomizedPages' -Url $($record.Url) -Value $([int]$record.CustomizedPageCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.AlternateCssUrlCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'AlternateCssUrl' -Url $($record.Url) -Value $([int]$record.AlternateCssUrlCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.XsltListViewCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'XsltListViews' -Url $($record.Url) -Value $([int]$record.XsltListViewCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.ScriptWebPartCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'ScriptWebParts' -Url $($record.Url) -Value $([int]$record.ScriptWebPartCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.ClassicExperienceOptOutCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'ModernExperienceOptOut' -Url $($record.Url) -Value $([int]$record.ClassicExperienceOptOutCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.ClassicExperienceListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'ClassicExperienceLists' -Url $($record.Url) -Value $([int]$record.ClassicExperienceListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.CustomPermissionLevelCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'CustomPermissionLevels' -Url $($record.Url) -Value $([int]$record.CustomPermissionLevelCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.EmailEnabledListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'EmailEnabledLists' -Url $($record.Url) -Value $([int]$record.EmailEnabledListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.HtmlFileCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'HtmlFiles' -Url $($record.Url) -Value $([int]$record.HtmlFileCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.ManagedMetadataListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'ManagedMetadataColumns' -Url $($record.Url) -Value $([int]$record.ManagedMetadataListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.ExternalListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'ExternalLists' -Url $($record.Url) -Value $([int]$record.ExternalListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.SharePointAlertCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'AlertSubscriptions' -Url $($record.Url) -Value $([int]$record.SharePointAlertCount)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.IsUnsupportedSiteTemplate) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'UnsupportedSiteTemplate' -Url $($record.Url) -Value $($record.Template) -Message ([string]$record.TemplateCompatibilityReason)))
        }
        if ($scope -eq 'SiteCollection' -and -not [bool]$record.IsUnsupportedSiteTemplate -and [string]$record.TemplateCompatibility -eq 'Review') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'TemplateCompatibilityReview' -Url $($record.Url) -Value $($record.Template) -Message ([string]$record.TemplateCompatibilityReason)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.TemplateLanguageReviewRequired) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'TemplateLanguageReview' -Url $($record.Url) -Value $(if ($null -ne $record.TemplateLanguageLcid) { [int]$record.TemplateLanguageLcid } else { $null }) -Message ([string]$record.TemplateLanguageReason)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.InfoPathFormCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'InfoPath' -Url $($record.Url) -Value $([int]$record.InfoPathFormCount)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.UsesFullTrustCode) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'FullTrustCode' -Url $($record.Url) -Value $($true)))
        }
        if ([bool]$record.HasFbaZone) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'FbaConfigured' -Url $($record.Url) -Value $($true)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.HasNoAccessLock) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'NoAccessSite' -Url $($record.Url) -Value $($record.SiteLockState)))
        }
        elseif ($scope -eq 'SiteCollection' -and [bool]$record.IsLockedSite) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'LockedSite' -Url $($record.Url) -Value $($record.SiteLockState)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.IrmEnabledListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'IrmEnabledLists' -Url $($record.Url) -Value $([int]$record.IrmEnabledListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.IsLargeSite) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'LargeSite' -Url $($record.Url) -Value $($record.SizeGB)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.LargeListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'LargeLists' -Url $($record.Url) -Value $([int]$record.LargeListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.LargeListViewCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'LargeListViews' -Url $($record.Url) -Value $([int]$record.LargeListViewCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.CheckedOutFileCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'CheckedOutFiles' -Url $($record.Url) -Value $([int]$record.CheckedOutFileCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.FileVersionCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'FileVersions' -Url $($record.Url) -Value $([int]$record.FileVersionCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.LargeExcelFileCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'LargeExcelFiles' -Url $($record.Url) -Value $([int]$record.LargeExcelFileCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.AudienceTargetedItemCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'AudienceTargeting' -Url $($record.Url) -Value $([int]$record.AudienceTargetedItemCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.SiteNotebookCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'SiteNotebook' -Url $($record.Url) -Value $([int]$record.SiteNotebookCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.CustomizedProfilePageCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'CustomizedProfilePage' -Url $($record.Url) -Value $([int]$record.CustomizedProfilePageCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.SubsiteCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'Subsites' -Url $($record.Url) -Value $([int]$record.SubsiteCount)))
        }
    }

    # Policies and browser file handling belong to the web application, so alert once per web application.
    foreach ($group in ($InputObject | Where-Object { $_.WebAppUrl } | Group-Object -Property WebAppUrl)) {
        $webAppRecord = $group.Group[0]
        if ([int]$webAppRecord.WebAppPolicyCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'WebApplicationPolicies' -Url $($webAppRecord.WebAppUrl) -Value $([int]$webAppRecord.WebAppPolicyCount)))
        }
        if ([string]$webAppRecord.BrowserFileHandling -eq 'Permissive') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'PermissiveBrowserFileHandling' -Url $($webAppRecord.WebAppUrl) -Value $('Permissive')))
        }
    }

    # BCS applications belong to the farm, so alert once per LOB system rather than per site.
    foreach ($bcsApplicationRow in @($BcsApplication)) {
        $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'BcsApplication' -Url $(([string]$bcsApplicationRow.WebApplicationUrls -split '; ')[0]) -Value $([string]$bcsApplicationRow.LobSystemName)))
    }
    if ($PSBoundParameters.ContainsKey('BcsApplication') -and -not $BcsInventoryComplete) {
        $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'BcsInventoryPartial' -Url $('') -Value $($false)))
    }

    # Secure Store target applications belong to the farm too: one alert per target application.
    foreach ($secureStoreRow in @($SecureStoreApplication)) {
        $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'SecureStoreApplication' -Url $(([string]$secureStoreRow.WebApplicationUrls -split '; ')[0]) -Value $([string]$secureStoreRow.Name)))
    }
    if ($PSBoundParameters.ContainsKey('SecureStoreApplication') -and -not $SecureStoreInventoryComplete) {
        $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'SecureStoreInventoryPartial' -Url $('') -Value $($false)))
    }

    # Profile property mappings belong to the farm too: one alert per connection that has mappings that the target does not have.
    # The connections are told apart by their service as well as by their name, and listed in the order of the rows.
    $mappingGroups = [ordered]@{}
    foreach ($customMapping in @($ProfilePropertyMapping | Where-Object { $null -ne $_ -and -not [bool]$_.SynchronizedInSharePointOnline -and $_.BuiltInProperty -ne $true })) {
        $groupKey = '{0}|{1}|{2}' -f [string]$customMapping.WebApplicationUrls, [string]$customMapping.UserProfileProxyId, [string]$customMapping.ConnectionName
        if (-not $mappingGroups.Contains($groupKey)) {
            $mappingGroups[$groupKey] = [PSCustomObject]@{ First = $customMapping; Count = 0 }
        }
        $mappingGroups[$groupKey].Count++
    }
    foreach ($mappingGroup in $mappingGroups.Values) {
        $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'ProfilePropertyMapping' -Url $(([string]$mappingGroup.First.WebApplicationUrls -split '; ')[0]) -Value $('{0}: {1} mapping(s)' -f [string]$mappingGroup.First.ConnectionName, $mappingGroup.Count)))
    }
    if ($PSBoundParameters.ContainsKey('ProfilePropertyMapping') -and -not $ProfileInventoryComplete) {
        $alerts.Add((ConvertTo-SPSInventoryAlert -TargetMode $TargetMode -AlertType 'ProfilePropertyMappingInventoryPartial' -Url $('') -Value $($false)))
    }

    return $alerts.ToArray()
}
