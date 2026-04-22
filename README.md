# SwiftTA

> **Fork notes (Apple silicon + mod browsing):** This branch of the original [loganjones/SwiftTA](https://github.com/loganjones/SwiftTA) focuses on making **TAassets** and **HPIView** useful asset inspectors on current Xcode / macOS with Apple silicon, and extends TAassets with a piece-level 3DO inspector, COB playback controls, and a mod-aware filesystem loader. Full write-up with code paths and troubleshooting is in [notes/SwiftTA_Apple_Silicon_Bootstrap.md](notes/SwiftTA_Apple_Silicon_Bootstrap.md).
>
> **What's new in this fork**
> - **Builds on Xcode 26 / macOS 26 / Apple silicon** — Swift disambiguation fixes, deployment target bump, Metal toolchain check, palette off-by-one fix.
> - **Piece hierarchy inspector** (both apps) — outline of every 3DO piece with primitive / vertex / child counts. Selecting a piece tints it gold in the 3D view (new Metal uniform + flat piece-index interpolant). `Script Refs` column lists every COB module that manipulates each piece, extracted statically from the bytecode.
> - **COB playback controls** (TAassets) — pause / step / 0×–2× speed slider, plus a "Run script…" pull-down for every module in the unit's COB so you can trigger `Activate`, `QueryPrimary`, etc. on demand and watch building internals animate piece by piece.
> - **Camera controls** — scroll / pinch zoom, shift-drag pitch, `=` / `-` / `0` keys. Auto-fits the model on load so large buildings don't open zoomed past the viewport; re-fits on window resize.
> - **Mod-aware filesystem** — a dynamic `Mods` menu lists every mod folder under `<base>/mods/` and rebuilds the merged filesystem on selection. Opening a mod folder directly (e.g. `~/tafiles/mods/taesc`) is auto-paired with the vanilla base it lives under. TAESC-style mods with nested `unitsE/` and off-spec `unitpicE/` directories are discovered recursively.
> - **Map viewer** — auto-fits the map to the viewport on load, pinch/scroll zoom, numbered start-position markers pulled from the OTA schema, and edge-smear fixed via `clamp_to_zero` sampling plus a fragment-shader discard past the map's actual pixel size. Supports maps up to 8192 px in the on-screen render budget.
> - **Weapons browser** — walks every `weapon*/` directory, parses each `.tdf` recursively, and lists every weapon block with a searchable detail pane (key, source file, weapon type, range, damage table, raw properties).
> - **Searchable browsers** — live filter fields above the Units, Maps, and Weapons lists.
> - **Browser chrome** — compact header strips carry unit/map details instead of centered oversized titles; the sidebar uses SF Symbols (cube, scope, map, folder) shifted clear of the traffic-light controls; TAassets window size/position persists across launches.
> - **Tolerant standalone loading** — `gamedata/sidedata.tdf` is optional; palette lookup falls back through side → standard → neutral; missing `TA_Features_2013.ccx` is logged clearly.
> - **HPIView extraction** — the previously-stub `Extract All` menu item is implemented, so you can now dump the entire archive to a folder.
> - **Script VM hardening** — the COB `divide` opcode no longer traps on divide-by-zero (observed in TAESC scripts).
>
> **Using the prebuilt TAassets**
> 1. Clone this repo, open `SwiftTA.xcworkspace` in Xcode 26+, or build from CLI:
>    ```
>    xcodebuild -workspace SwiftTA.xcworkspace -scheme TAassets \
>               -destination 'platform=macOS,arch=arm64' \
>               -configuration Release build
>    ```
> 2. Copy `build/.../Release/TAassets.app` anywhere you like (e.g. `~/Applications`).
> 3. First launch: right-click the app → Open (ad-hoc signed, so Gatekeeper asks once).
> 4. `File → Open…` → pick any directory of TA archives. Unit browser, file browser, and map browser all populate.
>    - Switch mods via the **Mods** menu.
>    - Open `<base>/mods/<ModName>` directly — it's treated as `base + mod` automatically.
>
> **Using HPIView**
> 1. Same build command with `-scheme HPIView`.
> 2. `File → Open…` on any `.hpi`, `.ufo`, `.ccx`, `.gp3`, or `.gpf`.
> 3. Drill into `objects3d/` → click a `.3DO` → browse the piece tree and script references on the right. Split divider resizes the outline.
> 4. Extract single files, folders, or the whole archive from the **File** menu.
>
> ---

I like [Swift](https://swift.org); but I'd like to get to know it better outside of my day job: writing iOS apps and libraries. So I've decided to retrace the steps of an old project I worked on ages ago: [writing a clone of Total Annihilation](https://github.com/loganjones/nTA-Total-Annihilation-Clone).

Currently, there is a simple game client (macOS, iOS, Linux) that loads up a hardcoded map and displays a single unit. See the [Build](#build) section for information on building and running the client.

![Screenshot](SwiftTA.jpg "SwiftTA Screenshot")

Additionally, there are a couple of macOS applications, [TAassets](#taassets) and [HPIView](#hpiview), that browse TA archive files (HPI & UFO files) and shows a preview of its contents.

## Build

#### macOS & iOS

Use the SwiftTA workspace (SwiftTA.xcworkspace) to build the macOS and/or the iOS game client.

#### Linux

The Linux build was developed using the official Swift 4.2 binaries for Ubuntu 16.04 from Swift.org. Additionally, the following packages are necessary to build:
```
clang libicu-dev libcurl3 libglfw3-dev libglfw3 libpng-dev
```

To build the game target, use a terminal to run `swift build` from the `SwiftTA/SwiftTA Linux` directory. To run the game, use `swift run`.

#### Windows

😅 ... yeah, about that. I haven't been able to get a build of the Swift compiler working on my Windows machine. It would be much easier if there were official builds available from Swift.org or even from Microsoft; but that is not a reality yet; maybe after Swift 5 and the ABI work? Another complication would be the lack of a C++ interface.

## Game Assets

Running the current game client requires that the Total Annihilation game files be accessible in your current user's Documents directory. More specifically, the game is hardcoded to look in `~/Documents/Total Annihilation` for any .hpi files (or .ufo, .ccx, etc). This is certainly a hack and will be addressed in the future. Note: a symbolic link to another directory is acceptable; though the link must be named `Total Annihilation`.

#### iOS

On iOS, this is difficult due to the lack of direct filesystem access. The easiest way to get the files into the right place is to run the game app once; and then use iTunes to copy the `Total Annihilation` directory over to the app's container. Find [device] -> File Sharing -> SwiftTA and just drag-and-drop the entire folder.

#### Linux

To run the game, use `swift run` from the `SwiftTA/SwiftTA Linux` directory (this will also build the project if it hasn't been built already).

Note: You will need an OpenGL 3.0 capable graphics driver to run the game. For development, I've been using the default driver in a VMWare Fusion install.

## TAassets

![Screenshot](TAassets.gif "TAassets Screenshot")

A macOS application that browses all of the assets contained in the TA archive files (HPI & UFO files) of a TA install directory. With this you can see the "virtual" file-sytem hierarchy that TA uses to load its assets. Additionally, you can browse specific categories (like units) to see a more complete representation (model + textures + animations).

You will need a Mac (natch) and a Total Annihilation installation somewhere on your browsable file-system. TAassets will read the files just as TA would; so any downloadable unit (a UFO) or other third-party material should "just work".

## HPIView

![Screenshot](HpiView.jpg "HpiView Screenshot")

A macOS application that browses the TA archive files (HPI & UFO files) and shows a preview of its contents. This is similar to an old Windows program (which I believe had the same name).

You will need a Mac and an HPI file or two. You can find these in Total Annihilation's main install directory. Any downloadable unit (a UFO) will work as well. As a bonus, you can also browse Total Annihilation: Kingdoms HPI files.

## Next Steps

Continuous iteration on the game client. Real unit loading. A full object system. UI interaction. So much to do.
