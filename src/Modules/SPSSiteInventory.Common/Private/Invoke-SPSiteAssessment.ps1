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
        $Scoring
    )

    $contentTypes = [System.Collections.Generic.List[object]]::new()
    $scored = [System.Collections.Generic.List[object]]::new()
    $siteTotal = $Inventory.Count
    $siteIndex = 0

    try {
        foreach ($item in $Inventory) {
            $siteIndex++
            $percentComplete = if ($siteTotal -gt 0) { [int](($siteIndex / $siteTotal) * 100) } else { 0 }
            $progressStatus = '{0}/{1}: {2}' -f $siteIndex, $siteTotal, $item.Url
            Write-Progress -Id 2 -Activity 'Collecting customization and scoring site collections' -Status $progressStatus -PercentComplete $percentComplete
            if ($siteIndex -eq 1 -or $siteIndex % 10 -eq 0 -or $siteIndex -eq $siteTotal) {
                $null = Add-SPSInventoryEvent -Message "Collecting customization signals ($progressStatus)." -Level Information
            }

            $site = $null
            $siteWarnings = [System.Collections.Generic.List[string]]::new()
            $siteInventoryComplete = $true
            if ($null -ne $item.PSObject.Properties['SiteInventoryComplete']) {
                $siteInventoryComplete = [bool]$item.SiteInventoryComplete
            }
            if (-not $siteInventoryComplete -and $item.SiteInventoryWarnings) {
                $siteWarnings.Add("Site inventory partial: $($item.SiteInventoryWarnings)")
            }

            try {
                $site = Get-SPSite -Identity $item.Url -ErrorAction Stop
                if ($null -eq $site) {
                    throw "SharePoint did not return a site collection for '$($item.Url)'."
                }
                $signals = Get-SPSSiteCustomization -Site $site -CustomFeatureId $CustomFeatureId -FullTrustFeatureId $FullTrustFeatureId
                $signals['SizeGB'] = $item.SizeGB
                $signals['HasFbaZone'] = $item.HasFbaZone
                foreach ($contentType in $signals.ContentTypes) {
                    $contentTypes.Add($contentType)
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
                    ContentDb = $item.ContentDb
                    Template = $item.Template
                    SizeGB = $item.SizeGB
                    SubWebCount = $item.SubWebCount
                    LastModified = $item.LastModified
                    SiteInventoryComplete = $siteInventoryComplete
                    SiteInventoryWarnings = $item.SiteInventoryWarnings
                    CustomizationInventoryComplete = $customizationComplete
                    ContentTypeInventoryComplete = $contentTypeComplete
                    AssessmentStatus = $assessmentStatus
                    AssessmentWarnings = $siteWarnings -join '; '
                    Workflow2010Count = $signals['Workflow2010Count']
                    Workflow2013Count = $signals['Workflow2013Count']
                    InfoPathFormCount = $signals['InfoPathFormCount']
                    UsesFullTrustCode = $signals['UsesFullTrustCode']
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
                    ContentDb = $item.ContentDb
                    Template = $item.Template
                    SizeGB = $item.SizeGB
                    SubWebCount = $item.SubWebCount
                    LastModified = $item.LastModified
                    SiteInventoryComplete = $siteInventoryComplete
                    SiteInventoryWarnings = $item.SiteInventoryWarnings
                    CustomizationInventoryComplete = $false
                    ContentTypeInventoryComplete = $false
                    AssessmentStatus = 'Failed'
                    AssessmentWarnings = $siteWarnings -join '; '
                    Workflow2010Count = $null
                    Workflow2013Count = $null
                    InfoPathFormCount = $null
                    UsesFullTrustCode = $null
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
    }
}
