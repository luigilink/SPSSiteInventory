# Release Process

SPSSiteInventory follows [Semantic Versioning](https://semver.org/) and a tag-driven
release flow handled by GitHub Actions.

## Versioning

- **MAJOR** — breaking changes to the settings schema, function signatures or output format.
- **MINOR** — new collectors, signals or capabilities, backward compatible.
- **PATCH** — bug fixes and documentation.

The single source of truth for the version is `ModuleVersion` in
`src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1`.

## Steps

1. Ensure `main` is green (Pester + PSScriptAnalyzer).
2. Bump `ModuleVersion` in the module manifest.
3. Move the relevant `CHANGELOG.md` entries from **Unreleased** into a new version section with the date.
4. Update `RELEASE-NOTES.md` with the highlights of the release (this file becomes the GitHub Release body).
5. Commit, open a PR, and merge to `main`.
6. Tag the merge commit `vX.Y.Z` and push the tag:

   ```powershell
   git tag v0.1.0
   git push origin v0.1.0
   ```

## What the automation does

- **Pester workflow** (`pester.yml`) — runs the Pester suite (under both PowerShell 7 and Windows PowerShell 5.1) and PSScriptAnalyzer on every pull request to `main`.
- **Release workflow** (`release.yml`) — on a `v*` tag, zips the contents of `src/` (so the archive extracts straight to `config/`, `Modules/` and the scripts) and publishes a GitHub Release using `RELEASE-NOTES.md` as the body.
- **Wiki workflow** (`wiki.yml`) — on push to `main` that touches `wiki/**`, syncs the `wiki/` folder to the GitHub wiki.
