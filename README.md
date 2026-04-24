# SwiftTA — Asset Inspectors for Total Annihilation

Two macOS apps for exploring Total Annihilation's game data. Point them at a folder of TA archives and browse every unit, map, weapon, and file inside:

- **TAassets** — unified asset browser with live 3D model previews, COB script playback, a piece hierarchy inspector, map height / passability overlays, and mod support.
- **HPIView** — a tree explorer for individual `.hpi` / `.ufo` / `.ccx` / `.gp3` / `.gpf` archives with per-file preview and bulk extraction.
- **AEX-MapEditor** *(early access)* — a bare-bones heightmap editor for loose `.tnt` files. Current build supports height raise/lower brushing with undo/redo and saves back to the original format. Tile painting, feature placement, and OTA metadata editing are on the roadmap.

Both apps run natively on Apple silicon (and Intel Macs) on macOS 10.13+, read every TA-family archive format, handle TAESC-style mods, and do not require a copy of Xcode to use.

## Download

Grab the latest build from the [Releases page](https://github.com/csilvertooth/SwiftTA/releases):

- **`TAassets-macOS.zip`** — the full asset browser
- **`HPIView-macOS.zip`** — archive viewer only
- **`AEX-MapEditor-macOS.zip`** — early-access heightmap editor

The `Latest main` prerelease is refreshed on every push to `main`. Versioned releases (e.g. `v0.1.0`) are posted when they're cut.

### First launch

The apps are **ad-hoc signed** (no paid Apple Developer certificate), so Gatekeeper will block the first launch. To open them:

1. Unzip the download and move the `.app` into `/Applications` or `~/Applications`.
2. In Finder, **right-click → Open** (or Control-click → Open).
3. Confirm the "unidentified developer" prompt once. macOS remembers the choice.

After that, launch them like any other app.

## What files do I need?

You need a copy of the **original Total Annihilation** game files. The apps don't ship with any game content — they just read whatever TA archives you point them at.

A working TA files directory typically contains:

| File(s) | Source | Role |
|---|---|---|
| `ccdata.ccx`, `ccmaps.ccx`, `ccmiss.ccx` | Cavedog CD-ROM or digital copy | Core game data (units, tiles, scripts) |
| `rev31.gp3` | TA patch 3.1 | Retail unit/engine patch |
| `btdata.ccx` *(optional)* | Battle Tactics expansion | Expansion units |
| `cc*.hpi`, `ta_features_2013.ccx` *(optional)* | Community | Additional features, maps, and the definitive feature pack |
| `mods/<ModName>/` *(optional)* | Mod author | Drop a mod folder here — more on mods below |

Any folder containing these files will work — the apps don't require a specific install location. A common layout:

```
~/tafiles/
  ccdata.ccx
  ccmaps.ccx
  ccmiss.ccx
  rev31.gp3
  TA_Features_2013.ccx
  mods/
    taesc/
      TAESC.gp3
      T2ESC.ufo
      ...
```

If `TA_Features_2013.ccx` is missing, maps still render but some features (trees, rocks, wrecks) will not. TAassets logs a clear warning pointing at the missing feature pack.

## Using TAassets

1. Launch `TAassets.app`.
2. `File → Open…` and pick your TA files folder (e.g. `~/tafiles`).
3. The sidebar has four browsers: **Units**, **Weapons**, **Maps**, **Files**.

### Units browser

- Filter the list with the search field at the top.
- Click a unit → 3D model renders on the right, textured and lit.
- **Camera**: drag to rotate heading, shift-drag to pitch, scroll / pinch to zoom, `=` / `-` / `0` to zoom-in / zoom-out / reset.
- **Piece hierarchy pane** on the right shows every 3DO piece with its primitive / vertex / child counts and every COB module that manipulates it. Click a piece to tint it gold in the 3D view.
- **COB playback** at the bottom: Pause, Step, 0× – 4× speed slider.
- **"Run script…" menu** fires any module in the unit's COB (`Create`, `Activate`, `QueryPrimary`, `StartMoving`, `StopMoving`, etc.).
- Press **`d`** while the 3D view is focused to dump every piece's current offset / turn / move / world position to the console — useful for diagnosing IK.
- On load, the viewer freezes background threads after `Create` returns so a walker unit holds its IK pose rather than running a forever-gait over an empty scene. Fire `StartMoving` manually if you want to see the gait.

### Maps browser

- Filter the list and click any map.
- The header strip carries map info (planet, player count, wind, tidal, gravity).
- Numbered markers show OTA start positions.
- **Overlay toggle** (None / Heights / Passability):
  - **Heights** tints each 16×16 cell from deep-blue (below sea level) through greens and yellows to white on high peaks.
  - **Passability** shows cells colored by slope — red where the max elevation delta to any neighbor exceeds the slope threshold, blue under sea level, orange where a feature occupies the cell, green-to-yellow for passable terrain. A slider lets you tune the threshold to match different movement classes.

### Weapons browser

- Walks every `weapon*/` directory and parses every `.tdf` recursively. Every weapon block from every mod's weapon tables is listed.
- Click a weapon to see its key, source file, type, range, damage table, and raw properties.

### Files browser

- The full merged virtual filesystem — every archive's contents layered into one tree, exactly how TA itself sees the files.
- Useful when you want to find where a specific file lives across multiple archives.

### Using mods

TAassets automatically discovers mod folders under `<base>/mods/`:

- A dynamic **Mods** menu appears in the menu bar listing every available mod.
- Selecting a mod rebuilds the merged filesystem with that mod layered on top of the vanilla base.
- You can also open a mod folder directly (e.g. `~/tafiles/mods/taesc`) — TAassets will auto-pair it with the vanilla base it lives next to.
- TAESC-style mods with nested `unitsE/`, `weaponE/`, and `unitpicE/` directories are discovered recursively.

## Using HPIView

1. Launch `HPIView.app`.
2. `File → Open…` and pick any `.hpi`, `.ufo`, `.ccx`, `.gp3`, or `.gpf` archive.
3. The left pane shows the archive's directory tree. The right pane previews whichever file you click.
4. Drill into `objects3d/` and click a `.3DO` to see the piece hierarchy plus references from the unit's COB script. Resize the split divider to adjust the outline width.
5. **Extract from the File menu**: a single file, the current selection, or the entire archive to a chosen folder.

## Build from source

If you'd rather build the apps yourself:

```
git clone https://github.com/csilvertooth/SwiftTA.git
cd SwiftTA
xcodebuild -workspace SwiftTA.xcworkspace -scheme TAassets \
           -destination 'platform=macOS' \
           -configuration Release \
           CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
```

Replace `-scheme TAassets` with `-scheme HPIView` for the other app. Built bundles land under `build/DerivedData/Build/Products/Release/`.

You'll need Xcode 26+ on macOS 26+ (older combos should also work but aren't tested).

## About this fork

This repository is a fork of the original [loganjones/SwiftTA](https://github.com/loganjones/SwiftTA) focused on modernizing the TAassets / HPIView tooling. See [docs/FORK_NOTES.md](docs/FORK_NOTES.md) for the summary of additions, and [notes/SwiftTA_Apple_Silicon_Bootstrap.md](notes/SwiftTA_Apple_Silicon_Bootstrap.md) for the file-by-file technical write-up. The original upstream README (Swift 4.2 / Ubuntu 16.04 era game-client instructions) is preserved at [docs/ORIGINAL_README.md](docs/ORIGINAL_README.md).

## Credits

- [Logan Jones](https://github.com/loganjones) — original SwiftTA project, HPIView, TAassets.
- Cavedog Entertainment — Total Annihilation (1997).
