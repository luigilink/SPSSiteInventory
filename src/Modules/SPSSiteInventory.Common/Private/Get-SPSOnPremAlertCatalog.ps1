function Get-SPSOnPremAlertCatalog {
    <#
        .SYNOPSIS
        Derives the alert catalog of the SharePointOnPrem target mode from the default one.

        .DESCRIPTION
        The default catalog (see Get-SPSAlertCatalog) is written for a migration to SharePoint Online:
        most of its alerts say what SharePoint Online lacks. The question of the SharePointOnPrem mode is
        another one: what stands between a site collection and the modern experience on the farm where it
        runs. The catalog derived here keeps every alert type, in the same order, and changes what that
        question changes:

        - An alert that is only about a migration to SharePoint Online (BCS, incoming e-mail, forms-based
          authentication, IRM, unsupported templates and the like) becomes Low, and its texts say so: the
          message starts with "Migration to SharePoint Online only." and the remediation with "Nothing to
          do to modernize this farm. If you migrate to SharePoint Online, this applies." The original text
          follows, so nothing is lost for whoever migrates later.
        - An alert whose meaning changes has its own words, and its own severity when the weight of its
          signal in the on-premises example configuration says so: the workflows, InfoPath and the other
          features that SharePoint Server Subscription Edition deprecates, the full-trust code that has to
          be rebuilt with the SharePoint Framework, the classic pages and the add-ins.
        - The alerts that tell the reader that the inventory itself is incomplete, and the alerts about the
          modern experience, are the same in both modes (the opt-out of the modern list experience is
          Medium here instead of Low).

        A word for an alert that is not in the catalog, or an alert that is both migration-only and
        worded, is an error, so that a renamed alert cannot lose its words without anybody noticing.

        Private because it is an implementation detail of Get-SPSAlertCatalog.

        .PARAMETER Catalog
        The default catalog, as Get-SPSAlertCatalog returns it.

        .EXAMPLE
        Get-SPSOnPremAlertCatalog -Catalog (Get-SPSAlertCatalog)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Catalog
    )

    $deprecatedFeaturePage = 'https://learn.microsoft.com/en-us/sharepoint/what-s-new/what-s-deprecated-or-removed-from-sharepoint-server-subscription-edition'
    $frameworkPage = 'https://learn.microsoft.com/en-us/sharepoint/dev/spfx/sharepoint-framework-overview'
    $publishingPage = 'https://learn.microsoft.com/en-us/sharepoint/dev/transform/modernize-publishing-portal'

    # What a migration to SharePoint Online is the only reason for: the farm keeps working with it.
    $migrationOnly = @(
        'CustomPermissionLevels', 'EmailEnabledLists', 'HtmlFiles', 'ManagedMetadataColumns', 'ExternalLists',
        'AlertSubscriptions', 'UnsupportedSiteTemplate', 'TemplateCompatibilityReview', 'TemplateLanguageReview',
        'FbaConfigured', 'IrmEnabledLists', 'LargeSite', 'CheckedOutFiles', 'FileVersions', 'LargeExcelFiles',
        'WebApplicationPolicies', 'PermissiveBrowserFileHandling', 'BcsApplication', 'SecureStoreApplication',
        'AudienceTargeting', 'SiteNotebook'
    )

    $override = [ordered]@{
        AssessmentPartial = @{
            Remediation = 'Review the warnings of the site record: counts are lower bounds and the category may be understated. A Modern-ready site collection is held in the Needs review wave until it is read in full. Fix the unreadable item or raise the matching cap, then run the inventory again.'
        }
        Workflow2010 = @{
            Message     = 'SharePoint 2010 workflows are deprecated in SharePoint Server Subscription Edition: Microsoft stopped supporting them on 14 July 2026.'
            Remediation = 'List the workflows with the site owners and rebuild them, as SharePoint 2013 workflows or with Power Automate. Complete the workflows in flight before you replace them.'
            Reference   = $deprecatedFeaturePage
        }
        Workflow2010Running = @{
            Remediation = 'Ask the site owners to finish the running workflows before you replace them: an instance that is still running is not carried over to a rebuilt workflow. SharePoint 2010 workflows are no longer supported since 14 July 2026, so plan their replacement, as SharePoint 2013 workflows or with Power Automate, for the work that is still unfinished.'
            Reference   = $deprecatedFeaturePage
        }
        Workflow2013 = @{
            Severity    = 'Medium'
            Message     = 'SharePoint 2013 workflows run on Workflow Manager, and Microsoft Workflow Manager is deprecated in SharePoint Server Subscription Edition: SharePoint Workflow Manager replaces it.'
            Remediation = 'Check which engine runs the workflows. Microsoft Workflow Manager is deprecated: move to SharePoint Workflow Manager, which Microsoft supports beyond 2026, or rebuild the workflows with Power Automate, which is the longer-term path.'
            Reference   = $deprecatedFeaturePage
        }
        Workflow2013Running = @{
            Severity    = 'Medium'
            Remediation = 'Let the running workflows finish before you move the engine or rebuild the workflows: an instance that is still running is not carried over. Then follow the advice for the SharePoint 2013 workflows.'
            Reference   = $deprecatedFeaturePage
        }
        AppInstances = @{
            Message     = 'SharePoint add-ins were detected: they keep running on this farm, and the SharePoint Framework is the model of the modern experience.'
            Remediation = 'List the add-ins with the site owners and decide for each one whether to keep it or to rebuild it as a SharePoint Framework solution, which SharePoint Server Subscription Edition supports. Ask the vendor of a purchased add-in for a version built with the SharePoint Framework.'
            Reference   = $frameworkPage
        }
        AppWebs = @{
            Message     = 'App webs were detected: they belong to SharePoint add-ins, and the SharePoint Framework is the model of the modern experience.'
            Remediation = 'Check what each app web stores and agree with the owners whether to keep the add-in or to replace it: the data kept in an app web goes with the add-in, so export what must be kept first, for example to a list or library of the host site.'
            Reference   = $frameworkPage
        }
        PublishingSite = @{
            Message     = 'Publishing features are enabled: modern pages are not supported on a classic publishing portal, so its pages stay classic.'
            Remediation = 'Plan the rebuild of the publishing pages as modern pages with the site owners: the page layouts, master pages and styles of a publishing portal have no modern counterpart. The pages keep working on this farm until they are rebuilt, so the work can be done by site and by page layout.'
            Reference   = $publishingPage
        }
        PublishingPages = @{
            Message     = 'Publishing pages were detected: they are classic pages that use page layouts, and each one has to be rebuilt to become a modern page.'
            Remediation = 'Catalog the pages by page layout (PublishingPageLayoutExamples in the inventory shows the most used), decide which pages are still needed and rebuild those as modern pages. Pages that share a layout are usually rebuilt together.'
            Reference   = $publishingPage
        }
        CustomizedPages = @{
            Message     = 'Customized pages were detected: they are classic pages that were edited outside the site definition, and they do not become modern pages by themselves.'
            Remediation = 'Tell the site owners which pages are customized (CustomizedPageExamples in the inventory shows where to start) and rebuild what they need as modern pages, with the web parts and the SharePoint Framework solutions that the modern experience supports.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/transform/modernize-userinterface-site-pages'
        }
        InfoPath = @{
            Message     = 'InfoPath Forms Services is deprecated in SharePoint Server Subscription Edition: Microsoft stopped supporting it on 14 July 2026.'
            Remediation = 'Plan a supported replacement for every InfoPath form that users fill in a browser, for example with Power Apps: repairing SOAP data connections, managed code or people pickers does not make a form supported again. Inventory the forms with their owners, rebuild them and test the replacements during user acceptance testing.'
            Reference   = $deprecatedFeaturePage
        }
        FullTrustCode = @{
            Severity    = 'Medium'
            Message     = 'Custom full-trust code runs on this farm, but it does not run in the modern experience: it is code to rebuild with the SharePoint Framework.'
            Remediation = 'Identify the farm solutions behind these features (see the farm solutions section) and plan their replacement with SharePoint Framework solutions, which SharePoint Server Subscription Edition supports. The full-trust code keeps working on the farm until then.'
            Reference   = $frameworkPage
        }
        NoAccessSite = @{
            Severity    = 'Medium'
            Message     = 'The site collection is locked with NoAccess: it cannot be read, so the inventory cannot assess it.'
            Remediation = 'Check that the lock is intended. A NoAccess lock makes the site unreadable, so it can be neither assessed nor modernized: unlock the site collections that must be modernized.'
        }
        LockedSite = @{
            Severity    = 'Low'
            Message     = 'The site collection is locked NoAdditions or ReadOnly: its content can still be read, but adding or changing content is restricted.'
            Remediation = 'Check that the lock is intended. A NoAdditions lock prevents adding content and a ReadOnly lock prevents adding, updating and deleting it, so the modernization of the site needs it unlocked: change the lock only when the work starts.'
        }
        LargeLists = @{
            Message     = 'Large lists were detected: on a list above the list view threshold, a view that filters or sorts on a column that is not indexed is blocked, in a modern list as in a classic one.'
            Remediation = 'Check with the site owners whether all the content must stay in the list: archive or clean up what is not needed, and index the columns that the views filter and sort on.'
        }
        LargeListViews = @{
            Message     = 'Large-list views were detected and should be reviewed: a view that filters or sorts a list above the list view threshold on a column that is not indexed is blocked.'
            Remediation = 'Review the views, for example by filtering on indexed columns and limiting lookup columns: the list view threshold applies to the views of a modern list too.'
        }
        Subsites = @{
            Message     = 'This site collection has subsites. They work on this farm, but modern SharePoint favors one site collection per unit of work.'
            Remediation = 'Decide with the site owners, when you plan the modernization, whether each subsite stays where it is or becomes a site collection of its own, linked from the navigation of the others (hub sites are not available in SharePoint Server). A subsite is part of the URL of its content, so reorganizing it later breaks the links to it, and the policies of a site collection (retention, classification, features) apply to all its subsites. Restructuring changes URLs, navigation and permissions, so plan the redirects and the communication. SubsiteCount, MaxSubsiteDepth and SubsiteExamples in the inventory show where to start.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/sites/sites-and-site-collections-overview'
        }
        ModernExperienceOptOut = @{
            Severity = 'Medium'
        }
    }

    foreach ($type in @($migrationOnly) + @($override.Keys)) {
        if (-not $Catalog.Contains($type)) {
            throw "The alert type '$type' is worded for the on-premises mode but is not in the alert catalog."
        }
    }
    foreach ($type in $migrationOnly) {
        if ($override.Contains($type)) {
            throw "The alert type '$type' is both migration-only and worded for the on-premises mode."
        }
    }

    $derived = [ordered]@{}
    foreach ($type in $Catalog.Keys) {
        $entry = $Catalog[$type]
        $words = @{
            Severity    = $entry.Severity
            Message     = $entry.Message
            Remediation = $entry.Remediation
            Reference   = $entry.Reference
        }
        if ($migrationOnly -contains $type) {
            $words.Severity = 'Low'
            # The prefix is kept apart, so that a specific message (the reason of a template alert) can take it too.
            $words.MessagePrefix = 'Migration to SharePoint Online only. '
            $words.Message = '{0}{1}' -f $words.MessagePrefix, $entry.Message
            $words.Remediation = 'Nothing to do to modernize this farm. If you migrate to SharePoint Online, this applies. {0}' -f $entry.Remediation
        }
        if ($override.Contains($type)) {
            foreach ($field in $override[$type].Keys) {
                $words[$field] = $override[$type][$field]
            }
        }
        $derived[$type] = $words
    }

    return $derived
}
