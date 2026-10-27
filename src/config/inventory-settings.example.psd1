# =====================================================================================
# SPSSiteInventory - Inventory settings (example)
#
# Copy this file to inventory-settings.psd1 and adjust the values for your farm. The
# real inventory-settings.psd1 is gitignored so environment-specific details (URLs,
# in-house solution names) stay out of version control.
#
# No client-specific value ships in this repository: this file is a neutral example.
# =====================================================================================
@{
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
    }

    # -------------------------------------------------------------------------------
    # Site-template parity rules (SMAT P0 scope)
    #
    # SPSSiteInventory maps each root-web template to:
    # - Compatible: known template families with supported SPO migration paths
    # - Unsupported: templates explicitly listed below
    # - Review: template values outside the supported map (manual validation needed)
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
    # SharePoint gives Limited Access, Read, Contribute, Design, Full Control, Edit and
    # Restricted Read a base type, so they are never reported as custom. The levels it
    # provisions for features and site templates (View Only, Approve, Manage Hierarchy,
    # Restricted Interfaces for Translation, Moderate, Records Center Web Service
    # Submitters) are recognized by their English names. On a non-English farm, list the
    # localized names here; they are added to the English ones. Otherwise those levels
    # are reported as custom permission levels.
    # -------------------------------------------------------------------------------
    PermissionLevels = @{
        BuiltInNames = @()
    }

    # -------------------------------------------------------------------------------
    # Scoring engine (consumed by Measure-SPSSiteComplexity)
    #
    # Category mapping:
    #   1 Simple    - score below Moderate, no blocking signal
    #   2 Moderate  - score at or above Moderate
    #   3 Complex   - score at or above Complex
    #   4 Blocking  - any BlockingSignals value is truthy (overrides the score)
    # -------------------------------------------------------------------------------
    Scoring = @{
        # Weighted signals: weight * signal value is summed into the score.
        # Booleans count as 1 when true; counts contribute their value.
        Weights = @{
            # SharePoint 2010 workflows run on the legacy engine, retired in SharePoint
            # Online: they always need a rebuild, so they weigh heavily. Add
            # 'Workflow2010Count' to BlockingSignals below if your organization treats
            # any legacy workflow as a hard blocker.
            Workflow2010Count        = 3.0
            # SharePoint 2013 workflows (Workflow Manager) are a lighter, more direct
            # remediation, so they weigh less than their 2010 counterparts.
            Workflow2013Count        = 1.5
            # Running workflow instances indicate immediate cutover risk and cleanup
            # effort in addition to workflow definition migration.
            Workflow2010RunningInstanceCount = 1.0
            Workflow2013RunningInstanceCount = 0.5
            # SharePoint add-ins and app webs often require replacement planning in
            # SharePoint Online, especially for provider-hosted/custom add-ins.
            AppInstanceCount = 1.0
            AppWebCount = 1.5
            # Classic publishing sites rely on page layouts and publishing features that
            # need extensive remediation. Weighted, not blocking: add
            # 'PublishingInfrastructureEnabled' to BlockingSignals to treat them as projects.
            PublishingInfrastructureEnabled = 2.0
            PublishingWebCount = 0.5
            PublishingPageLayoutCount = 0.5
            PublishingPageCount = 0.001
            # Customized (unghosted) pages are reverted to their default state on migration.
            CustomizedPageCount = 1.0
            # Custom permission levels may not be carried over by migration tools and must
            # be recreated or replaced. Not blocking; see PermissionLevels above.
            CustomPermissionLevelCount = 0.5
            # Incoming e-mail is not available in SharePoint Online.
            EmailEnabledListCount = 0.5
            # .htm/.html files prompt a download under the Strict browser file handling that
            # SharePoint Online enforces. Counted only where a web application is Permissive.
            HtmlFileCount = 0.1
            # Managed metadata columns read their values from the term store, which is
            # migrated separately from the sites. Weighted, not blocking.
            ManagedMetadataListCount = 0.1
            ManagedMetadataTermSetCount = 0.25
            # External lists are backed by BCS external content types. BCS is retired in
            # SharePoint Online, so these lists cannot be migrated there and need a replacement
            # such as Power Apps. Weighted, and listed in BlockingSignals below.
            ExternalListCount = 1.0
            # Unsupported site templates cannot be migrated directly to SPO.
            IsUnsupportedSiteTemplate = 5.0
            # Language mismatches or unknown language metadata require readiness review.
            TemplateLanguageReviewRequired = 0.5
            # InfoPath forms (retired, no SharePoint Online equivalent) must be rebuilt in
            # Power Apps. Weighted heavily and listed as a blocking signal below.
            InfoPathFormCount        = 3.0
            # IRM-enabled lists and libraries require records-protection remediation
            # before migration.
            IrmEnabledListCount      = 2.5
            # Large-content risk signals (SMAT parity scope).
            IsLargeSite              = 1.5
            LargeListCount           = 0.5
            LargeListViewCount       = 0.5
            CheckedOutFileCount      = 0.05
            FileVersionCount         = 0.02
            SandboxSolutions         = 3.0
            CustomMasterPage         = 2.0
            EventReceivers           = 1.5
            UniquePermissionsCount   = 0.01
            SizeGB                   = 0.02
        }

        # Score thresholds that promote a site to the next category.
        Thresholds = @{
            Moderate = 1.0
            Complex  = 6.0
        }

        # Signals that force category 4 (Blocking) regardless of the score.
        # UsesFullTrustCode marks a site that activates a feature from a custom
        # full-trust solution (a WSP deploying a global assembly): not portable to
        # SharePoint Online as-is.
        BlockingSignals = @(
            'UsesCustomFarmFeature'
            'UsesFullTrustCode'
            'InfoPathFormCount'
            # FBA on any zone requires identity/authentication remediation for SPO.
            # This is a configured capability, not a measurement of active users.
            'HasFbaZone'
            # Site lock states (ReadOnly / NoAdditions / NoAccess) indicate migration
            # blockers until the lock is removed or changed.
            'IsLockedSite'
            # IRM protection on lists/libraries requires migration remediation.
            'IrmEnabledListCount'
            # Unsupported templates are not migration targets as-is.
            'IsUnsupportedSiteTemplate'
            # External lists depend on BCS, which is retired in SharePoint Online: they cannot be
            # recreated there and the scenario needs a replacement such as Power Apps. The site
            # itself can still be migrated; remove this entry to treat the replacement as
            # remediation of a Moderate or Complex site instead of a dedicated project.
            'ExternalListCount'
        )
    }

    # -------------------------------------------------------------------------------
    # Migration wave plan (consumed by Group-SPSMigrationWave)
    #
    # Each site is assigned to a wave from its complexity category. The migrated unit
    # is the site collection, so waves are planned per site by complexity - content
    # databases are an on-premises storage concern with no SharePoint Online
    # equivalent and are not used here.
    #
    # Each entry lists the categories it groups. The default below is one wave per
    # category; to put every non-blocking site in the first wave instead, use:
    #   @{ Wave = 1; Name = 'Migrate now'; Categories = @(1, 2, 3) }
    #   @{ Wave = 2; Name = 'Projects';    Categories = @(4) }
    # A site whose category is not listed lands in an 'Unassigned' bucket.
    # -------------------------------------------------------------------------------
    MigrationWaves = @(
        @{ Wave = 1; Name = 'Quick wins'; Categories = @(1) }
        @{ Wave = 2; Name = 'Light remediation'; Categories = @(2) }
        @{ Wave = 3; Name = 'Rebuild'; Categories = @(3) }
        @{ Wave = 4; Name = 'Projects / blockers'; Categories = @(4) }
    )
}
