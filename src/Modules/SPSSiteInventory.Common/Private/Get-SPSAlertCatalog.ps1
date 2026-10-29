function Get-SPSAlertCatalog {
    <#
        .SYNOPSIS
        Returns the catalog that maps each alert type to its severity and remediation hint.

        .DESCRIPTION
        Every alert the inventory raises (see Get-SPSInventoryAlert) has one entry here, so
        the same signal always produces the same severity, explanation and advice, and a
        reader of the report knows what to do next. An entry holds:

        - Severity: High, Medium or Low. High is for findings that block or break a
          migration, Medium for findings that need a plan or a check, and Low for
          information to pass on, such as telling users what the migration does not carry.
        - Message: what was detected and why it matters. Alerts whose message depends on the
          record, such as the template reasons, replace it with their own text.
        - Remediation: the next step, written from the guidance of the SharePoint Migration
          Assessment Tool (SMAT) scan reports and the Microsoft documentation.
        - Reference: the Microsoft Learn page behind the advice, or an empty string.

        The catalog is written for the default mode, SharePointOnline: a migration to SharePoint
        Online. With the SharePointOnPrem mode it is the catalog of the modernization of the farm,
        which Get-SPSOnPremAlertCatalog derives from this one: the same alert types, in the same
        order, with the severity and the words of what matters for that question. Each catalog is
        built once per session and the entries are returned in a stable order.

        Private because it is an implementation detail of the alert helpers.

        .PARAMETER TargetMode
        SharePointOnline (the default) or SharePointOnPrem. Any other value is rejected.

        .EXAMPLE
        (Get-SPSAlertCatalog)['InfoPath'].Remediation

        .EXAMPLE
        (Get-SPSAlertCatalog -TargetMode 'SharePointOnPrem')['InfoPath'].Severity
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Object]
        $TargetMode = 'SharePointOnline'
    )

    $mode = (Get-SPSTargetProfile -TargetMode $TargetMode).TargetMode
    if ($mode -eq 'SharePointOnPrem') {
        if ($null -eq $script:SPSAlertCatalogOnPrem) {
            $script:SPSAlertCatalogOnPrem = Get-SPSOnPremAlertCatalog -Catalog (Get-SPSAlertCatalog)
        }
        return $script:SPSAlertCatalogOnPrem
    }

    if ($null -ne $script:SPSAlertCatalog) {
        return $script:SPSAlertCatalog
    }

    $script:SPSAlertCatalog = [ordered]@{
        WebApplicationEnumerationFailed = @{
            Severity    = 'High'
            Message     = 'Site collection enumeration failed for this web application.'
            Remediation = 'Fix the access or database problem reported in the run log and run the inventory again: the site collections of this web application are not assessed until then.'
            Reference   = ''
        }
        AssessmentFailed = @{
            Severity    = 'High'
            Message     = 'Site assessment failed.'
            Remediation = 'Read the warnings of the site record, fix the cause (permissions, locked or unreachable content) and run the inventory again: the site has no category or score until then.'
            Reference   = ''
        }
        AssessmentPartial = @{
            Severity    = 'Medium'
            Message     = 'Site assessment is partial and may miss signals.'
            Remediation = 'Review the warnings of the site record: counts are lower bounds and the category may be understated. A Simple site collection is held in the Needs review wave until it is read in full. Fix the unreadable item or raise the matching cap, then run the inventory again.'
            Reference   = ''
        }
        Workflow2010 = @{
            Severity    = 'High'
            Message     = 'Legacy SharePoint 2010 workflows require migration remediation.'
            Remediation = 'List the workflows with the site owners and rebuild them, for example with Power Automate: the SharePoint 2010 workflow engine is retired in SharePoint Online. Complete the workflows in flight before the migration.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-workflow-associations-2010'
        }
        Workflow2010Running = @{
            Severity    = 'High'
            Message     = 'Active SharePoint 2010 workflow instances were detected.'
            Remediation = 'Ask the site owners to finish the running workflows on the source before the migration: running instances are not migrated and appear as never started afterwards, and the SharePoint 2010 workflow engine is retired in SharePoint Online, so they cannot be restarted there. Plan a supported replacement, for example with Power Automate, for any work that is still unfinished.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/business-apps/power-automate/guidance/migrate-from-classic-workflows-to-power-automate-flows'
        }
        Workflow2013 = @{
            Severity    = 'High'
            Message     = 'SharePoint 2013 workflows are retired in SharePoint Online and require migration remediation.'
            Remediation = 'List the workflows with the site owners and rebuild them, for example with Power Automate: the SharePoint 2013 workflow engine was retired in SharePoint Online on 2 April 2026. Complete the workflows in flight before the migration.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/business-apps/power-automate/guidance/migrate-from-classic-workflows-to-power-automate-flows'
        }
        Workflow2013Running = @{
            Severity    = 'High'
            Message     = 'Active SharePoint 2013 workflow instances were detected.'
            Remediation = 'Ask the site owners to finish the running workflows on the source before the migration: running instances are not migrated and appear as never started afterwards, and the SharePoint 2013 workflow engine was retired in SharePoint Online on 2 April 2026, so they cannot be restarted there. Plan a supported replacement, for example with Power Automate, for any work that is still unfinished.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/business-apps/power-automate/guidance/migrate-from-classic-workflows-to-power-automate-flows'
        }
        AppInstances = @{
            Severity    = 'Medium'
            Message     = 'SharePoint add-ins were detected and require migration compatibility review.'
            Remediation = 'List the add-ins with the site owners and agree on a supported replacement for each one before the cutover: the SharePoint Add-In model was retired in SharePoint Online on 2 April 2026, so add-ins cannot be reinstalled there. Rebuild custom add-ins as SharePoint Framework solutions and ask the vendor of a purchased add-in for a version that does not depend on the add-in model. Reinstalling an add-in only applies to a target that still supports them, such as a SharePoint Server farm with an app catalog.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/sp-add-ins/retirement-announcement-for-add-ins'
        }
        AppWebs = @{
            Severity    = 'Medium'
            Message     = 'App webs were detected and should be assessed for SharePoint Online replacement paths.'
            Remediation = 'Check what each app web stores and agree with the owners how to preserve it before the cutover: the data kept there is not carried over, and the add-in cannot be reinstalled in SharePoint Online, so export the data that must be kept, for example to a list or library of the host site, and plan the replacement of the add-in.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/sp-add-ins/retirement-announcement-for-add-ins'
        }
        PublishingSite = @{
            Severity    = 'Medium'
            Message     = 'Publishing features are enabled; page layouts and publishing customizations typically need extensive remediation.'
            Remediation = 'Run a test migration of these sites, list what breaks (page layouts, master pages, styles) and plan the fixes. Starting a new portal and archiving the old one is often easier.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-publishing-sites'
        }
        PublishingPages = @{
            Severity    = 'Medium'
            Message     = 'Publishing pages were detected; their pages may not render correctly until page layouts, master pages and styles are reviewed.'
            Remediation = 'Catalog the pages by page layout, run a test migration and plan the fixes to layouts, master pages, JavaScript and CSS after the migration.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scanpublishing-pages'
        }
        CustomizedPages = @{
            Severity    = 'Medium'
            Message     = 'Customized pages are reverted to their default state during migration; owners must reapply customizations afterwards.'
            Remediation = 'Tell the site owners which pages are customized: they must reapply the customization after the migration, and should look for out-of-the-box behavior to replace it where possible.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-customized-pages'
        }
        AlternateCssUrl = @{
            Severity    = 'Medium'
            Message     = 'Webs use an alternate CSS URL: modern pages do not apply it, so a page that relies on it looks different in the modern experience.'
            Remediation = 'List the webs with the site owners (AlternateCssUrlExamples in the inventory shows where to start) and replace the style sheet with the branding that modern pages support: a site theme for the colors and the logo, and a SharePoint Framework extension where a theme is not enough. Then clear the alternate CSS URL of the web.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/modern-experience-customizations-customize-pages'
        }
        XsltListViews = @{
            Severity    = 'Medium'
            Message     = 'List views render with XSLT: the modern list ignores it, so SharePoint shows these lists in the classic experience.'
            Remediation = 'List the views with the site owners (XsltListViewExamples in the inventory shows where to start). Replace the customization with what the modern list supports, view formatting for the look of a view or a column and a SharePoint Framework field customizer for more, then clear the XslLink or the Xsl of the view so that the list opens in the modern experience.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/modern-experience-customizations-customize-lists-and-libraries'
        }
        ScriptWebParts = @{
            Severity    = 'Medium'
            Message     = 'Script Editor or Content Editor web parts carry script: they do not exist on a modern page, so the pages that use them stay classic.'
            Remediation = 'Find out with the site owners what each script does (ScriptWebPartExamples in the inventory shows where to start), rebuild it as a SharePoint Framework web part or extension and replace the page with a modern page that uses it. A web part that only formats text or embeds a page can usually be replaced by the Text or the Embed web part.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/modern-experience-customizations-customize-pages'
        }
        ModernExperienceOptOut = @{
            Severity    = 'Low'
            Message     = 'A site collection or webs opted out of the modern list and library experience: their lists open in the classic experience unless a list says otherwise.'
            Remediation = 'Ask the site owners why the site collection or the web opted out, and whether its lists still need the classic experience. When they do not, deactivate the feature of the site collection (E3540C7D-6BEA-403C-A224-1A12EAFEE4C4) or of the web (52E14B6F-B1BB-4969-B89B-C4FAA56745EF), then check the lists that SharePoint still shows in the classic experience.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/transform/modernize-userinterface-lists-and-libraries-optout'
        }
        ClassicExperienceLists = @{
            Severity    = 'Low'
            Message     = 'Lists are set to the classic experience: they open in it even where the modern list experience is available.'
            Remediation = 'Check with the site owners why each list was set to the classic experience (ClassicExperienceListExamples in the inventory shows where to start): a customization that the modern list does not support, or a habit. Set the "List experience" of the list back to the default when nothing blocks it.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/dev/transform/modernize-userinterface-lists-and-libraries-optout'
        }
        CustomPermissionLevels = @{
            Severity    = 'Medium'
            Message     = 'Custom permission levels may not be carried over by migration tools; recreate them or move users to the built-in levels.'
            Remediation = 'Decide before the migration: move users and groups to the built-in permission levels, or plan to recreate the custom levels. Check the permissions afterwards.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-custom-permission-level'
        }
        EmailEnabledLists = @{
            Severity    = 'Medium'
            Message     = 'Incoming e-mail is not available in SharePoint Online; messages sent to these lists will no longer arrive.'
            Remediation = 'Tell the users that e-mail no longer reaches these lists after the migration and plan another way to capture the messages.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-email-enabled-lists'
        }
        HtmlFiles = @{
            Severity    = 'Medium'
            Message     = 'HTML files open in the browser today but prompt a download under the Strict browser file handling SharePoint Online enforces.'
            Remediation = 'Warn the site owners. If the files must open in the browser, rename them to .aspx (this needs designer access to the site); otherwise users are prompted to download them, which also affects Page Viewer web parts.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-browser-file-handling'
        }
        ManagedMetadataColumns = @{
            Severity    = 'Medium'
            Message     = 'Managed metadata columns depend on the term store; plan the term store migration together with these lists and verify the columns afterwards.'
            Remediation = 'Migrate these lists close to the term store migration, then check that items in them can still be created and edited.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-managed-metadata-columns'
        }
        ExternalLists = @{
            Severity    = 'High'
            Message     = 'External lists depend on BCS, which Microsoft retired in SharePoint Online on 30 September 2024: they cannot be migrated, so plan a replacement such as Power Apps.'
            Remediation = 'Plan a replacement for each scenario, for example with Power Apps and its connectors; the on-premises data gateway reaches on-premises data. There is no direct migration.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/business-connectivity-services-retirement'
        }
        AlertSubscriptions = @{
            Severity    = 'Medium'
            Message     = 'Users have SharePoint alerts (Alert Me subscriptions) on this site; they are not migrated and SharePoint Online retired SharePoint Alerts from July 2026, so each one needs a replacement.'
            Remediation = 'Plan a replacement before the cutover: SharePoint Online retired SharePoint Alerts from July 2026, so they cannot be recreated there and existing ones stop working. Use the SharePoint alerts CSV and JSON files to see who is notified of what, rebuild each notification that is still needed with a SharePoint rule or a Power Automate flow (Microsoft publishes a template for each classic alert scenario) and tell the users. Recreating an alert only applies to a target that still supports them.'
            Reference   = 'https://learn.microsoft.com/en-us/troubleshoot/sharepoint/sites/no-alert-notifications'
        }
        UnsupportedSiteTemplate = @{
            Severity    = 'High'
            Message     = 'Site template is not supported for direct SharePoint Online migration.'
            Remediation = 'Check what the Team Site template that receives the content lacks compared with the source site, plan the rebuild of those features and validate the site after the migration.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-unsupported-site-templates'
        }
        TemplateCompatibilityReview = @{
            Severity    = 'Medium'
            Message     = 'Site template compatibility requires manual validation.'
            Remediation = 'Check the template against the templates your target supports. If it is not covered, treat the site like one with an unsupported template.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-unsupported-site-templates'
        }
        TemplateLanguageReview = @{
            Severity    = 'Medium'
            Message     = 'Template language requires manual compatibility review.'
            Remediation = 'Plan for someone who reads the language of the site to validate the migrated content during user acceptance testing.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-site-template-language'
        }
        InfoPath = @{
            Severity    = 'High'
            Message     = 'InfoPath forms are not supported in SharePoint Online.'
            Remediation = 'Plan a supported replacement for every InfoPath form that users fill in a browser, for example with Power Apps: InfoPath Forms Services is retired in SharePoint Online, so repairing SOAP data connections, managed code or people pickers does not make a form work there. Inventory the forms with their owners, rebuild them and test the replacements during user acceptance testing.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-infopath'
        }
        FullTrustCode = @{
            Severity    = 'High'
            Message     = 'Custom full-trust code is a migration blocker.'
            Remediation = 'Identify the farm solutions behind these features (see the farm solutions section) and plan their replacement: SharePoint Online does not support full-trust solutions.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-full-trust-component-results'
        }
        FbaConfigured = @{
            Severity    = 'High'
            Message     = 'Forms-based authentication requires identity remediation.'
            Remediation = 'Plan the move of the forms-based accounts to an identity SharePoint Online supports, and map the users before the migration.'
            Reference   = ''
        }
        NoAccessSite = @{
            Severity    = 'High'
            Message     = 'The site collection is locked with NoAccess: it cannot be read, so the migration tools skip it.'
            Remediation = 'Check that the lock is intended. A NoAccess lock makes the site unreadable and the migration tools skip it: unlock the sites that must migrate.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-locked-sites'
        }
        LockedSite = @{
            Severity    = 'Medium'
            Message     = 'The site collection is locked NoAdditions or ReadOnly: its content can still be read and migrated.'
            Remediation = 'Check that the lock is intended. A NoAdditions lock prevents adding content and a ReadOnly lock prevents adding, updating and deleting it, but both still allow reading, so the content can be migrated and the lock is often a deliberate migration freeze: change it only if your migration method requires it.'
            Reference   = 'https://learn.microsoft.com/en-us/powershell/module/microsoft.sharepoint.powershell/set-spsite?view=sharepoint-ps'
        }
        IrmEnabledLists = @{
            Severity    = 'High'
            Message     = 'IRM-enabled lists require records-protection remediation.'
            Remediation = 'Configure the target for rights management, disable IRM on these lists before the migration, then enable it again on the source and target lists once the content is copied.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-irm-enabled-lists'
        }
        LargeSite = @{
            Severity    = 'Medium'
            Message     = 'Site content size is above the configured large-site threshold.'
            Remediation = 'Plan more time and a dedicated wave: the larger the site, the harder the migration schedule is to predict.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-large-sites'
        }
        LargeLists = @{
            Severity    = 'Medium'
            Message     = 'Large lists were detected and may require migration batching or cleanup.'
            Remediation = 'Check whether all the content must migrate, archive or clean up what is not needed, expect a longer and less predictable migration and validate the item counts afterwards.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-large-lists'
        }
        LargeListViews = @{
            Severity    = 'Medium'
            Message     = 'Large-list views were detected and should be reviewed for migration readiness.'
            Remediation = 'Remediate the views before the migration, for example by filtering on indexed columns and limiting lookup columns: the list view threshold applies continuously in SharePoint Online.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-large-list-views'
        }
        CheckedOutFiles = @{
            Severity    = 'Medium'
            Message     = 'Checked-out files were detected and should be checked in before migration.'
            Remediation = 'Ask the users to check in their files before the migration date: only checked-in content is migrated.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-checked-out-files'
        }
        FileVersions = @{
            Severity    = 'Medium'
            Message     = 'Files with high version counts were detected and may increase migration time.'
            Remediation = 'Decide whether all versions must be kept: the migration time grows with the number of versions.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-file-versions'
        }
        Subsites = @{
            Severity    = 'Low'
            Message     = 'This site collection has subsites. SharePoint Online supports them, but modern SharePoint favors one site collection per unit of work, connected by hub sites.'
            Remediation = 'Decide with the site owners, before the migration, whether each subsite stays where it is or becomes a site collection of its own, connected to the others by a hub site. A subsite is part of the URL of its content, so reorganizing it later breaks the links to it, and the policies of a site collection (retention, classification, features) apply to all its subsites. Restructuring changes URLs, navigation and permissions, so plan the redirects and the communication. SubsiteCount, MaxSubsiteDepth and SubsiteExamples in the inventory show where to start.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/planning-hub-sites'
        }
        WebApplicationPolicies = @{
            Severity    = 'Medium'
            Message     = 'Web application policies are not migrated to SharePoint Online; replace them with site-collection permissions.'
            Remediation = 'Manage these permissions at the site collection level instead, or use licensing to grant or limit capabilities, and check the result during user acceptance testing.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-web-application-policies'
        }
        PermissiveBrowserFileHandling = @{
            Severity    = 'Medium'
            Message     = 'Permissive browser file handling is not available in SharePoint Online; .htm and .html files will prompt a download.'
            Remediation = 'Warn the owners of the sites in this web application: see the HTML file alerts for the sites concerned and check that their pages render after the migration.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepointmigration/migration-assessment-scan-browser-file-handling'
        }
        BcsApplication = @{
            Severity    = 'Medium'
            Message     = 'BCS is retired in SharePoint Online, so BCS applications cannot be migrated; plan a replacement such as Power Apps for the solutions that rely on them.'
            Remediation = 'Replace the scenarios that rely on this application, for example with Power Apps and its connectors. BCS is not retired in SharePoint Server Subscription Edition, so a target that stays on-premises can keep using it.'
            Reference   = 'https://learn.microsoft.com/en-us/sharepoint/business-connectivity-services-retirement'
        }
        BcsInventoryPartial = @{
            Severity    = 'Medium'
            Message     = 'The BCS inventory is partial: some web applications or LOB systems could not be read, so BCS applications may be missing.'
            Remediation = 'Fix the web application or LOB system named in the run warnings and run the inventory again before relying on the BCS report.'
            Reference   = ''
        }
    }

    return $script:SPSAlertCatalog
}
