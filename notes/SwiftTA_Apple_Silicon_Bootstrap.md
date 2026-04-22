# SwiftTA Apple Silicon Bootstrap Notes

Date: 2026-04-21
Branch: `chore/swiftta-apple-silicon-bootstrap`
Host: macOS 26.3.1 / Xcode 26.4.1, Apple silicon.

## Build status

| Target   | Scheme   | Destination                      | Result |
|----------|----------|----------------------------------|--------|
| HPIView  | HPIView  | `platform=macOS,arch=arm64`      | ✅ BUILD SUCCEEDED |
| TAassets | TAassets | `platform=macOS,arch=arm64`      | ✅ BUILD SUCCEEDED |

Binaries: `build/DerivedData/Build/Products/Debug/HPIView.app`, `.../TAassets.app` — native arm64 Mach-O.

Command used:
```
xcodebuild -workspace SwiftTA.xcworkspace -scheme <HPIView|TAassets> \
           -destination 'platform=macOS,arch=arm64' -configuration Debug \
           -derivedDataPath build/DerivedData build
```

## Environment fixes (one-time, outside the repo)

1. **Xcode plug-in load failure** — `IDESimulatorFoundation` failed to load because the system copy of `DVTDownloads.framework` was older than Xcode 26.4's expected symbol set. Resolved by updating Xcode to 26.4.1 and running `sudo xcodebuild -runFirstLaunch`.
2. **Metal toolchain missing** — Xcode 26 ships `metal` as a downloadable component. Installed with `xcodebuild -downloadComponent MetalToolchain` (no sudo).
3. **CoreSimulator mismatch warning** — `CoreSimulator is out of date (1051.49.0 vs 1051.50.0)` is printed on every invocation. It only disables iOS Simulator, so macOS builds are unaffected. Will resolve on the next macOS point update.

## Repo fixes (committed on the bootstrap branch)

1. **`SwiftTA-Core/Sources/SwiftTA-Core/TdfParser.swift`** — five call sites of `data.withUnsafeBytes { $0[i] }` became ambiguous under current Swift. Closures now explicitly take `(UnsafeRawBufferPointer)` and reference `bytes[i]`. Behavior unchanged.
2. **`HPIView/HPIView.xcodeproj/project.pbxproj`** — `MACOSX_DEPLOYMENT_TARGET` bumped `10.12 → 10.13` in both configurations. Xcode 26 refuses to build below 10.13.
3. **`TAassets/TAassets.xcodeproj/project.pbxproj`** — same bump, four locations (app + tests × Debug/Release).
4. **`HPIView/HPIView/HpiDocument.swift`** — `@IBAction func extractAll` was a stub (opened nothing). Implemented it to enumerate `hpiDocument.filesystem.root.items`, open a directory chooser sheet, and delegate to the existing `extractItems(_:to:)` recursion.

Remaining non-blocking warnings (left as-is to keep the diff minimal):
- `SwiftTA-Core/.../TextureAtlasPacker.swift:47,50` — tuple label mismatch (`offset`/`element` vs `index`/`texture`) will become an error in a future Swift language mode.
- `SwiftTA-Core/.../GameRenderer.swift:26` — `class` keyword on a protocol is deprecated (use `AnyObject`).
- HPIView / TAassets projects still carry a few pbxproj IDs referencing the old deployment target docs (build output is clean).

## Archive support audit (deliverable 4)

Entry points live in `SwiftTA-Core/Sources/SwiftTA-Core/hpi.swift`:

- `HpiItem.loadFromArchive(contentsOf:)` parses any HPI-format container and returns a `HpiItem.Directory` tree. Format is detected from the header marker + version field:
  - `HpiFormat.HpiVersion.ta` — Total Annihilation HPI (extended header path).
  - `HpiFormat.HpiVersion.tak` — Kingdoms HPI.
  - `HpiFormat.HpiVersion.saveGame` — present in the enum, no loader branch.
- `HpiItem.extract(file:fromHPI:)` returns a single file's bytes, handling encryption and optional per-chunk compression.

