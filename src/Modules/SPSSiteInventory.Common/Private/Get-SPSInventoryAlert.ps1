function Get-SPSInventoryAlert {
    <#
        .SYNOPSIS
        Builds the risk alerts of a scored inventory.

        .DESCRIPTION
        Turns the signals of each scored record into alerts: one per site collection and
        signal, one per web application for the policy and browser file handling signals, and
        one per BCS LOB system. A failed or partial assessment and a failed web application
        enumeration are alerts too, so a gap in the inventory is never silent.

        Each alert gets its severity, explanation, remediation and Microsoft Learn reference
        from the alert catalog (see Get-SPSAlertCatalog), so the same signal always gives the
        same advice. The function is pure: it reads no farm and writes no file.

        Private because it is an implementation detail of Export-SPSInventoryReport.

        .PARAMETER InputObject
        The scored inventory records: site collection rows and web application failure rows.

        .PARAMETER BcsApplication
        Optional BCS LOB system rows from Get-SPSBcsApplication. One alert is raised per LOB
        system.

        .PARAMETER BcsInventoryComplete
        Whether the BCS inventory could be read in full. It only matters when
        BcsApplication is supplied: when false, a BcsInventoryPartial alert is raised.

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
        $BcsInventoryComplete = $true
    )

    $alerts = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $InputObject) {
        $scope = if ($null -ne $record.PSObject.Properties['InventoryScope']) { [string]$record.InventoryScope } else { 'SiteCollection' }
        if ($scope -eq 'WebApplication') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'WebApplicationEnumerationFailed' -Url $(if ($record.WebAppUrl) { $record.WebAppUrl } else { $record.Url }) -Value $(if ($record.SiteInventoryWarnings) { $record.SiteInventoryWarnings } else { $record.AssessmentWarnings })))
        }
        if ($record.AssessmentStatus -eq 'Failed') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'AssessmentFailed' -Url $($record.Url) -Value $($record.AssessmentWarnings)))
        }
        if ($record.AssessmentStatus -eq 'Partial') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'AssessmentPartial' -Url $($record.Url) -Value $($record.AssessmentWarnings)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.Workflow2010Count -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'Workflow2010' -Url $($record.Url) -Value $([int]$record.Workflow2010Count)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.Workflow2010RunningInstanceCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'Workflow2010Running' -Url $($record.Url) -Value $([int]$record.Workflow2010RunningInstanceCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.Workflow2013Count -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'Workflow2013' -Url $($record.Url) -Value $([int]$record.Workflow2013Count)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.Workflow2013RunningInstanceCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'Workflow2013Running' -Url $($record.Url) -Value $([int]$record.Workflow2013RunningInstanceCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.AppInstanceCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'AppInstances' -Url $($record.Url) -Value $([int]$record.AppInstanceCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.AppWebCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'AppWebs' -Url $($record.Url) -Value $([int]$record.AppWebCount)))
        }
        if ($scope -eq 'SiteCollection' -and ([bool]$record.PublishingInfrastructureEnabled -or [int]$record.PublishingWebCount -gt 0)) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'PublishingSite' -Url $($record.Url) -Value $([int]$record.PublishingWebCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.PublishingPageCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'PublishingPages' -Url $($record.Url) -Value $([int]$record.PublishingPageCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.CustomizedPageCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'CustomizedPages' -Url $($record.Url) -Value $([int]$record.CustomizedPageCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.CustomPermissionLevelCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'CustomPermissionLevels' -Url $($record.Url) -Value $([int]$record.CustomPermissionLevelCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.EmailEnabledListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'EmailEnabledLists' -Url $($record.Url) -Value $([int]$record.EmailEnabledListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.HtmlFileCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'HtmlFiles' -Url $($record.Url) -Value $([int]$record.HtmlFileCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.ManagedMetadataListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'ManagedMetadataColumns' -Url $($record.Url) -Value $([int]$record.ManagedMetadataListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.ExternalListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'ExternalLists' -Url $($record.Url) -Value $([int]$record.ExternalListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.SharePointAlertCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'AlertSubscriptions' -Url $($record.Url) -Value $([int]$record.SharePointAlertCount)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.IsUnsupportedSiteTemplate) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'UnsupportedSiteTemplate' -Url $($record.Url) -Value $($record.Template) -Message ([string]$record.TemplateCompatibilityReason)))
        }
        if ($scope -eq 'SiteCollection' -and -not [bool]$record.IsUnsupportedSiteTemplate -and [string]$record.TemplateCompatibility -eq 'Review') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'TemplateCompatibilityReview' -Url $($record.Url) -Value $($record.Template) -Message ([string]$record.TemplateCompatibilityReason)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.TemplateLanguageReviewRequired) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'TemplateLanguageReview' -Url $($record.Url) -Value $(if ($null -ne $record.TemplateLanguageLcid) { [int]$record.TemplateLanguageLcid } else { $null }) -Message ([string]$record.TemplateLanguageReason)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.InfoPathFormCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'InfoPath' -Url $($record.Url) -Value $([int]$record.InfoPathFormCount)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.UsesFullTrustCode) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'FullTrustCode' -Url $($record.Url) -Value $($true)))
        }
        if ([bool]$record.HasFbaZone) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'FbaConfigured' -Url $($record.Url) -Value $($true)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.HasNoAccessLock) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'NoAccessSite' -Url $($record.Url) -Value $($record.SiteLockState)))
        }
        elseif ($scope -eq 'SiteCollection' -and [bool]$record.IsLockedSite) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'LockedSite' -Url $($record.Url) -Value $($record.SiteLockState)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.IrmEnabledListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'IrmEnabledLists' -Url $($record.Url) -Value $([int]$record.IrmEnabledListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [bool]$record.IsLargeSite) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'LargeSite' -Url $($record.Url) -Value $($record.SizeGB)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.LargeListCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'LargeLists' -Url $($record.Url) -Value $([int]$record.LargeListCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.LargeListViewCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'LargeListViews' -Url $($record.Url) -Value $([int]$record.LargeListViewCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.CheckedOutFileCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'CheckedOutFiles' -Url $($record.Url) -Value $([int]$record.CheckedOutFileCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.FileVersionCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'FileVersions' -Url $($record.Url) -Value $([int]$record.FileVersionCount)))
        }
        if ($scope -eq 'SiteCollection' -and [int]$record.SubsiteCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'Subsites' -Url $($record.Url) -Value $([int]$record.SubsiteCount)))
        }
    }

    # Policies and browser file handling belong to the web application, so alert once per web application.
    foreach ($group in ($InputObject | Where-Object { $_.WebAppUrl } | Group-Object -Property WebAppUrl)) {
        $webAppRecord = $group.Group[0]
        if ([int]$webAppRecord.WebAppPolicyCount -gt 0) {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'WebApplicationPolicies' -Url $($webAppRecord.WebAppUrl) -Value $([int]$webAppRecord.WebAppPolicyCount)))
        }
        if ([string]$webAppRecord.BrowserFileHandling -eq 'Permissive') {
            $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'PermissiveBrowserFileHandling' -Url $($webAppRecord.WebAppUrl) -Value $('Permissive')))
        }
    }

    # BCS applications belong to the farm, so alert once per LOB system rather than per site.
    foreach ($bcsApplicationRow in @($BcsApplication)) {
        $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'BcsApplication' -Url $(([string]$bcsApplicationRow.WebApplicationUrls -split '; ')[0]) -Value $([string]$bcsApplicationRow.LobSystemName)))
    }
    if ($PSBoundParameters.ContainsKey('BcsApplication') -and -not $BcsInventoryComplete) {
        $alerts.Add((ConvertTo-SPSInventoryAlert -AlertType 'BcsInventoryPartial' -Url $('') -Value $($false)))
    }

    return $alerts.ToArray()
}
