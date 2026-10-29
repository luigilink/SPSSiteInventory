# =====================================================================================
# SPSSiteInventory - Inventory settings, on-premises modernization (example)
#
# Copy this file to inventory-settings.psd1 and adjust the values for your farm, when the
# question is not "can this site collection move to SharePoint Online?" but "is it ready for
# the modern experience, and what does it take to modernize it where it runs?". This is the
# preset of the SharePointOnPrem target mode; inventory-settings.example.psd1 is the preset
# of the default SharePointOnline mode, and the two files have the same sections.
#
# What changes with the mode:
#   - the four categories are called Modern-ready, Light remediation, Rebuild (SPFx) and
#     Blocked (their numbers, 1 to 4, do not change), and so do the waves below;
#   - the scoring below fits that question. Full-trust code and custom farm features run
#     on the farm, so they are code to rebuild with the SharePoint Framework (SPFx), not a
#     blocker. Forms-based authentication, unsupported templates, NoAccess locks, IRM and
#     external lists belong to a migration, not to the modernization of a farm, so they
#     weigh nothing here (the signals are still collected and listed in the reports).
#
# The real inventory-settings.psd1 is gitignored so environment-specific details (URLs,
# in-house solution names) stay out of version control.
#
# No client-specific value ships in this repository: this file is a neutral example.
# =====================================================================================
@{
    # What the inventory prepares: 'SharePointOnline' (the default when the setting is
    # missing) or 'SharePointOnPrem'. The mode names the categories and the waves, and
    # frames the report; the Scoring section below decides what counts as a blocker.
    TargetMode = 'SharePointOnPrem'

    # Free-form environment identifier, used in output file names and the banner.
    EnvName = 'PROD'

    # Optional list of web application URLs to scan. Leave empty to scan every content
    # web application in the farm.
    WebApplicationUrl = @()

    # Custom farm solutions (WSP) are auto-detected by default: a solution is treated as
    # custom unless its name looks like a Microsoft / out-of-the-box solution. You usually
    # do NOT need to configure anything here.
    #
    # CustomSolutionPrefix is an optional OVERRIDE: list case-insensitive name prefixes to
    # force a solution to be treated as custom when auto-detection wrongly classifies it as
    # Microsoft. Leave empty to rely on auto-detection alone.
    CustomSolutionPrefix = @()

    # Optional: turn auto-detection off to fall back to the legacy behaviour where only
    # CustomSolutionPrefix decides which solutions are custom.
    # AutoDetectCustomSolutions = $true

    # Optional: extra name prefixes to treat as Microsoft / out-of-the-box during
    # auto-detection (for example a known vendor package that should not count as custom).
    # KnownMicrosoftSolutionPrefix = @()

    # Folder where the CSV/JSON reports are written.
    OutputFolder = 'C:\SPSSiteInventory\Reports'

    # Days of run logs kept under the Logs folder.
    LogRetentionDays = 90

    # -------------------------------------------------------------------------------
    # Large-content risk thresholds
    #
    # These thresholds drive large-content signals collected per site:
    # - IsLargeSite (site size >= LargeSiteSizeGB)
    # - LargeListCount / LargeListViewCount
    # - CheckedOutFileCount
    # - FileVersionCount
    #
    # File-version counting scans document-library items. To keep runtime predictable,
    # MaxItemsForVersionScanPerLibrary caps per-library scanning; when hit, the scan is
    # marked partial and a warning is emitted. MaxItemsForPublishingPageScanPerLibrary
    # applies the same cap to the page-layout scan of publishing Pages libraries, and
    # MaxItemsForHtmlFileScanPerLibrary to the .htm/.html file count (collected only in
    # web applications that use Permissive browser file handling).
    #
    # ScriptWebPartCount reads the web parts of the home page of each web and of the pages of
    # its Site Pages and Pages libraries: MaxItemsForWebPartScanPerLibrary caps how many pages
    # of each library are read, and a library above it makes the site marked partial.
    #
    # LargeExcelFileCount counts the Excel workbooks (.xlsx) of at least LargeExcelFileSizeMB (10 MB:
    # the size above which SharePoint Online asks the user to open a workbook in Excel instead of the
    # browser); MaxItemsForExcelFileScanPerLibrary caps how many workbooks are checked in a library.
    #
    # AudienceTargetedItemCount counts the list items that target an audience (the Target Audiences
    # column); MaxItemsForAudienceTargetingScanPerList caps how many items are read in each list that
    # has the column, and a list above it makes the site marked partial. SiteNotebookCount counts the
    # site notebooks of the Site Assets library; MaxItemsForNotebookScanPerLibrary caps how many
    # folders of that library are read.
    #
    # MaxAlertRowsPerSite caps how many SharePoint alert rows are exported per site
    # collection; SharePointAlertCount stays exact. When the cap is hit, the site is
    # marked partial and a warning is emitted.
    # -------------------------------------------------------------------------------
    LargeContentThresholds = @{
        LargeSiteSizeGB = 100
        LargeListItemCount = 5000
        LargeListViewRowLimit = 5000
        CheckedOutFileCount = 1
        FileVersionCount = 50
        MaxItemsForVersionScanPerLibrary = 2000
        MaxItemsForPublishingPageScanPerLibrary = 2000
        MaxItemsForHtmlFileScanPerLibrary = 2000
        MaxItemsForWebPartScanPerLibrary = 200
        LargeExcelFileSizeMB = 10
        MaxItemsForExcelFileScanPerLibrary = 2000
        MaxItemsForAudienceTargetingScanPerList = 2000
        MaxItemsForNotebookScanPerLibrary = 2000
        MaxAlertRowsPerSite = 5000
    }

    # -------------------------------------------------------------------------------
    # Site-template parity rules (SMAT P0 scope)
    #
    # SPSSiteInventory maps each root-web template to:
    # - Compatible: known template families with supported SPO migration paths
    # - Unsupported: templates explicitly listed below
    # - Review: template values outside the supported map (manual validation needed)
    #
    # The result is reported (IsUnsupportedSiteTemplate and the template columns), but in this
    # mode it does not weigh on the score: a template that SharePoint Online does not support
    # still runs on your farm.
    #
    # Language parity is best-effort:
    # - if SupportedLanguageLcid is empty, any recognized .NET culture is accepted;
    # - if populated, LCIDs outside the list are flagged for review.
    # -------------------------------------------------------------------------------
    TemplateParity = @{
        UnsupportedTemplates = @(
            'APP#0'
            'SPSMSITEHOST#0'
        )
        SupportedTemplatePrefixes = @(
            'STS#'
            'COMMUNITY#'
            'PROJECTSITE#'
            'SITEPAGEPUBLISHING#'
            'CMSPUBLISHING#'
            'BLANKINTERNET#'
            'SRCHCEN#'
            'WIKI#'
            'ENTERWIKI#'
            'BDR#'
            'OFFILE#'
            'GROUP#'
            'SPSPERS#'
            'SPSNEWS#'
            'SPSNHOME#'
        )
        # Optional: templates to force as "Review" even when they match a supported prefix.
        # BLOG templates are kept as review by default because migration usually
        # requires remapping to modern SPO structures.
        ReviewTemplatePrefixes = @('BLOG#')
        # Optional: allowed language LCIDs. Leave empty to accept any recognized culture.
        SupportedLanguageLcid = @()
    }

    # -------------------------------------------------------------------------------
    # Permission levels
    #
    # SharePoint gives Limited Access, Read, Contribute, Design, Full Control and Edit a
    # base type, so they are never reported as custom. The levels it provisions for
    # features and site templates (View Only, Approve, Manage Hierarchy, Restricted Read,
    # Restricted Interfaces for Translation, Moderate, Records Center Web Service
    # Submitters) are recognized by their English names. On a non-English farm, list the
    # localized names here; they are added to the English ones. Otherwise those levels
    # are reported as custom permission levels.
    # -------------------------------------------------------------------------------
    PermissionLevels = @{
        BuiltInNames = @()
    }

    # -------------------------------------------------------------------------------
    # Scope
    #
    # Personal sites (My Sites, template SPSPERS) belong to the OneDrive migration, and site
    # masters are the hidden site collections that SharePoint creates itself to speed up the
    # creation of personal sites (host name sitemaster- followed by a GUID). Neither is a
    # site to migrate, so both are left out of the inventory by default, also when this
    # section is missing. The My Site host (SPSMSITEHOST) is a real site and always stays.
    # Set an option to $true to keep that kind of site collection; set both to $true to
    # scan what version 1.x scanned. The values must be $true or $false. The report and the
    # log say how many site collections were left out.
    # -------------------------------------------------------------------------------
    Scope = @{
        IncludePersonalSites = $false
        IncludeSiteMasters = $false
    }

    # -------------------------------------------------------------------------------
    # HTML report
    #
    # The HTML report is one file until it has more site collections than HtmlSplitThreshold
    # (3000: about 5 MB, which still filters at once). A larger farm gets an entry page, with
    # the summary, the risk indicators, the alerts, the wave plan and the detail sections,
    # and the table of the site collections on pages of at most HtmlRowsPerPage of them
    # (500, about 1 MB a page), one series per category, in the same folder. The pages link
    # to each other with relative links: keep them together, and the folder can be moved,
    # zipped and sent. 0 never splits. The values must be whole numbers: HtmlSplitThreshold
    # from 0 to 10000000 and HtmlRowsPerPage from 50 to 5000.
    # -------------------------------------------------------------------------------
    Report = @{
        HtmlSplitThreshold = 3000
        HtmlRowsPerPage = 500
    }

    # -------------------------------------------------------------------------------
    # SharePoint alerts
    #
    # The SharePoint alerts report lists the "Alert Me" subscriptions of the users, with
    # the login name of each owner so that you can tell them which notifications to replace.
    # A login name is personal data: set IncludeUserLogin to $false to leave it out.
    # UserLoginName then stays empty and the owners are not looked up. The value must be
    # $true or $false.
    # -------------------------------------------------------------------------------
    SharePointAlerts = @{
        IncludeUserLogin = $true
    }

    # -------------------------------------------------------------------------------
    # Scoring engine (consumed by Measure-SPSSiteComplexity)
    #
    # Category mapping (the numbers are the same in both modes, the names are those of the
    # SharePointOnPrem mode):
    #   1 Modern-ready      - score below Moderate, no blocking signal
    #   2 Light remediation - score at or above Moderate
    #   3 Rebuild (SPFx)    - score at or above Complex
    #   4 Blocked           - any BlockingSignals value is truthy (overrides the score)
    #
    # The question is what stands between a site collection and the modern experience on
    # the farm where it runs, so a weight measures the effort to modernize, not the effort
    # to move to SharePoint Online.
    # -------------------------------------------------------------------------------
    Scoring = @{
        # Weighted signals: weight * signal value is summed into the score.
        # Booleans count as 1 when true; counts contribute their value.
        Weights = @{
            # SharePoint 2010 workflows are deprecated in SharePoint Server Subscription Edition
            # and their support ended on 14 July 2026: they must be rebuilt (SharePoint 2013
            # workflows or Power Automate), so they weigh heavily. Not blocking: they still run.
            Workflow2010Count        = 3.0
            Workflow2013Count        = 1.5
            Workflow2010RunningInstanceCount = 1.0
            Workflow2013RunningInstanceCount = 0.5
            # Add-ins and app webs are not part of the modern experience and need a plan.
            AppInstanceCount = 1.0
            AppWebCount = 1.5
            # Classic publishing sites rely on page layouts and publishing features that have
            # no modern equivalent: a rebuild, not a quick fix. Weighted, not blocking.
            PublishingInfrastructureEnabled = 2.0
            PublishingWebCount = 0.5
            PublishingPageLayoutCount = 0.5
            PublishingPageCount = 0.001
            # Customized (unghosted) pages do not render as modern pages: they are rebuilt.
            CustomizedPageCount = 1.0
            # Custom permission levels work on the farm: noted, hardly weighed.
            CustomPermissionLevelCount = 0.1
            # Incoming e-mail works on the farm.
            EmailEnabledListCount = 0
            # Strict browser file handling is a SharePoint Online behavior.
            HtmlFileCount = 0
            # The term store stays where it is.
            ManagedMetadataListCount = 0
            ManagedMetadataTermSetCount = 0
            # BCS is not retired in SharePoint Server Subscription Edition: external lists keep
            # working. They are listed in the reports, and they do not weigh here.
            ExternalListCount = 0
            # A template that SharePoint Online does not support still runs on the farm.
            IsUnsupportedSiteTemplate = 0
            TemplateLanguageReviewRequired = 0
            # Subsites work on the farm. Modern SharePoint favors one site collection per unit
            # of work, so a large or deep hierarchy is a restructuring topic to plan, not a cost
            # of modernizing: it is not penalised.
            SubsiteCount = 0
            MaxSubsiteDepth = 0
            # InfoPath Forms Services is deprecated and its support ended on 14 July 2026, with
            # no modern equivalent: the forms are rebuilt in Power Apps. Weighted heavily and
            # listed as a blocking signal below.
            InfoPathFormCount        = 3.0
            # IRM works on the farm.
            IrmEnabledListCount      = 0
            # Large-content signals are a performance topic of the modern experience as well:
            # a list that exceeds the list view threshold does not render better in a modern list.
            IsLargeSite              = 0.5
            LargeListCount           = 0.5
            LargeListViewCount       = 0.5
            CheckedOutFileCount      = 0.05
            # Excel workbooks that SharePoint Online does not open in the browser are migrated: the
            # signal says whom to warn, it does not move a site collection to a worse category.
            LargeExcelFileCount      = 0
            # Audience-targeted items and site notebooks are migrated, with another name for the notebook
            # and without the targeting: the signals say whom to warn and what to rebuild, they do not
            # move a site collection to a worse category.
            AudienceTargetedItemCount = 0
            SiteNotebookCount        = 0
            # The customized profile page of a My Site host does not migrate either: the signal says whom to
            # warn, it does not move a site collection to a worse category.
            CustomizedProfilePageCount = 0
            FileVersionCount         = 0
            # Code that runs in the farm is not a blocker here but a modernization project: the
            # sandboxed solutions are retired, and the full-trust code, the custom master pages
            # and the event receivers do not run in the modern experience and are rebuilt with
            # the SharePoint Framework (SPFx). The weights are heavy enough to put a site that
            # has one of them above the Complex threshold with another signal.
            SandboxSolutions         = 3.0
            UsesFullTrustCode        = 4.0
            UsesCustomFarmFeature    = 2.0
            CustomMasterPage         = 3.0
            EventReceivers           = 1.5
            # What makes a page or a list fall back to the classic experience, and is rebuilt for
            # the modern one: an alternate CSS URL on a web (a site theme replaces it), a list view
            # that renders with XSLT (view formatting or an SPFx field customizer replaces it), a
            # Script Editor or Content Editor web part that holds script (an SPFx web part or
            # extension replaces it), a site collection or a web that opted out of the modern list
            # and library experience, and a list forced to the classic experience (the opt-out is
            # removed, and the lists checked). ModernBlockerCount only brings these signals and the
            # custom master page and the publishing features together for the reports: it does not
            # weigh, or each blocker would count twice.
            AlternateCssUrlCount     = 1.5
            XsltListViewCount        = 1.0
            ScriptWebPartCount       = 1.5
            ClassicExperienceOptOutCount = 1.0
            ClassicExperienceListCount = 0.5
            ModernBlockerCount       = 0
            UniquePermissionsCount   = 0
            SizeGB                   = 0
        }

        # Score thresholds that promote a site to the next category.
        Thresholds = @{
            Moderate = 1.0
            Complex  = 6.0
        }

        # Signals that force category 4 (Blocked) regardless of the score. Few signals should:
        # a site is blocked when nothing in the modern experience can replace what it does.
        # InfoPath Forms Services is such a case: its support ended on 14 July 2026 and the forms
        # have no modern editor. UsesFullTrustCode and UsesCustomFarmFeature are NOT here: they
        # are code to rebuild with SPFx, which the weights above express. Add them if your
        # organization treats any full-trust solution as a hard blocker.
        BlockingSignals = @(
            'InfoPathFormCount'
        )
    }

    # -------------------------------------------------------------------------------
    # Wave plan (consumed by Group-SPSMigrationWave)
    #
    # Each site is assigned to a wave from its category. In this mode the wave is a
    # modernization wave: what can be switched to the modern experience first, what needs
    # a light remediation, what is rebuilt with SPFx, and what is blocked.
    #
    # Each entry lists the categories it groups. The default below is one wave per
    # category; to put every site that is not blocked in the first wave instead, use:
    #   @{ Wave = 1; Name = 'Modernize now'; Categories = @(1, 2, 3) }
    #   @{ Wave = 2; Name = 'Projects';      Categories = @(4) }
    # A site whose category is not listed lands in an 'Unassigned' bucket. A site whose
    # assessment failed is in 'Not assessed', and a Modern-ready site (category 1) whose
    # assessment is partial is in 'Needs review', whatever the entries say: what could not be
    # read counts as 0, so it waits there until it is read in full.
    # -------------------------------------------------------------------------------
    MigrationWaves = @(
        @{ Wave = 1; Name = 'Ready'; Categories = @(1) }
        @{ Wave = 2; Name = 'Light remediation'; Categories = @(2) }
        @{ Wave = 3; Name = 'Rebuild (SPFx)'; Categories = @(3) }
        @{ Wave = 4; Name = 'Blocked'; Categories = @(4) }
    )
}