File-extension wiring in `SwiftTA-Core/Sources/SwiftTA-Core/Filesystem.swift`:

```swift
public static let weightedArchiveExtensions = ["ufo", "gp3", "ccx", "gpf", "hpi"]
```

`FileSystem(mergingHpisIn:)` (used by TAassets) walks `~/Documents/Total Annihilation`, filters by those extensions, and merges every matched archive into one virtual filesystem. Extension is only used as a filter — all files flow through the same `HpiItem.loadFromArchive` code path, which is why UFO/CCX/GP3/GPF all browse correctly as long as their binary format is HPI.

HPIView uses `FileSystem(hpi:)` (single archive per document). Its `Info.plist` registers UTIs for `com.cavedog.hpi` only; to accept UFO/CCX directly by double-click, additional UTIs would need to be declared. Open-via-menu already works for any file thanks to `NSDocument`'s generic reader.

No parser changes were required — archive browsing works as-is.

## Extraction features in HPIView (deliverable 5)

Implemented via `HPIView/HPIView/HpiDocument.swift`:

- **Extract selected file(s)** — existing `@IBAction func extract(sender:)` ([HpiDocument.swift:405](HPIView/HPIView/HpiDocument.swift#L405)). Iterates the Finder selection, maps each to `HpiItem`, and writes it next to the chosen directory via `HpiItem.extract(file:fromHPI:)`.
- **Extract selected folder** — same action; when a directory is selected, `extractItems(_:to:)` recurses, creating subdirectories as it goes ([HpiDocument.swift:435-463](HPIView/HPIView/HpiDocument.swift#L435-L463)).
- **Extract entire archive** — `@IBAction func extractAll(sender:)` ([HpiDocument.swift:427](HPIView/HPIView/HpiDocument.swift#L427)). Was a stub before this branch; now enumerates `hpiDocument.filesystem.root.items`, shows an `NSOpenPanel` directory-chooser sheet, and reuses `extractItems(_:to:)`.

Menu wiring already exists in `HPIView/HPIView/Base.lproj/MainMenu.xib` (`extractWithSender:` and `extractAllWithSender:` first-responder actions). No XIB changes needed.

Gaps / potential follow-ups (not implemented — out of scope for this pass):
- No progress UI for large archives.
- Errors are `print`-logged; no user-facing dialog.
- `validateMenuItem` only enables `extract` when something is selected — `extractAll` is always enabled; fine, but consider disabling when the archive is empty.
- TAassets has no extraction UI; its filesystem is merged across many archives, so per-item extract would need to carry `archiveURL` (already present on `FileSystem.File`) into the action.

## 3DO / model viewer extension points (deliverable 6)

### Parsing

- `SwiftTA-Core/Sources/SwiftTA-Core/UnitModel.swift`
  - Public struct `UnitModel` — opens a `.3DO` file via `UnitModel(contentsOf:)`.
  - Core parse loop: `UnitModel.loadModel(from: UnsafeRawBufferPointer)` walks a queue of piece offsets, reading `TA_3DO_OBJECT`, `TA_3DO_VERTEX`, and `TA_3DO_PRIMITIVE` C-structs (defined in `SwiftTA-Ctypes` via `module.modulemap`).
  - Piece hierarchy is built inline: each object's `offsetToChildObject` / `offsetToSiblingObject` drives the traversal; `ModelData.pieces` is a flat array; `nameLookup` maps piece name → index.
  - `UnitModel.PieceMap` computes parent chains (`mapParents`) — useful for animation evaluation and for exporting a hierarchical representation (e.g. glTF nodes).

### Textures / palette

- `SwiftTA-Core/Sources/SwiftTA-Core/ModelTexturePack.swift` — an index of available model textures across the merged filesystem. `UnitBrowserViewController` holds an instance (`textures`) and hands it to the renderer.
- `SwiftTA-Core/Sources/SwiftTA-Core/UnitTextureAtlas.swift` — packs the textures referenced by a specific model into a single atlas; each primitive carries UV rect keyed off the piece's texture name.
- `SwiftTA-Core/Sources/SwiftTA-Core/TextureAtlasPacker.swift` — the packing algorithm (currently emits two tuple-label warnings, see above).
- `SwiftTA-Core/Sources/SwiftTA-Core/Palette.swift` + `Palette+Files.swift` — 8-bit palette loading (`.PAL`) and RGBA resolution. `HPIView/HPIView/HpiDocument.swift` loads `PALETTE.PAL` from the bundle at preview time; for a proper 3DO inspector the palette should come from the selected side's palette in `SideData`.

### Rendering entry points

- TAassets: `TAassets/TAassets/UnitView.swift` delegates to `UnitView+Metal.swift` (macOS default) or `UnitView+Opengl.swift`. Renderer protocols in `UnitViewRenderer+Metal.swift` / `UnitViewRenderer+OpenglCore33.swift` / `UnitViewRenderer+OpenglLegacy.swift`.
- HPIView: `HPIView/HPIView/ModelView.swift` + `ModelView+Metal.swift` / `ModelView+Opengl.swift`, renderer in `ModelViewRenderer+Metal.swift`.
- The Metal pipeline lives in the `SwiftTA-Metal` Swift package; shaders in `HPIView/HPIView/*.metal` (ModelViewRenderer, TntViewRenderer variants). Metal toolchain download is required (see environment fix #2).

### Suggested shape for a dedicated 3DO inspector

If the goal is to evolve TAassets into a focused 3DO/asset inspector + exporter:

1. Re-use `UnitModel.loadModel` unchanged — it already produces the canonical piece tree.
2. Surface piece metadata (name, position, child count, primitive count) in an `NSOutlineView` keyed off `UnitModel.pieces` + `PieceMap.parents`.
3. Wrap the existing Metal renderer in a stand-alone `NSViewController` that takes a `UnitModel` + `ModelTexturePack`/`UnitTextureAtlas` + `Palette` (all already wired up in `UnitBrowser`/`UnitView`).
4. For export, walk `UnitModel.PieceMap` once to emit glTF nodes (one per piece, TRS from `TA_3DO_OBJECT` offsets), and one mesh per piece primitive set. Textures already land in an RGBA atlas via `UnitTextureAtlas` — that's glTF-friendly.
5. Animation (COB scripts) lives in `UnitScript*.swift` (`UnitScript.swift`, `UnitScript+VM.swift`, `UnitScript+Instructions.swift`, `UnitScript+CobDecompile.swift`). Piece transforms are driven at runtime by the VM — for glTF export, either bake to sampled animations or emit the raw bytecode as a side-car and evaluate later.

## Validate checklist

- [x] HPIView builds on current Apple silicon macOS
- [x] TAassets builds on current Apple silicon macOS
- [ ] Apps launch without immediate runtime failure — **not verified from CLI** (requires GUI interaction and a valid `~/Documents/Total Annihilation` directory for TAassets; HPIView only needs a `.hpi` file via Open).
- [x] Existing HPI/UFO browsing code audited
- [x] CCX/GP3/GPF support confirmed via shared `HpiItem.loadFromArchive` + `weightedArchiveExtensions`
- [x] Extraction locations identified; `extractAll` stub completed
- [x] 3DO / model viewer extension points identified

---

# Feature work

Everything below was added on top of the bootstrap. All features live on the `chore/swiftta-apple-silicon-bootstrap` branch.

## Piece hierarchy inspector

Both apps surface a live outline of model pieces beside the 3D preview.

- **TAassets**: [`PieceHierarchyView`](TAassets/TAassets/PieceHierarchyView.swift) sits below the unit's 3D preview inside `UnitDetailViewController`.
- **HPIView**: same view is embedded in a vertical `NSSplitView` with the 3D view; drag the divider to resize. [`HPIView/PieceHierarchyView.swift`](HPIView/HPIView/PieceHierarchyView.swift), layout in [`ModelView.swift`](HPIView/HPIView/ModelView.swift).

Columns:
- **Piece** — the string baked into each `TA_3DO_OBJECT` (`base`, `pad`, `nano`, `turret`, `flare`, `explode1`, …). Tree structure follows the 3DO parent/child pointers.
- **Prims / Verts / Children** — primitive count for the piece, total vertex indices across its primitives, number of direct children.
- **Script Refs** — each COB module that references this piece plus the set of opcodes used (`Create[dontShade]`, `Activate[turnPieceWithSpeed]`, …). Extracted statically by [`UnitScript.pieceReferences()`](SwiftTA-Core/Sources/SwiftTA-Core/UnitScript+PieceReferences.swift).

Selecting a row tints the piece in gold inside the 3D view. Implemented by a new `highlightedPieceIndex` uniform and a flat interpolant in both renderers' shaders:
- TAassets: [`UnitViewRenderer+MetalShaders.metal`](TAassets/TAassets/UnitViewRenderer+MetalShaders.metal) + [`UnitViewRenderer+MetalShaderTypes.h`](TAassets/TAassets/UnitViewRenderer+MetalShaderTypes.h) (the uniform is already in a `pieces[40]` buffer, so the index is straightforward).
- HPIView: [`ModelViewRenderer+MetalShaders.metal`](HPIView/HPIView/ModelViewRenderer+MetalShaders.metal) + [`ModelViewRenderer+MetalShaderTypes.h`](HPIView/HPIView/ModelViewRenderer+MetalShaderTypes.h). Required adding an `int pieceIndex` attribute to `ModelMetalRenderer_ModelVertex`; [`ModelViewRenderer+Metal.swift`](HPIView/HPIView/ModelViewRenderer+Metal.swift) writes it in `append(_:_:_:…)`/`appendLine`.

## Camera controls

Same bindings in both apps, applied to either the unit view (TAassets) or 3DO preview (HPIView):

| Input | Effect |
|---|---|
| Two-finger / mouse scroll | Zoom |
| Trackpad pinch | Zoom |
| `=` / `+` | Zoom in by 1.25× |
| `-` | Zoom out by 1.25× |
| `0` | Reset zoom and camera rotation |
| Mouse drag (no modifier) | Yaw (Z) |
| Shift + drag | Pitch (X) — consumed via a new `rotateX` step in the view matrix |
| Option + drag | Roll (Y) — state exists; wiring trivial |

Zoom scales the orthographic scene width. Each app maintains its own base width: TAassets derives it from the unit's `footprint.width`; HPIView uses [`UnitModel.maxWorldExtent`](SwiftTA-Core/Sources/SwiftTA-Core/UnitModel+Bounds.swift) so large buildings fit on load. `viewportChanged` re-fits on window resize.

## Playback controls (TAassets)

[`PlaybackControlsView`](TAassets/TAassets/PlaybackControlsView.swift) sits as a thin toolbar between the 3D preview and the piece outline.

- **Pause / Play** — toggles `viewState.playbackSpeed` between 0 and the last nonzero speed. `UnitViewController.updateAnimatingState` short-circuits script execution while paused.
- **Step** — pauses, then calls `stepOnce(by:)` to advance exactly 1/30 s of script time. Useful for inching through a build yard opening.
- **Speed slider (0×–2×)** — scales deltaTime each frame.
- **Run script…** — pull-down listing every module in the unit's COB (`Create`, `Activate`, `QueryPrimary`, etc.). Selecting one invokes `scriptContext.startScript(name)` so building internals can be observed on demand.

## Mod support

[`FileSystem`](SwiftTA-Core/Sources/SwiftTA-Core/Filesystem.swift) gained a `modDirectory:` parameter. When set, mod archives overlay the base with `overwrite: true`, so mod files replace vanilla when names collide and mod-only files are additive. `weightedArchiveExtensions` order (`ufo, gp3, ccx, gpf, hpi`) controls the load order inside each directory so later archives win.

### Mods menu

Dynamic menu in the menubar (installed from [`AppDelegate`](TAassets/TAassets/AppDelegate.swift)). Items populate lazily from `<baseURL>/mods/*/` at `menuWillOpen`. First item reads `Base only: <folder>` to reflect the actual base, not a generic "vanilla" label. The action routes through `AppDelegate.activateModFromMenu(_:)` → `TaassetsDocument.activateMod(_:)` so dispatch is reliable regardless of first-responder state.

### Mod folder auto-detect

[`TaassetsDocument.read(from:)`](TAassets/TAassets/TaassetsDocument.swift) checks if the opened folder's parent is named `mods` or `mod`. If so, and the grandparent contains any recognized archive extension, it loads the grandparent as the base with the opened folder as the active mod. This means:
- `File → Open → ~/tafiles` → base only (same as before).
- `File → Open → ~/tafiles/mods/taesc` → `base: tafiles + mod: taesc` automatically, so the mod gets its textures and palettes from the vanilla base without the user stitching it together.

### Standalone-folder tolerances

For users who open a mod folder that has no vanilla parent:
- `gamedata/sidedata.tdf` is optional — missing file just logs and uses empty sides.
- [`UnitDetailViewController.resolvePalette`](TAassets/TAassets/UnitBrowser.swift) chains `texturePalette → standardTaPalette → Palette()` so the 3D view still paints something.
- [`Palette.init()`](SwiftTA-Core/Sources/SwiftTA-Core/Palette.swift) now allocates 256 entries instead of 255 (a latent off-by-one that only showed up once the fallback was exercised).

### Unit discovery

[`UnitBrowserViewController.viewDidLoad`](TAassets/TAassets/UnitBrowser.swift) walks the entire merged filesystem for `*.fbi` (not just `units/`). TAESC-family archives store their content in `unitsE/` alongside the vanilla `units/`; the broader walk catches them. Duplicates are deduped by lowercased base name so overridden vanilla units appear once. Debug prints at load time expose the root entries and per-directory FBI counts so mod troubleshooting is visible.

[`UnitBrowserViewController.buildpic(for:)`](TAassets/TAassets/UnitBrowser.swift) iterates every root directory whose name starts with `unitpic` (covering `unitpics/`, `unitpicsE/`, `unitpicE/`) and tries PCX, BMP, PNG, JPG, JPEG, TGA before falling back to `anims/buildpic/*.{jpg,jpeg,png,bmp}`.

### COB divide-by-zero hardening

[`UnitScript+Instructions.swift`](SwiftTA-Core/Sources/SwiftTA-Core/UnitScript+Instructions.swift) — the `.divide` opcode used Swift's `/` which traps on division by zero. Some mod-shipped COB scripts (confirmed in TAESC) hit this when the VM evaluates side effects on large buildings. Replaced with a guarded closure that returns 0 when `rhs == 0`.

## Gaps / future work

- HPIView doesn't have mod awareness; it's still a single-archive browser. Probably fine since the app's job is file introspection, not mod switching.
- The OpenGL renderers do not apply the new highlight/pitch; TAassets' default Metal path covers both, and macOS 26 deprecates Apple's OpenGL anyway.
- The `unitsE`, `gamedatE`, `guiE` duplicate root directories from the TAESC archives are still not understood — they look like HPI directory-name parsing corruption rather than intentional English-locale variants. The broader unit/pic scans work around it, but the HPI parser may still be reading one byte past the null terminator in some cases.
- No per-unit texture variant handling for team colors. Units render with side 1's palette only.
- Extraction UI only exists in HPIView. TAassets could carry its own since `FileSystem.File.archiveURL` already tells it which container each file came from.

---

# TAassets UX work

Collected on branch `chore/taassets-ux` after the initial bootstrap was merged to `main`. Covers browser chrome, map viewer upgrades, mod-unit discovery, a working weapons tab, and several shader fixes to support mod maps.

## Browser chrome

- **Detail pane layout** ([TAassets/TAassets/UnitBrowser.swift](TAassets/TAassets/UnitBrowser.swift), [TAassets/TAassets/MapBrowser.swift](TAassets/TAassets/MapBrowser.swift)) — the old 62% golden-ratio content box with a centered 18-pt title has been replaced with a compact header strip. Map pane shows `mapname · planet · N players · wind lo-hi · tidal · gravity` from the OTA. Unit pane shows `objectName · title · description · side · tedclass · footprint · speed`. The 3D or map content fills the remaining pane.
- **Autoresizing fix** ([TAassets/TAassets/UnitBrowser.swift](TAassets/TAassets/UnitBrowser.swift), [TAassets/TAassets/MapBrowser.swift](TAassets/TAassets/MapBrowser.swift)) — the detail controller's view was set to `[.width, .width]` in both browsers, so the detail pane never grew vertically with the window. Fixed to `[.width, .height]`.
- **Sidebar icons** ([TAassets/TAassets/TaassetsDocument.swift](TAassets/TAassets/TaassetsDocument.swift)) — swapped the stock AppKit images for SF Symbols on macOS 11+: `cube.fill` (Units), `scope` (Weapons), `map.fill` (Maps), `folder.fill` (Files). Falls back to the original images on older systems.
- **Sidebar spacing** ([TAassets/TAassets/TaassetsDocument.swift](TAassets/TAassets/TaassetsDocument.swift)) — the Units icon was clipping under the red/yellow/green window buttons; added 28-pt top edge insets on the sidebar stack view.
- **Window sizing & autosave** ([TAassets/TAassets/TaassetsDocument.swift](TAassets/TAassets/TaassetsDocument.swift)) — documents now open at ~70% of screen width / 80% height (capped 1600×1100, floored 1100×750) and persist the frame under `TaassetsMainWindow` so future launches restore the last size and position. Minimum size 900×600 so the browser chrome always fits.
- **Search fields** ([TAassets/TAassets/UnitBrowser.swift](TAassets/TAassets/UnitBrowser.swift), [TAassets/TAassets/MapBrowser.swift](TAassets/TAassets/MapBrowser.swift), [TAassets/TAassets/WeaponsBrowser.swift](TAassets/TAassets/WeaponsBrowser.swift)) — added an `NSSearchField` above the Units, Maps, and Weapons lists. Filters live. Units match on name/title/description/3DO object name; maps match on base name; weapons match on key/name/weapontype/source file.

## Map viewer

- **Auto-fit on load** ([TAassets/TAassets/MapView+Metal.swift](TAassets/TAassets/MapView+Metal.swift)) — `MetalMapView.zoomToFit(resolution:)` sets `NSScrollView.magnification` so the full map fits the current viewport on open (previously always 1:1 which made 16k-wide maps look like an opaque tile). `NSScrollView.allowsMagnification` is already on, so pinch/scroll zoom work throughout.
- **Viewport sync every frame** ([TAassets/TAassets/MapView+Metal.swift](TAassets/TAassets/MapView+Metal.swift)) — `draw(in:)` now refreshes `viewState.viewport` from the current clip-view bounds each frame. The bounds-changed notification was occasionally dropped around a map reload, so the second map would stop redrawing while the scrollView's markers kept scrolling. Belt-and-suspenders fix.
- **Start-position markers** ([TAassets/TAassets/MapView+Metal.swift](TAassets/TAassets/MapView+Metal.swift)) — the scroll view's (previously invisible) document view is now a `MapOverlayView` that paints numbered gold/orange circles at every commander start pulled from `MapInfo.schema[0].startPositions`. Flipped coordinate system so positions match OTA directly. Scrolls and zooms with the map.
- **Map size ceiling** ([HPIView/HPIView/TntViewRenderer+MetalDynamicTiles.swift](HPIView/HPIView/TntViewRenderer+MetalDynamicTiles.swift)) — `maximumDisplaySize` bumped from `4096×4096` to `8192×8192` (16×16 screen-tile grid, ~256 MB VRAM) so maps render cleanly on 4K-class Retina displays. `computeTileGrid` clamps the visible grid to `maximumGridSize` so a viewport larger than the pool no longer overflows the pre-sized index/slice buffers (previously produced tile fallback artifacts).
- **Past-edge discard** ([HPIView/HPIView/TntViewRenderer+MetalShaders.metal](HPIView/HPIView/TntViewRenderer+MetalShaders.metal), [HPIView/HPIView/TntViewRenderer+MetalShaderTypes.h](HPIView/HPIView/TntViewRenderer+MetalShaderTypes.h)) — map fragment shaders discard pixels outside the map's pixel area. Single-quad checks texCoord against `[0,1]`; tile shader compares world position to a new `mapSize` uniform. Samplers also switched to `clamp_to_zero`. No more vertical smearing of the last terrain column when the viewport or a partial edge tile extends past the map.
- **Missing-features warning** ([TAassets/TAassets/MapView+Metal.swift](TAassets/TAassets/MapView+Metal.swift)) — feature loading errors are no longer swallowed by `try?`; the viewer now logs a clear note pointing at `TA_Features_2013.ccx` so users can tell when that archive is missing from the base.

## Mod support

- **Mod-folder auto-detect** ([TAassets/TAassets/TaassetsDocument.swift](TAassets/TAassets/TaassetsDocument.swift)) — File → Open on a folder whose parent is named `mods` or `mod` and whose grandparent has TA archives now loads the grandparent as the base with the opened folder as the active mod. Opening `~/tafiles/mods/taesc` behaves the same as opening `~/tafiles` and choosing `taesc` from the Mods menu — the mod gets its textures and palettes from the vanilla base.
- **Menu routing** ([TAassets/TAassets/AppDelegate.swift](TAassets/TAassets/AppDelegate.swift)) — the Mods-menu action routes through `AppDelegate.activateModFromMenu(_:)` rather than targeting the NSDocument directly, so dispatch works regardless of first-responder state. The first menu entry reads `Base only: <folder>` instead of a generic label.
- **Recursive unit discovery** ([TAassets/TAassets/UnitBrowser.swift](TAassets/TAassets/UnitBrowser.swift)) — `UnitBrowserViewController.viewDidLoad` walks the entire merged filesystem for `*.fbi`, catching TAESC-style archives that stash unit definitions in `unitsE/` alongside `units/`. Deduped by lowercased base name so an overridden vanilla unit appears once. Debug prints expose root entries and per-directory FBI counts.
- **Generalized buildpic search** ([TAassets/TAassets/UnitBrowser.swift](TAassets/TAassets/UnitBrowser.swift)) — iterates every root directory whose name starts with `unitpic` and tries PCX, BMP, PNG, JPG/JPEG, TGA before falling back to `anims/buildpic/` JPG/PNG/BMP. Handles both vanilla and mod naming.

## Weapons browser ([TAassets/TAassets/WeaponsBrowser.swift](TAassets/TAassets/WeaponsBrowser.swift))

New tab wired to the Weapons sidebar button. Walks every top-level directory whose name starts with `weapon` (so `weaponsE/` and `weaponE/` from mod archives are picked up) and parses each `*.tdf` with `TdfParser`. Every block with at least one property is shown in a two-column table (name, range). Container blocks with only subobjects are descended into rather than listed. Selecting a weapon prints its key, source file, weapon type, range, damage table, and full property set in the detail pane. Search field narrows by key, name, weapon type, and source file.

## COB VM hardening ([SwiftTA-Core/Sources/SwiftTA-Core/UnitScript+Instructions.swift](SwiftTA-Core/Sources/SwiftTA-Core/UnitScript+Instructions.swift))

Some mod scripts (confirmed in TAESC) invoke the divide opcode with a zero right-hand side. Swift's `/` traps on integer division by zero and crashed the app the moment a unit was selected. Replaced the `.divide` entry in the opcode dispatch dictionary with a guarded closure that returns `0` on zero divisor so the VM keeps running.
