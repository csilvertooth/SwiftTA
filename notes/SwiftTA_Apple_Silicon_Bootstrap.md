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
