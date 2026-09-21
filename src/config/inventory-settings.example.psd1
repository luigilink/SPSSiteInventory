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

    # Case-insensitive name prefixes that mark a farm solution (WSP) as custom / in-house.
    # Any site activating a feature from a matching solution is flagged and can be scored
    # as blocking. Replace with your own product/solution prefixes.
    CustomSolutionPrefix = @(
        'contoso'
    )

    # Folder where the CSV/JSON reports are written.
    OutputFolder = 'C:\SPSSiteInventory\Reports'

    # Days of run logs kept under the Logs folder.
    LogRetentionDays = 90

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
            # InfoPath forms (retired, no SharePoint Online equivalent) must be rebuilt in
            # Power Apps. Weighted heavily and listed as a blocking signal below.
            InfoPathFormCount        = 3.0
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
        )
    }
}
