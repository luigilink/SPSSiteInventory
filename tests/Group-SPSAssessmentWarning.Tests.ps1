# Behavior tests for Group-SPSAssessmentWarning (pure, no farm needed).
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:Module = Get-Module -Name SPSSiteInventory.Common

    # Group-SPSAssessmentWarning is private; reach it inside the module scope.
    function Group-Warning {
        param ([AllowNull()] [AllowEmptyCollection()] [AllowEmptyString()] [System.String[]] $Warning)

        return @(& $script:Module { param($w) Group-SPSAssessmentWarning -Warning $w } $Warning)
    }

    $script:Reason = 'Cannot find an overload for "GetItems" and the argument count: "1".'
}

Describe 'Group-SPSAssessmentWarning' {
    It 'returns nothing for an empty list, a null list or only empty entries' {
        @(Group-Warning -Warning @()) | Should -HaveCount 0
        @(Group-Warning -Warning $null) | Should -HaveCount 0
        @(Group-Warning -Warning @('', $null, '')) | Should -HaveCount 0
    }

    It 'returns a warning that occurs once unchanged' {
        $warning = "Could not read checked-out files on 'appfiles' in web 'https://contoso/sites/a': $script:Reason"

        $result = @(Group-Warning -Warning @($warning))

        $result | Should -HaveCount 1
        $result[0] | Should -BeExactly $warning
    }

    It 'groups warnings that differ only by the quoted names, keeping the first one verbatim' {
        $warnings = @(
            "Could not read checked-out files on 'appfiles' in web 'https://contoso/sites/a': $script:Reason"
            "Could not read checked-out files on 'Documents' in web 'https://contoso/sites/a/hr': $script:Reason"
            "Could not read checked-out files on 'Pages' in web 'https://contoso/sites/a': $script:Reason"
        )

        $result = @(Group-Warning -Warning $warnings)

        $result | Should -HaveCount 1
        $result[0] | Should -BeExactly "Could not read checked-out files on 'appfiles' in web 'https://contoso/sites/a': $script:Reason [+2 similar]"
    }

    It 'counts every extra occurrence of a kind' {
        $warnings = 1..11 | ForEach-Object { "Could not read checked-out files on 'list$_' in web 'https://contoso/sites/a': $script:Reason" }

        $result = @(Group-Warning -Warning $warnings)

        $result | Should -HaveCount 1
        $result[0] | Should -BeExactly "Could not read checked-out files on 'list1' in web 'https://contoso/sites/a': $script:Reason [+10 similar]"
    }

    It 'keeps the order of first appearance across the kinds' {
        $warnings = @(
            "Could not read versions on 'a' in web 'https://contoso/sites/a': Access denied"
            'Customization inventory partial; some signals may be missing.'
            "Could not read versions on 'b' in web 'https://contoso/sites/a': Access denied"
            "Could not read checked-out files on 'a' in web 'https://contoso/sites/a': Access denied"
            "Could not read checked-out files on 'c' in web 'https://contoso/sites/a': Access denied"
        )

        $result = @(Group-Warning -Warning $warnings)

        $result | Should -HaveCount 3
        $result[0] | Should -BeExactly "Could not read versions on 'a' in web 'https://contoso/sites/a': Access denied [+1 similar]"
        $result[1] | Should -BeExactly 'Customization inventory partial; some signals may be missing.'
        $result[2] | Should -BeExactly "Could not read checked-out files on 'a' in web 'https://contoso/sites/a': Access denied [+1 similar]"
    }

    It 'does not merge warnings with a different reason or different numbers' {
        $warnings = @(
            "Could not read checked-out files on 'a' in web 'https://contoso/sites/a': Access denied"
            "Could not read checked-out files on 'b' in web 'https://contoso/sites/a': The server is busy"
            "Could not read 2 versions on 'a' in web 'https://contoso/sites/a': Access denied"
            "Could not read 3 versions on 'a' in web 'https://contoso/sites/a': Access denied"
        )

        $result = @(Group-Warning -Warning $warnings)

        $result | Should -HaveCount 4
        $result | Should -Not -Match 'similar'
    }

    It 'never splits a warning on a semicolon' {
        $warning = 'Customization inventory partial; some signals may be missing.'

        $result = @(Group-Warning -Warning @($warning, $warning, 'Content-type inventory partial; content-type counts may be incomplete.'))

        $result | Should -HaveCount 2
        $result[0] | Should -BeExactly 'Customization inventory partial; some signals may be missing. [+1 similar]'
        $result[1] | Should -BeExactly 'Content-type inventory partial; content-type counts may be incomplete.'
    }

    It 'ignores null and empty entries when it groups the others' {
        $result = @(Group-Warning -Warning @($null, "Lists unreadable on 'a': Access denied", '', "Lists unreadable on 'b': Access denied"))

        $result | Should -HaveCount 1
        $result[0] | Should -BeExactly "Lists unreadable on 'a': Access denied [+1 similar]"
    }

    It 'groups warnings without any quoted token only when they are identical' {
        $result = @(Group-Warning -Warning @('Access denied', 'Access denied', 'Access denied.'))

        $result | Should -HaveCount 2
        $result[0] | Should -BeExactly 'Access denied [+1 similar]'
        $result[1] | Should -BeExactly 'Access denied.'
    }
}
