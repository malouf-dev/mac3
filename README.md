# mac3

**GTA III, native on Apple Silicon.** A build that renders through
**Metal**, runs sharp at full **Retina** resolution, and turns on macOS **Game
Mode** automatically. One command turns your own copy of the original game —
Steam, retail disc, or files from an old PC — into a ready-to-play
`Grand Theft Auto III.app`. No administrator password needed.

This repository hosts the **download only** — there is no source code here.

> ⚠️ **This needs the original GTA III, not the Definitive Edition.** The
> Definitive Edition is a different, rebuilt game and will not work.

## Install

**You need:** an Apple Silicon Mac (M1 or newer) on macOS 15.7.9 or later, and
your own copy of the **original GTA III** — the classic 2001/2002 PC
release, *not* the Definitive Edition
([Steam](https://store.steampowered.com/app/12100/) works out of the box — you
never have to launch it).

1. Open **Terminal** (`Cmd+Space`, type `Terminal`, press Enter), paste this
   line and press Enter:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/gtamac/mac3/main/quick-install.sh | bash
   ```

   It finds your game files automatically (a Steam copy, or an already-installed
   app from an earlier run — including the previous mac3.app or re3.app) and
   puts **Grand Theft Auto III.app** in your Downloads folder — about a minute,
   the app is ~1.2 GB with the game inside.

2. When Finder opens, **drag Grand Theft Auto III into Applications** — or just
   double-click it to play right away.

**Using a non-Steam copy?** Add the path to the end of the command — a game
folder (the one with `models`, `data`, `audio`, …) or a GTA III `.app` that
contains the files (including Wineskin/Wine and CrossOver wrappers, such as the
`GTA 3.app` on a mounted "Grand Theft Auto 3" disc image) both work — again,
from the original game, not the Definitive Edition:

```sh
curl -fsSL https://raw.githubusercontent.com/gtamac/mac3/main/quick-install.sh | bash -s -- ~/Downloads/"Grand Theft Auto 3.app"
```

**Upgrading?** Run the same one-liner again — it reuses the game files from your
installed app.

Prefer a classic disk image? Add `--dmg` to get a drag-to-Applications
`Grand Theft Auto III.dmg` instead: `... | bash -s -- --dmg`.

## Direct downloads

| File | What it is |
|---|---|
| [`mac3-macos-arm64.tar.gz`](https://raw.githubusercontent.com/gtamac/mac3/main/mac3-macos-arm64.tar.gz) | the app with no game assets, for building your own bundle |
| [`mac3-macos-arm64.zip`](https://raw.githubusercontent.com/gtamac/mac3/main/mac3-macos-arm64.zip) | the same, zipped |
| [`quick-install.sh`](https://raw.githubusercontent.com/gtamac/mac3/main/quick-install.sh) | the installer the one-liner runs |
| [`signtool-arm64.tar.gz`](https://raw.githubusercontent.com/gtamac/mac3/main/signtool-arm64.tar.gz) | the bundled ad-hoc signer, so installing needs no Xcode |

## Legal

mac3 requires the files from your own legally purchased copy of the original
Grand Theft Auto III. No game assets are distributed here.

## What's new

**Latest update**

- **Metal ray tracing** (new in-game Graphics option, off by default): a
  ray-tracing pass on the Metal GPU traces real shadows through Liberty City —
  crisp sun shadows with volumetric light rays by day; at night, street lamps
  cast shadows and car headlights project a realistic low-beam pattern onto
  the road, each lamp with its own ray-traced shadow; explosions and muzzle
  flashes light up their surroundings and throw hard radial shadows day and
  night. Turn it on with the **METAL RAY TRACING** switch in the Graphics
  menu, right below the MetalFX preset — it's experimental and starts off.
- **The installed app is now `Grand Theft Auto III.app`, with the classic
  GTA III icon** — the name on disk, in the menu bar, and in the Dock all
  match the original game. mac3 stays the name of the project and the
  download repository. Upgrading with the one-liner carries everything over,
  and picks up the game files from an existing install under any of its past
  names (mac3.app, re3.app).
- The installer now accepts **CrossOver wrappers** — for example the
  `GTA 3.app` on a mounted "Grand Theft Auto 3" disc image — and pulls the
  streamed radio audio out of them too.

## The port

GTA III running natively on Apple Silicon, with the same treatment
[macVC](https://github.com/gtamac/macVC) gives Vice City.

**Rendering**

- Renders through Metal (via ANGLE) instead of Apple's deprecated OpenGL
- HDR: true extended-range highlights on XDR and HDR displays, on by default
  (Graphics → HDR)
- MetalFX upscaling with five presets — Quality and Balanced use the spatial
  scaler, Performance, Max and Ultra use the temporal one. Balanced by
  default; set it to Off for native resolution. Applied from the main menu,
  before you load a save.
- 4x MSAA by default, plus mipmapped, trilinear and anisotropically filtered
  textures
- Extended draw distance with the original fog, and vehicles that fade in with
  distance instead of popping into view
- All three islands stay loaded, so there is no pause crossing the bridges

**macOS**

- Opens in native fullscreen on the display you launched it from, at your
  screen's real Retina resolution
- Game Mode turns on automatically while it runs
- Settings and saves live in `~/Library/Application Support/mac3/`, safely
  outside the app
- Fixes the classic "mouse sometimes not detected" bug, and keeps the cursor
  inside the game in fullscreen menus
- Tells you when a new version is out, and can install it for you

**Installing**

- One command builds a ready-to-play `Grand Theft Auto III.app` from your own
  copy of the game
- Finds the Steam copy on its own, including the radio stations and mission
  dialogue that the Steam release stores away from the game files
- Needs no administrator password and no Xcode
