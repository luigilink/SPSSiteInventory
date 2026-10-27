BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
    $script:ModuleName = 'SPSSiteInventory.Common'

    function global:Get-SPFarm {
        [CmdletBinding()]
        param ()
        throw 'Unmocked SharePoint call: Get-SPFarm'
    }
    function global:Get-SPWebApplication {
        [CmdletBinding()]
        param ($Identity)
        throw 'Unmocked SharePoint call: Get-SPWebApplication'
    }

    $script:ReportsFolder = Join-Path -Path $TestDrive -ChildPath 'Reports'
    New-Item -Path $script:ReportsFolder -ItemType Directory -Force | Out-Null

    function Get-SettingsBody {
        param
        (
            [System.String] $OutputFolderLine = "OutputFolder = '$($script:ReportsFolder)'",
            [System.String] $WebApplicationUrl = '@()',
            [System.String] $Weights = 'WorkflowCount = 1.0; InfoPathFormCount = 3.0',
            [System.String] $BlockingSignals = "'InfoPathFormCount'",
            [System.String] $Extra = ''
        )

        return @"
@{
    EnvName           = 'LAB'
    WebApplicationUrl = $WebApplicationUrl
    $OutputFolderLine
    $Extra
    Scoring           = @{
        Weights         = @{ $Weights }
        Thresholds      = @{ Moderate = 2; Complex = 5 }
        BlockingSignals = @($BlockingSignals)
    }
}
"@
    }

    function Write-TestSettings {
        param
        (
            [System.String] $Name,
            [System.String] $Body
        )

        $path = Join-Path -Path $TestDrive -ChildPath $Name
        Set-Content -Path $path -Value $Body -Encoding UTF8
        return $path
    }

    function Get-TestResult {
        param
        (
            [System.Object[]] $Check,
            [System.String] $Name
        )

        return @($Check | Where-Object { $_.Name -eq $Name })[0]
    }

    $script:SettingsPath = Write-TestSettings -Name 'inventory-settings.psd1' -Body (Get-SettingsBody)
    $script:ExamplePath = Write-TestSettings -Name 'inventory-settings.example.psd1' -Body (Get-SettingsBody)
}

AfterAll {
    Remove-Item -Path 'function:global:Get-SPFarm' -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:Get-SPWebApplication' -ErrorAction SilentlyContinue
}

