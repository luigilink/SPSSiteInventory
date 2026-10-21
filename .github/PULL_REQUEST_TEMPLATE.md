<!--
Thanks for opening a Pull Request.

PR title format for this repository:
- SPSSiteInventory: Short description
- BREAKING CHANGE: SPSSiteInventory: Short description
-->

#### Pull Request (PR) description

<!--
Describe what changed and why.
Include user impact when applicable.
-->

#### This Pull Request (PR) fixes the following issues

<!--
Example:
- Fixes #30
If no issue is fixed, write: None.
-->

#### Validation summary

<!--
Paste command outputs or links to CI jobs when possible.
-->

- Pester:
- PSScriptAnalyzer:
- Windows PowerShell 5.1 / pwsh CI:

#### Task list

- [ ] Added an entry under **Unreleased** in `CHANGELOG.md` describing the change and impact (and issue reference when applicable).
- [ ] Added/updated relevant tests under `tests/`, or documented why tests are not needed.
- [ ] Ran `Invoke-Pester -Path .\tests` (or a targeted subset with rationale).
- [ ] Ran `Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` and addressed issues.
- [ ] Updated wiki/docs (`wiki/`) when behavior, parameters, or configuration changed.
- [ ] Confirmed changed scripts remain compatible with Windows PowerShell 5.1.
