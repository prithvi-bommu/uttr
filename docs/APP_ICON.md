# App Icon

How the Uttr app icon works and how to change it.

## Where the icon lives

| Path | What it is |
|------|------------|
| `Design/AppIcon/uttr-icon-source.png` | The single 1024x1024 source image. This is the only file you edit/replace. |
| `Uttr/Resources/Assets.xcassets/AppIcon.appiconset/` | The 10 generated PNGs (16pt-512pt @1x/@2x) + `Contents.json` that Xcode bundles into the app. **Never edit these by hand** -- they are regenerated from the source image. |
| `Scripts/make-appicon.sh` | Generator: source PNG -> all 10 appiconset sizes + `Contents.json`. |
| `Scripts/render-placeholder-icon.swift` | Renders the current placeholder artwork (indigo gradient + white mic). Only needed if you want to re-render the placeholder. |

The icon shown on the DMG, in Finder, and in Cmd-Tab all come from the app
bundle's `AppIcon` asset -- it is baked in at build time. macOS does not
support switching the app icon at runtime, so changing it always means
regenerate + rebuild.

## How to change the app icon

1. Get a **square PNG, 1024x1024 or larger** (transparency supported).
   Design tip: keep the artwork inside a centered ~824x824 rounded rect and
   leave the rest transparent, so macOS renders the standard margin/shadow
   like other app icons.

2. Regenerate the icon set:

   ```bash
   cd /path/to/uttr
   ./Scripts/make-appicon.sh path/to/your-new-icon.png
   ```

   Or replace `Design/AppIcon/uttr-icon-source.png` with your new image and
   run the script with no arguments (it defaults to that path). Keeping the
   source image committed at that path is recommended so the icon can always
   be regenerated.

3. Rebuild the app (`./Scripts/release-dmg.sh` for a DMG, or a normal Xcode
   build). ⚠️ Remember: every rebuild of the ad-hoc-signed app wipes the TCC
   permission grants (Input Monitoring / Accessibility) on the installed copy.

4. If Finder still shows the old icon after installing, the icon cache is
   stale. Renaming/moving the app or a logout usually refreshes it; the
   nuclear option is `killall Finder`.

## Keeping multiple icons around

To switch between several images, keep each candidate in `Design/AppIcon/`
(e.g. `Design/AppIcon/candidate-blue.png`, `Design/AppIcon/candidate-wave.png`)
and point the script at whichever one you want active:

```bash
./Scripts/make-appicon.sh Design/AppIcon/candidate-wave.png
```

The last one you ran the script with is the one that ships in the next build.

## Menu bar icon (unrelated)

The menu bar icon is separate -- it's an SF Symbol chosen at runtime in
`Uttr/Features/MenuBar/MenuBarLabel.swift` and is not affected by any of the
above.