Describe 'Get-SPSReadinessCheck' {
    BeforeEach {
        Mock -ModuleName $script:ModuleName Get-SPSHostEnvironment {
            [PSCustomObject]@{ Edition = 'Desktop'; Version = '5.1.14393.6343'; VersionMajor = 5; VersionMinor = 1; ComputerName = 'SP01'; UserName = 'CONTOSO\spfarm'; IsElevated = $true }
        }
        Mock -ModuleName $script:ModuleName Get-SPSInstalledProductVersion {
            [PSCustomObject]@{ ProductMajorPart = 16; ProductMinorPart = 0; ProductBuildPart = 18526; ProductPrivatePart = 20424 }
        }
        Mock -ModuleName $script:ModuleName Import-SPSSharePointCommand { }
        Mock -ModuleName $script:ModuleName Get-SPFarm {
            $farm = [PSCustomObject]@{ Name = 'SP_Config' }
            $farm | Add-Member -MemberType ScriptMethod -Name CurrentUserIsAdministrator -Value { $true }
            $farm
        }
        Mock -ModuleName $script:ModuleName Get-SPWebApplication {
            if ($PSBoundParameters.ContainsKey('Identity')) {
                [PSCustomObject]@{ Url = $Identity }
            }
            else {
                [PSCustomObject]@{ Url = 'https://intranet' }
                [PSCustomObject]@{ Url = 'https://mysites' }
            }
        }
    }

    Context 'a farm server that is ready' {
        BeforeEach {
            $script:Checks = @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath -ExampleConfigPath $script:ExamplePath)
        }

        It 'has no error, no warning and nothing skipped' {
            @($script:Checks | Where-Object { $_.Status -ne 'OK' }) | Should -BeNullOrEmpty
        }

        It 'gives every check a section, a name, a status, a detail and the blocking flag' {
            foreach ($check in $script:Checks) {
                $check.Section | Should -Not -BeNullOrEmpty
                $check.Name | Should -Not -BeNullOrEmpty
                $check.Status | Should -BeIn @('OK', 'Warning', 'Error', 'Skipped')
                $check.PSObject.Properties.Name | Should -Contain 'Detail'
                $check.IsBlocking | Should -BeFalse
            }
        }

        It 'lists the sections in the order of the run' {
            $sections = @($script:Checks | ForEach-Object { $_.Section } | Select-Object -Unique)

            $sections | Should -Be @('Toolkit', 'PowerShell', 'Settings', 'SharePoint')
        }

        It 'reports what it found' {
            (Get-TestResult -Check $script:Checks -Name 'Windows PowerShell 5.1').Detail | Should -Be 'Version 5.1.14393.6343'
            (Get-TestResult -Check $script:Checks -Name 'Elevated session').Detail | Should -Be 'Running as CONTOSO\spfarm.'
            (Get-TestResult -Check $script:Checks -Name 'SharePoint installed').Detail | Should -Be 'Build 16.0.18526.20424'
            (Get-TestResult -Check $script:Checks -Name 'Farm connection').Detail | Should -Be "Configuration database 'SP_Config'."
            (Get-TestResult -Check $script:Checks -Name 'Web applications').Detail | Should -Be '2 content web application(s) will be scanned.'
            (Get-TestResult -Check $script:Checks -Name 'SPSSiteInventory.Common module').Detail | Should -Match '^Version \d+\.\d+\.\d+'
        }

        It 'is read-only: it does not create the output folder of the settings file' {
            $missingFolder = Join-Path -Path $TestDrive -ChildPath 'NotCreated\Reports'
            $path = Write-TestSettings -Name 'readonly.psd1' -Body (Get-SettingsBody -OutputFolderLine "OutputFolder = '$missingFolder'")

            $null = Get-SPSReadinessCheck -ConfigPath $path

            Test-Path -LiteralPath $missingFolder | Should -BeFalse
            Test-Path -LiteralPath (Split-Path -Path $missingFolder -Parent) | Should -BeFalse
        }
    }

    Context 'the PowerShell host' {
        It 'is an error in PowerShell 7, which cannot load the SharePoint snap-in' {
            Mock -ModuleName $script:ModuleName Get-SPSHostEnvironment {
                [PSCustomObject]@{ Edition = 'Core'; Version = '7.4.1'; VersionMajor = 7; VersionMinor = 4; ComputerName = 'SP01'; UserName = 'spfarm'; IsElevated = $true }
            }

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Windows PowerShell 5.1'

            $result.Status | Should -Be 'Error'
            $result.IsBlocking | Should -BeTrue
            $result.Detail | Should -Match 'powershell\.exe'
        }

        It 'is a warning for another Windows PowerShell version' {
            Mock -ModuleName $script:ModuleName Get-SPSHostEnvironment {
                [PSCustomObject]@{ Edition = 'Desktop'; Version = '5.0.10586.117'; VersionMajor = 5; VersionMinor = 0; ComputerName = 'SP01'; UserName = 'spfarm'; IsElevated = $true }
            }

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Windows PowerShell 5.1'

            $result.Status | Should -Be 'Warning'
            $result.IsBlocking | Should -BeFalse
        }

        It 'is an error when the session is not elevated' {
            Mock -ModuleName $script:ModuleName Get-SPSHostEnvironment {
                [PSCustomObject]@{ Edition = 'Desktop'; Version = '5.1.14393.6343'; VersionMajor = 5; VersionMinor = 1; ComputerName = 'SP01'; UserName = 'spfarm'; IsElevated = $false }
            }

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Elevated session'

            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'Run as administrator'
        }

        It 'skips the elevation check where it cannot be determined' {
            Mock -ModuleName $script:ModuleName Get-SPSHostEnvironment {
                [PSCustomObject]@{ Edition = 'Core'; Version = '7.4.1'; VersionMajor = 7; VersionMinor = 4; ComputerName = 'mac'; UserName = 'jc'; IsElevated = $null }
            }

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Elevated session'

            $result.Status | Should -Be 'Skipped'
        }
    }

    Context 'the settings file' {
        It 'is an error when it does not exist, and says what to do' {
            $missing = Join-Path -Path $TestDrive -ChildPath 'missing.psd1'

            $checks = @(Get-SPSReadinessCheck -ConfigPath $missing)

            $result = Get-TestResult -Check $checks -Name 'Settings file'
            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'inventory-settings\.example\.psd1'
            Get-TestResult -Check $checks -Name 'Settings content' | Should -BeNullOrEmpty
            Get-TestResult -Check $checks -Name 'Output folder' | Should -BeNullOrEmpty
        }

        It 'is an error when the Scoring section is missing' {
            $path = Write-TestSettings -Name 'noscoring.psd1' -Body "@{ EnvName = 'LAB' }"

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $path) -Name 'Settings content'

            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'Scoring'
        }

        It 'is an error when the SharePointAlerts section is not valid' {
            $path = Write-TestSettings -Name 'badalerts.psd1' -Body (Get-SettingsBody -Extra "SharePointAlerts = @{ IncludeUserLogin = 'false' }")

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $path) -Name 'Settings content'

            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'IncludeUserLogin'
        }

        It 'is an error when the settings file cannot be parsed' {
            $path = Write-TestSettings -Name 'broken.psd1' -Body '@{ EnvName = '

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $path) -Name 'Settings content'

            $result.Status | Should -Be 'Error'
        }
    }

    Context 'the output folder' {
        It 'is an error when OutputFolder is not set, because the scan would fail when it writes the reports' {
            $path = Write-TestSettings -Name 'nooutput.psd1' -Body (Get-SettingsBody -OutputFolderLine '')

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $path) -Name 'Output folder'

            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'OutputFolder is not set'
        }

        It 'is OK when the folder exists' {
            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Output folder'

            $result.Status | Should -Be 'OK'
            $result.Detail | Should -Be $script:ReportsFolder
        }

        It 'is OK when the folder does not exist yet but can be created' {
            $newFolder = Join-Path -Path $TestDrive -ChildPath 'NewReports'
            $path = Write-TestSettings -Name 'newfolder.psd1' -Body (Get-SettingsBody -OutputFolderLine "OutputFolder = '$newFolder'")

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $path) -Name 'Output folder'

            $result.Status | Should -Be 'OK'
            $result.Detail | Should -Match 'does not exist yet; the scan creates it'
            Test-Path -LiteralPath $newFolder | Should -BeFalse
        }

        It 'is an error when a part of the path is a file, because the scan could not create the folder below it' {
            $file = Join-Path -Path $TestDrive -ChildPath 'AFile2.txt'
            Set-Content -Path $file -Value 'x'
            $nested = Join-Path -Path (Join-Path -Path $file -ChildPath 'Reports') -ChildPath 'Deeper'
            $path = Write-TestSettings -Name 'underfile.psd1' -Body (Get-SettingsBody -OutputFolderLine "OutputFolder = '$nested'")

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $path) -Name 'Output folder'

            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'is a file, not a folder'
            $result.Detail | Should -Match 'AFile2\.txt'
        }

        It 'is an error when the path is a file' {
            $file = Join-Path -Path $TestDrive -ChildPath 'AFile.txt'
            Set-Content -Path $file -Value 'x'
            $path = Write-TestSettings -Name 'file.psd1' -Body (Get-SettingsBody -OutputFolderLine "OutputFolder = '$file'")

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $path) -Name 'Output folder'

            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'is a file, not a folder'
        }
    }

    Context 'the comparison with the example configuration' {
        BeforeAll {
            $script:NewerExample = Write-TestSettings -Name 'example-newer.psd1' -Body (Get-SettingsBody `
                    -Weights 'WorkflowCount = 1.0; InfoPathFormCount = 3.0; HasFbaZone = 2.0; ExternalListCount = 1.0; HasNoAccessLock = 4.0' `
                    -BlockingSignals "'InfoPathFormCount', 'HasFbaZone', 'ExternalListCount', 'HasNoAccessLock'")
        }

        It 'warns about the blocking signals of the example that the settings do not have' {
            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath -ExampleConfigPath $script:NewerExample) -Name 'Blocking signals'

            $result.Status | Should -Be 'Warning'
            $result.IsBlocking | Should -BeFalse
            $result.Detail | Should -Match '^3 blocking signal\(s\)'
            $result.Detail | Should -Match 'HasFbaZone'
            $result.Detail | Should -Match 'ExternalListCount'
            $result.Detail | Should -Match 'HasNoAccessLock'
            $result.Detail | Should -Match 'not classified as Blocking'
        }

        It 'warns about the weights of the example that the settings do not have' {
            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath -ExampleConfigPath $script:NewerExample) -Name 'Signal weights'

            $result.Status | Should -Be 'Warning'
            $result.Detail | Should -Match '^3 signal\(s\)'
            $result.Detail | Should -Match 'ExternalListCount, HasFbaZone, HasNoAccessLock'
            $result.Detail | Should -Match 'do not change the score'
        }

        It 'does not ask for HasNoAccessLock when IsLockedSite already blocks every lock' {
            $path = Write-TestSettings -Name 'islocked.psd1' -Body (Get-SettingsBody -BlockingSignals "'InfoPathFormCount', 'HasFbaZone', 'ExternalListCount', 'IsLockedSite'")

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $path -ExampleConfigPath $script:NewerExample) -Name 'Blocking signals'

            $result.Status | Should -Be 'OK'
        }

        It 'is OK when the settings have more than the example' {
            $path = Write-TestSettings -Name 'more.psd1' -Body (Get-SettingsBody `
                    -Weights 'WorkflowCount = 1.0; InfoPathFormCount = 3.0; HasFbaZone = 2.0; ExternalListCount = 1.0; HasNoAccessLock = 4.0; Extra = 1.0' `
                    -BlockingSignals "'InfoPathFormCount', 'HasFbaZone', 'ExternalListCount', 'HasNoAccessLock', 'Extra'")

            $checks = @(Get-SPSReadinessCheck -ConfigPath $path -ExampleConfigPath $script:NewerExample)

            (Get-TestResult -Check $checks -Name 'Blocking signals').Status | Should -Be 'OK'
            (Get-TestResult -Check $checks -Name 'Signal weights').Status | Should -Be 'OK'
        }

        It 'shortens a long list of signals' {
            $weights = (1..12 | ForEach-Object { 'Signal{0:D2} = 1.0' -f $_ }) -join '; '
            $exampleFile = Write-TestSettings -Name 'example-long.psd1' -Body (Get-SettingsBody -Weights $weights -BlockingSignals '')

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath -ExampleConfigPath $exampleFile) -Name 'Signal weights'

            $result.Detail | Should -Match '^12 signal\(s\)'
            $result.Detail | Should -Match 'Signal08, and 4 more\.'
            $result.Detail | Should -Not -Match 'Signal09'
        }

        It 'is skipped, with the reason, when the example cannot be read' {
            $brokenExample = Write-TestSettings -Name 'example-broken.psd1' -Body "@{ EnvName = 'x' }"

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath -ExampleConfigPath $brokenExample) -Name 'Comparison with the example'

            $result.Status | Should -Be 'Skipped'
            $result.Detail | Should -Match 'could not be read'
        }

        It 'is skipped, with the path, when the example file does not exist' {
            $missingExample = Join-Path -Path $TestDrive -ChildPath 'no-such-example.psd1'

            $checks = @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath -ExampleConfigPath $missingExample)
            $result = Get-TestResult -Check $checks -Name 'Comparison with the example'

            $result.Section | Should -Be 'Settings'
            $result.Status | Should -Be 'Skipped'
            $result.IsBlocking | Should -BeFalse
            $result.Detail | Should -Be ('The example settings file was not found at {0}: the blocking signals and the weights were not compared.' -f $missingExample)
            Get-TestResult -Check $checks -Name 'Blocking signals' | Should -BeNullOrEmpty
            Get-TestResult -Check $checks -Name 'Signal weights' | Should -BeNullOrEmpty
        }

        It 'does not change the verdict when the example file does not exist' {
            $missingExample = Join-Path -Path $TestDrive -ChildPath 'no-such-example.psd1'

            $checks = @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath -ExampleConfigPath $missingExample)
            $report = Write-SPSReadinessReport -Check $checks 6>$null

            @($checks | Where-Object { $_.Status -ne 'OK' }) | Should -HaveCount 1
            $report.IsReady | Should -BeTrue
            $report.ErrorCount | Should -Be 0
            $report.WarningCount | Should -Be 0
            $report.SkippedCount | Should -Be 1
        }

        It 'adds no comparison result when the example path is empty' {
            $checks = @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath -ExampleConfigPath '')

            Get-TestResult -Check $checks -Name 'Comparison with the example' | Should -BeNullOrEmpty
        }

        It 'does not compare when no example is given' {
            $checks = @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath)

            Get-TestResult -Check $checks -Name 'Blocking signals' | Should -BeNullOrEmpty
            Get-TestResult -Check $checks -Name 'Signal weights' | Should -BeNullOrEmpty
            Get-TestResult -Check $checks -Name 'Comparison with the example' | Should -BeNullOrEmpty
        }
    }

    Context 'SharePoint' {
        It 'skips every SharePoint check on request, without calling SharePoint' {
            $checks = @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath -SkipSharePoint)

            $result = Get-TestResult -Check $checks -Name 'SharePoint checks'
            $result.Status | Should -Be 'Skipped'
            $result.Detail | Should -Match '-SkipSharePoint'
            Should -Invoke -ModuleName $script:ModuleName Get-SPSInstalledProductVersion -Times 0 -Exactly
            Should -Invoke -ModuleName $script:ModuleName Import-SPSSharePointCommand -Times 0 -Exactly
        }

        It 'is an error when SharePoint is not installed, and the farm checks are skipped' {
            Mock -ModuleName $script:ModuleName Get-SPSInstalledProductVersion { $null }

            $checks = @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath)

            $installed = Get-TestResult -Check $checks -Name 'SharePoint installed'
            $installed.Status | Should -Be 'Error'
            $installed.IsBlocking | Should -BeTrue
            $installed.Detail | Should -Match 'farm server'
            (Get-TestResult -Check $checks -Name 'SharePoint commands').Status | Should -Be 'Skipped'
            (Get-TestResult -Check $checks -Name 'Farm connection').Status | Should -Be 'Skipped'
            Should -Invoke -ModuleName $script:ModuleName Import-SPSSharePointCommand -Times 0 -Exactly
            Should -Invoke -ModuleName $script:ModuleName Get-SPFarm -Times 0 -Exactly
        }

        It 'is an error when the SharePoint commands cannot be loaded, and the farm is not queried' {
            Mock -ModuleName $script:ModuleName Import-SPSSharePointCommand { throw 'The snap-in is not registered.' }

            $checks = @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath)

            $result = Get-TestResult -Check $checks -Name 'SharePoint commands'
            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'could not be loaded: The snap-in is not registered\.'
            (Get-TestResult -Check $checks -Name 'Farm connection').Status | Should -Be 'Skipped'
            Should -Invoke -ModuleName $script:ModuleName Get-SPFarm -Times 0 -Exactly
        }

        It 'is an error when the farm cannot be reached, and the checks that need it are skipped' {
            Mock -ModuleName $script:ModuleName Get-SPFarm { throw 'Cannot connect to the configuration database.' }

            $checks = @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath)

            $result = Get-TestResult -Check $checks -Name 'Farm connection'
            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'Cannot connect to the configuration database'
            (Get-TestResult -Check $checks -Name 'Farm administrator').Status | Should -Be 'Skipped'
            (Get-TestResult -Check $checks -Name 'Web applications').Status | Should -Be 'Skipped'
            Should -Invoke -ModuleName $script:ModuleName Get-SPWebApplication -Times 0 -Exactly
        }

        It 'is a warning, not an error, when the account is not a farm administrator' {
            Mock -ModuleName $script:ModuleName Get-SPFarm {
                $farm = [PSCustomObject]@{ Name = 'SP_Config' }
                $farm | Add-Member -MemberType ScriptMethod -Name CurrentUserIsAdministrator -Value { $false }
                $farm
            }

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Farm administrator'

            $result.Status | Should -Be 'Warning'
            $result.IsBlocking | Should -BeFalse
            $result.Detail | Should -Match 'farm account'
        }

        It 'is a warning when whether the account is a farm administrator cannot be determined' {
            Mock -ModuleName $script:ModuleName Get-SPFarm {
                $farm = [PSCustomObject]@{ Name = 'SP_Config' }
                $farm | Add-Member -MemberType ScriptMethod -Name CurrentUserIsAdministrator -Value { throw 'Access denied.' }
                $farm
            }

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Farm administrator'

            $result.Status | Should -Be 'Warning'
            $result.Detail | Should -Match 'could not be determined'
            $result.Detail | Should -Match 'Access denied'
        }

        It 'checks a blank entry of WebApplicationUrl as the scan would, and reports it as an error' {
            $path = Write-TestSettings -Name 'blankentry.psd1' -Body (Get-SettingsBody -WebApplicationUrl "@('https://intranet', ' ')")

            $checks = @(Get-SPSReadinessCheck -ConfigPath $path)

            (Get-TestResult -Check $checks -Name "Web application 'https://intranet'").Status | Should -Be 'OK'
            $blank = Get-TestResult -Check $checks -Name 'Web application (empty entry)'
            $blank.Status | Should -Be 'Error'
            $blank.Detail | Should -Match 'empty entry'
            Get-TestResult -Check $checks -Name 'Web applications' | Should -BeNullOrEmpty
        }

        It 'reads an empty string as a blank entry, and a missing value or an empty list as every web application' {
            $empty = Write-TestSettings -Name 'emptystring.psd1' -Body (Get-SettingsBody -WebApplicationUrl "''")
            $none = Write-TestSettings -Name 'nullurl.psd1' -Body (Get-SettingsBody -WebApplicationUrl '$null')

            (Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $empty) -Name 'Web application (empty entry)').Status | Should -Be 'Error'
            (Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $none) -Name 'Web applications').Status | Should -Be 'OK'
            (Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Web applications').Status | Should -Be 'OK'
        }

        It 'is an error when the farm has no content web application' {
            Mock -ModuleName $script:ModuleName Get-SPWebApplication { }

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Web applications'

            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'no content web application'
        }

        It 'is an error when the web applications cannot be listed' {
            Mock -ModuleName $script:ModuleName Get-SPWebApplication { throw 'Access denied.' }

            $result = Get-TestResult -Check @(Get-SPSReadinessCheck -ConfigPath $script:SettingsPath) -Name 'Web applications'

            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Match 'could not be listed: Access denied'
        }

        It 'checks each configured web application instead of listing them all' {
            $path = Write-TestSettings -Name 'webapps.psd1' -Body (Get-SettingsBody -WebApplicationUrl "@('https://intranet', 'https://gone')")
            Mock -ModuleName $script:ModuleName Get-SPWebApplication {
                if ($Identity -eq 'https://gone') { throw 'The web application does not exist.' }
                [PSCustomObject]@{ Url = $Identity }
            }

            $checks = @(Get-SPSReadinessCheck -ConfigPath $path)

            (Get-TestResult -Check $checks -Name "Web application 'https://intranet'").Status | Should -Be 'OK'
            $missing = Get-TestResult -Check $checks -Name "Web application 'https://gone'"
            $missing.Status | Should -Be 'Error'
            $missing.Detail | Should -Match 'Not found: The web application does not exist\.'
            Get-TestResult -Check $checks -Name 'Web applications' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-SPSHostEnvironment' {
    It 'describes the host that runs the tests' {
        $module = Get-Module -Name 'SPSSiteInventory.Common'

        $environment = & $module { Get-SPSHostEnvironment }

        $environment.Edition | Should -Be $PSVersionTable.PSEdition
        $environment.Version | Should -Be $PSVersionTable.PSVersion.ToString()
        $environment.VersionMajor | Should -Be $PSVersionTable.PSVersion.Major
        $environment.ComputerName | Should -Not -BeNullOrEmpty
        $environment.UserName | Should -Not -BeNullOrEmpty
        if ($null -ne $environment.IsElevated) {
            $environment.IsElevated | Should -BeOfType [System.Boolean]
        }
    }
}
