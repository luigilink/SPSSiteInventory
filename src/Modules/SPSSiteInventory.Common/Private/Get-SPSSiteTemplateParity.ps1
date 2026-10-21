function Get-SPSSiteTemplateParity {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.String]
        $Template,

        [Parameter()]
        [AllowNull()]
        [System.Nullable[int]]
        $LanguageLcid,

        [Parameter()]
        [System.Collections.IDictionary]
        $TemplateParity = @{}
    )

    $supportedTemplatePrefixes = @(
        'STS#',
        'COMMUNITY#',
        'PROJECTSITE#',
        'SITEPAGEPUBLISHING#',
        'CMSPUBLISHING#',
        'BLANKINTERNET#',
        'SRCHCEN#',
        'WIKI#',
        'ENTERWIKI#',
        'BDR#',
        'OFFILE#',
        'GROUP#',
        'SPSPERS#',
        'SPSNEWS#',
        'SPSNHOME#'
    )
    if ($TemplateParity.Contains('SupportedTemplatePrefixes')) {
        $supportedTemplatePrefixes = @($TemplateParity.SupportedTemplatePrefixes)
    }

    $unsupportedTemplateReasons = @{
        'APP#0' = 'App web templates are not migration targets in SharePoint Online.'
        'SPSMSITEHOST#0' = 'My Site host templates are not migrated as site collections to SharePoint Online.'
    }
    $unsupportedTemplates = @($unsupportedTemplateReasons.Keys)
    if ($TemplateParity.Contains('UnsupportedTemplates')) {
        $unsupportedTemplates = @($TemplateParity.UnsupportedTemplates)
    }
    $reviewTemplatePrefixes = @('BLOG#')
    if ($TemplateParity.Contains('ReviewTemplatePrefixes')) {
        $reviewTemplatePrefixes = @($TemplateParity.ReviewTemplatePrefixes)
    }
    $reviewTemplateReasons = @{
        'BLOG#' = 'Blog templates require remapping for SharePoint Online and should be reviewed.'
    }
    $compatibleTemplateReasons = @{
        'SPSPERS#0' = 'Personal site templates are supported migration sources and map to OneDrive in SharePoint Online.'
    }
    $supportedLanguageLcid = @()
    if ($TemplateParity.Contains('SupportedLanguageLcid')) {
        $supportedLanguageLcid = @($TemplateParity.SupportedLanguageLcid)
    }

    $normalizedTemplate = ''
    if (-not [string]::IsNullOrWhiteSpace($Template)) {
        $normalizedTemplate = $Template.Trim().ToUpperInvariant()
    }

    $templateCompatibility = 'Review'
    $templateCompatibilityReason = 'Template value is missing.'
    $isUnsupportedTemplate = $false

    if (-not [string]::IsNullOrWhiteSpace($normalizedTemplate)) {
        if ($unsupportedTemplates -icontains $normalizedTemplate) {
            $templateCompatibility = 'Unsupported'
            $isUnsupportedTemplate = $true
            if ($unsupportedTemplateReasons.ContainsKey($normalizedTemplate)) {
                $templateCompatibilityReason = $unsupportedTemplateReasons[$normalizedTemplate]
            }
            else {
                $templateCompatibilityReason = "Template '$normalizedTemplate' is listed in UnsupportedTemplates."
            }
        }
        else {
            $matchingReviewPrefix = @($reviewTemplatePrefixes | Where-Object { $normalizedTemplate.StartsWith(([string]$_).ToUpperInvariant()) } | Select-Object -First 1)
            $matchingSupportedPrefix = @($supportedTemplatePrefixes | Where-Object { $normalizedTemplate.StartsWith(([string]$_).ToUpperInvariant()) } | Select-Object -First 1)
            if ($matchingReviewPrefix.Count -gt 0) {
                $reviewPrefixKey = ([string]$matchingReviewPrefix[0]).ToUpperInvariant()
                $templateCompatibility = 'Review'
                if ($reviewTemplateReasons.ContainsKey($reviewPrefixKey)) {
                    $templateCompatibilityReason = $reviewTemplateReasons[$reviewPrefixKey]
                }
                else {
                    $templateCompatibilityReason = "Template '$normalizedTemplate' matches a review prefix and requires manual validation."
                }
            }
            elseif ($matchingSupportedPrefix.Count -gt 0) {
                $templateCompatibility = 'Compatible'
                if ($compatibleTemplateReasons.ContainsKey($normalizedTemplate)) {
                    $templateCompatibilityReason = $compatibleTemplateReasons[$normalizedTemplate]
                }
                else {
                    $templateCompatibilityReason = "Template '$normalizedTemplate' matches a compatibility prefix."
                }
            }
            else {
                $templateCompatibility = 'Review'
                $templateCompatibilityReason = "Template '$normalizedTemplate' is not mapped; review SharePoint Online compatibility."
            }
        }
    }

    $templateLanguageTag = ''
    $templateLanguageName = ''
    $templateLanguageReviewRequired = $false
    $templateLanguageReason = ''

    if ($null -eq $LanguageLcid) {
        $templateLanguageReviewRequired = $true
        $templateLanguageReason = 'Template language could not be collected.'
    }
    else {
        $culture = $null
        try {
            $culture = [System.Globalization.CultureInfo]::GetCultureInfo([int]$LanguageLcid)
        }
        catch {
            $templateLanguageReviewRequired = $true
            $templateLanguageReason = "Template language LCID '$LanguageLcid' is not recognized by .NET culture metadata."
        }

        if ($null -ne $culture) {
            $templateLanguageTag = [string]$culture.Name
            $templateLanguageName = [string]$culture.EnglishName
            if (@($supportedLanguageLcid).Count -gt 0) {
                $isListed = $false
                foreach ($allowed in $supportedLanguageLcid) {
                    try {
                        if ([int]$allowed -eq [int]$LanguageLcid) {
                            $isListed = $true
                            break
                        }
                    }
                    catch {
                        continue
                    }
                }
                if (-not $isListed) {
                    $templateLanguageReviewRequired = $true
                    $templateLanguageReason = "Template language LCID '$LanguageLcid' is outside SupportedLanguageLcid."
                }
            }
        }
    }

    return [PSCustomObject]@{
        IsUnsupportedSiteTemplate = $isUnsupportedTemplate
        TemplateCompatibility = $templateCompatibility
        TemplateCompatibilityReason = $templateCompatibilityReason
        TemplateLanguageLcid = $LanguageLcid
        TemplateLanguageTag = $templateLanguageTag
        TemplateLanguageName = $templateLanguageName
        TemplateLanguageReviewRequired = $templateLanguageReviewRequired
        TemplateLanguageReason = $templateLanguageReason
    }
}
