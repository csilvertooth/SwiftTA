# Bootstrap SwiftTA on Apple Silicon for TA Archive and 3DO Viewing

## Objective
Modernize and validate the SwiftTA workspace on current macOS + Xcode + Apple silicon, using the existing HPIView and TAassets apps as the base for a Total Annihilation archive browser and 3DO/asset viewer.

## Scope
1. Open and build SwiftTA.xcworkspace on current Xcode/macOS.
2. Make the macOS targets HPIView and TAassets compile and run on Apple silicon.
3. Limit changes to compatibility/build/runtime modernization unless a parser fix is required to restore existing behavior.
4. Verify archive browsing for HPI/UFO and audit existing support for CCX/other TA archives.
5. Add extraction support to HPIView:
   - extract selected file
   - extract selected folder
   - extract entire archive
6. Inspect TAassets and document the extension points for:
   - 3DO/model loading
   - texture/palette resolution
   - piece hierarchy display
   - future export to normalized JSON / glTF pipeline

## Non-Goals
- No broad parser rewrites unless necessary.
- No full editor implementation yet.
- No speculative engine-side schema work in this pass.

## Deliverables
- Apple silicon build notes
- Compatibility fixes committed in repo
- Running HPIView app
- Running TAassets app
- Extraction features in HPIView
- Architecture note for turning TAassets into a dedicated 3DO inspector
