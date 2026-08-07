# Release Runbook

## Code Signing (read first)

`Scripts/release-dmg.sh` auto-detects the signing identity, in priority order:

| Priority | Identity | When |
|---|---|---|
| 1 | `$UTTR_SIGN_IDENTITY` env var | Explicit override |
| 2 | `Developer ID Application: …` | **M7 onward** — picked up automatically once the cert is in the keychain |
| 3 | `Uttr Dev Signing` (self-signed) | Interim local builds — keeps TCC grants stable across rebuilds on the dev machine (ADR-010) |
| 4 | Ad-hoc (`-`) | Fallback — permission grants reset on every rebuild |

**Switching to Developer ID when it arrives (M7): install the certificate in
the keychain — that is the entire migration.** The next `release-dmg.sh` run
signs with it automatically. One-time cost after any identity switch: macOS
sees a "different app" once, so re-grant Mic / Input Monitoring /
Accessibility and re-apply the launch-at-login toggle a single time.

Recreating the self-signed cert on a new machine (ADR-010): create a
code-signing cert named `Uttr Dev Signing` via Keychain Access → Certificate
Assistant (or openssl with `-legacy` PKCS12 export), import into the login
keychain, then `security add-trusted-cert -p codeSign -k
~/Library/Keychains/login.keychain-db cert.pem`.

## Prerequisites (full external release, M7)

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
