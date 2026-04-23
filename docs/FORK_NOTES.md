# Fork notes

This repository is a fork of [loganjones/SwiftTA](https://github.com/loganjones/SwiftTA) that keeps the original Swift game-engine experiment intact and adds a set of asset-inspection and COB-scripting improvements focused on **TAassets** and **HPIView** running on current Apple silicon / Xcode / macOS. The deep technical write-up (file-by-file fixes, script-VM changes, renderer patches) lives in [notes/SwiftTA_Apple_Silicon_Bootstrap.md](../notes/SwiftTA_Apple_Silicon_Bootstrap.md).

The original upstream README (Swift 4.2 / Ubuntu 16.04 era game-client instructions) is preserved at [ORIGINAL_README.md](ORIGINAL_README.md).

## Highlights added in this fork

- **Builds cleanly on Xcode 26 / macOS 26 / Apple silicon** — Swift disambiguation fixes, deployment-target bump, Metal toolchain check, palette off-by-one fix.
- **Piece hierarchy inspector** (both apps) — outline of every 3DO piece with primitive / vertex / child counts. Selecting a piece tints it gold in the 3D view. `Script Refs` column lists every COB module that manipulates each piece, extracted statically from the bytecode.
- **COB playback controls** (TAassets) — pause / step / 0×–4× speed slider, plus a "Run script…" pull-down for every module in the unit's COB.
- **Walker-IK fidelity** — rotation matrix composes yaw-outermost so child pitch axes stay horizontal, `PIECE_XZ / PIECE_Y` return native TA integer units, `XZ_ATAN` is unsigned (so `LegGroups` quadrant checks work), `GROUND_HEIGHT` is stubbed stably so `PositionLegs` converges.
- **Freeze-after-Create viewer mode** — on unit load, after `Create` returns the viewer kills the background threads it spawned so the unit holds its IK pose instead of running a forever-gait over an empty scene. Manual scripts from the "Run script…" menu still run.
- **Camera controls** — scroll / pinch zoom, shift-drag pitch, `=` / `-` / `0` keys. Auto-fits the model on load and on window resize.
- **Mod-aware filesystem** — a dynamic `Mods` menu lists every mod folder under `<base>/mods/` and rebuilds the merged filesystem on selection. Opening a mod folder directly (e.g. `~/tafiles/mods/taesc`) is auto-paired with the vanilla base it lives under. TAESC-style mods with nested `unitsE/` and off-spec `unitpicE/` directories are discovered recursively.
- **Map browser overlays** — per-cell **Heights** tinting and a **Passability** heatmap (slope threshold adjustable, under-sea cells blue, feature-occupied cells orange) for lining up external engine passability logic against the actual TNT heightmap + sea level.
- **Map rendering** — auto-fits on load, pinch/scroll zoom, numbered start-position markers from the OTA schema, and edge-smear fixed via `clamp_to_zero` sampling plus a fragment-shader discard past the map's actual pixel size. Supports maps up to 8192 px on-screen.
- **Weapons browser** — walks every `weapon*/` directory, parses each `.tdf` recursively, and lists every weapon block with a searchable detail pane.
- **Searchable browsers** — live filter fields above the Units, Maps, and Weapons lists.
- **Browser chrome** — compact header strips; SF Symbols sidebar; window size / position persists across launches.
- **Tolerant standalone loading** — `gamedata/sidedata.tdf` is optional; palette lookup falls back through side → standard → neutral; missing `TA_Features_2013.ccx` is logged clearly.
- **HPIView extraction** — the `Extract All` menu item is implemented so you can dump the entire archive to a folder.
- **Script VM hardening** — COB divide-by-zero returns 0 rather than trapping, `Stack.pop(count:)` returns the correct number of elements, `wait-for-turn` / `wait-for-move` wake threads when the matching animation drains, multi-root 3DO trees all render (sibling subtrees no longer get dropped).
