# Release Runbook

## Prerequisites

- Apple Developer ID Application certificate installed
- Notarization credentials stored in Keychain profile `uttr-notarize`
- Clean working tree on `main`
- All tests passing

## Steps

1. **Verify clean state**
   ```bash
   git status
   ./Scripts/test.sh
   ```

2. **Update version**
   - Set `MARKETING_VERSION` in Xcode project
   - Increment `CURRENT_PROJECT_VERSION`
   - Update `CHANGELOG.md`: move Unreleased items under new version heading

3. **Tag the release**
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```

4. **Archive**
   ```bash
   ./Scripts/archive.sh
   ```

5. **Notarize**
   ```bash
   ./Scripts/notarize.sh build/export/Uttr.app
   ```

6. **Create DMG**
   ```bash
   ./Scripts/make-dmg.sh build/export/Uttr.app 1.0.0
   ```

7. **Verify Gatekeeper**
   ```bash
   spctl --assess --type execute --verbose build/export/Uttr.app
   ```

8. **Publish GitHub Release**
   ```bash
   gh release create v1.0.0 build/Uttr-1.0.0.dmg \
       --title "Uttr v1.0.0" \
       --notes-file CHANGELOG.md
   ```

9. **Verify on clean machine**
   - Download DMG from GitHub Release
   - Drag to Applications
   - Launch and verify Gatekeeper does not block
   - Run basic dictation test
