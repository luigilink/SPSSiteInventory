BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
}

Describe 'Get-SPSSiteTemplateParity' {
    It 'marks explicitly unsupported templates as blockers' {
        $result = InModuleScope SPSSiteInventory.Common {
            Get-SPSSiteTemplateParity -Template 'APP#0' -LanguageLcid 1033
        }

        $result.IsUnsupportedSiteTemplate | Should -BeTrue
        $result.TemplateCompatibility | Should -Be 'Unsupported'
        $result.TemplateCompatibilityReason | Should -Match 'not migration targets'
    }

    It 'marks known template families as compatible' {
        $result = InModuleScope SPSSiteInventory.Common {
            Get-SPSSiteTemplateParity -Template 'STS#3' -LanguageLcid 1036
        }

        $result.IsUnsupportedSiteTemplate | Should -BeFalse
        $result.TemplateCompatibility | Should -Be 'Compatible'
        $result.TemplateLanguageReviewRequired | Should -BeFalse
        $result.TemplateLanguageTag | Should -Be 'fr-FR'
    }

    It 'treats personal sites as compatible sources mapped to OneDrive' {
        $result = InModuleScope SPSSiteInventory.Common {
            Get-SPSSiteTemplateParity -Template 'SPSPERS#0' -LanguageLcid 1033
        }

        $result.IsUnsupportedSiteTemplate | Should -BeFalse
        $result.TemplateCompatibility | Should -Be 'Compatible'
        $result.TemplateCompatibilityReason | Should -Match 'OneDrive'
    }

    It 'flags blog templates for compatibility review by default' {
        $result = InModuleScope SPSSiteInventory.Common {
            Get-SPSSiteTemplateParity -Template 'BLOG#0' -LanguageLcid 1033
        }

        $result.IsUnsupportedSiteTemplate | Should -BeFalse
        $result.TemplateCompatibility | Should -Be 'Review'
        $result.TemplateCompatibilityReason | Should -Match 'remapping'
    }

    It 'marks unmapped templates for review' {
        $result = InModuleScope SPSSiteInventory.Common {
            Get-SPSSiteTemplateParity -Template 'CUSTOM#42' -LanguageLcid 1033
        }

        $result.TemplateCompatibility | Should -Be 'Review'
        $result.TemplateCompatibilityReason | Should -Match 'not mapped'
    }

    It 'flags unrecognized language LCIDs for review' {
        $result = InModuleScope SPSSiteInventory.Common {
            Get-SPSSiteTemplateParity -Template 'STS#0' -LanguageLcid 999999
        }

        $result.TemplateLanguageReviewRequired | Should -BeTrue
        $result.TemplateLanguageReason | Should -Match 'not recognized'
    }

    It 'uses SupportedLanguageLcid allow-lists when provided' {
        $result = InModuleScope SPSSiteInventory.Common {
            $rules = @{
                SupportedLanguageLcid = @(1033)
            }
            Get-SPSSiteTemplateParity -Template 'STS#0' -LanguageLcid 1036 -TemplateParity $rules
        }

        $result.TemplateLanguageReviewRequired | Should -BeTrue
        $result.TemplateLanguageReason | Should -Match 'outside SupportedLanguageLcid'
    }
}
