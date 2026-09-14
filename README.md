# mac3 — native GTA III in one portable macOS app

This fork is one user-facing `mac3.app`. On first launch its **mac3 Launcher**
window detects the legacy Steam wrapper when possible, or lets you choose/drop
in your owned `Grand Theft Auto III.app`. It imports the game data and streamed
audio once, then offers **Play**, **Check for Updates**, and **Rebuild** from
that same window.

Steam is only an asset source. The old Steam macOS wrapper is 32-bit Intel and
will not launch on current macOS; the native playable copy is separate.

This checkout contains a prebuilt engine, not the engine source code. It is
ad-hoc signed and not notarized. Read [`SECURITY-NOTES.md`](SECURITY-NOTES.md)
before distributing it.

## Requirements

- Apple Silicon Mac on macOS 15.7.9 or later
- Original GTA III, not Grand Theft Auto III: Definitive Edition
- A complete checkout containing `mac3-macos-arm64.tar.gz`

## Build mac3.app

```sh
./make-mac3-app.sh
```

Open `dist/mac3.app` from a writable folder. Before setup it contains only the
Launcher and verified engine archive; it never bundles anyone's licensed game
files.

On first launch, select **Use Detected Copy**, choose the original wrapper, or
drag the wrapper onto the window. A manually selected folder must be complete,
including `models/gta3.img` and `models/fonts.txd`; mac3 rejects partial
exports instead of building an app that cannot start. After setup, **Replace
Game Data…** lets you recover from a bad source without a separate manager.
mac3 embeds these private files inside
`mac3.app/Contents/Resources/Portable/`:

- `Playable/mac3.app` — an internal engine bundle, not a second app to open;
  it contains the single imported copy of GTA III data and audio; and
- `Distributions/` — verified engine archives retained for rebuilds.

mac3 re-signs its outer bundle after setup, rebuilds, and updates. Once setup
is complete, `mac3.app` contains the complete game and can be copied to another
writable location without Steam or a separate support folder.

## Updates and play

**Check for Updates** explicitly fetches this fork's
`DistributionManifest.json`. An explicit **Install** download is checked
against its SHA-256, cached inside mac3.app, and used to rebuild the internal
engine with the already-imported game files.

When you select **Play**, mac3 hides its Launcher window, Dock icon, and menu
bar while it runs the internal engine directly. When the game quits, the
Launcher returns. The Launcher and game use the same mac3 icon for continuity.

Do not use the original engine's Terminal updater. mac3 disables its legacy
version check and Terminal-installer command, then re-signs the internal
engine, so this fork remains the only update path.
