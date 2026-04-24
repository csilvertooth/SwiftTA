//
//  MapCanvasView.swift
//  AEX-MapEditor
//
//  Core Graphics canvas for the Phase 2 MVP. Renders the height-map as
//  a grayscale raster, draws a brush footprint overlay while the cursor
//  is hovering, and routes mouse drags into the active HeightBrushStroke.
//
//  The MVP deliberately uses CG, not Metal — a 256×256-cell map is only
//  65 536 grayscale pixels; painting on the main thread fits budget.
//  When the editor needs tile-level texture authoring (Phase 4) we swap
//  in the Metal renderer from TAassets. Keeping this simple keeps the
//  bring-up honest.
//

import Cocoa


protocol MapCanvasViewDelegate: AnyObject {
    /// Called when a brush stroke finishes. The delegate is responsible
    /// for wrapping the command into the undo manager.
    func canvasDidFinishStroke(_ command: MapCommand)
    /// Called every frame the stroke mutates the model, so the window
    /// controller can refresh its title bar / dirty marker.
    func canvasDidModifyMap()
    /// When the Features tool is active and the user clicks a cell,
    /// the delegate decides which feature index (if any) should be
    /// assigned — typically reads the current picker selection. A
    /// return of nil means "no change" (e.g. user hasn't picked a
    /// feature yet, or we're in erase mode); a non-nil .some(nil)
    /// means "remove any feature here".
    func canvasWantsFeatureAssignment(forCell index: Int) -> Int??
}


enum MapCanvasTool {
    case heights
    case features
    case tiles
}


final class MapCanvasView: NSView {

    weak var delegate: MapCanvasViewDelegate?

    /// The map being edited. The canvas reads `map.model.heightMap.samples`
    /// directly on each redraw and writes through it during brush strokes,
    /// so setting a new map or committing a command both require
    /// `needsDisplay = true` to repaint.
    var map: EditableMap? {
        didSet {
            tileRasterCache = nil
            needsDisplay = true
        }
    }

    /// Index into `map.model.tileSet` the user has selected as the
    /// "paint" tile in Tiles mode. Defaulted to 0 when a map loads;
    /// updated via `selectedTileIndex`.
    var selectedTileIndex: Int = 0

    /// Brush configuration, surfaced to the window's tool palette.
    var brushRadius: Int = 3
    var brushStrength: Int = 16
    /// When true, the next height stroke lowers instead of raising.
    var eraseMode: Bool = false

    /// Which tool's interactions take effect on mouse events.
    var activeTool: MapCanvasTool = .heights {
        didSet { needsDisplay = true }
    }

    // MARK: - Internal state

    private var activeStroke: HeightBrushStroke?
    private var hoverCell: (col: Int, row: Int)?
    /// Cached tile raster so we only re-rasterize when tiles or the
    /// loaded map actually change. Set to nil to force a rebuild.
    private var tileRasterCache: CGImage?

    /// Call when tile data changes (paint, undo, redo, save, etc.) so
    /// the next draw rebuilds the cached raster.
    func invalidateTileRaster() {
        tileRasterCache = nil
        needsDisplay = true
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let map = map, let ctx = NSGraphicsContext.current?.cgContext else { return }
        switch activeTool {
        case .tiles:
            drawTileRaster(of: map, in: ctx)
        default:
            drawHeightRaster(of: map, in: ctx)
        }
        drawFeatureOverlay(of: map, in: ctx)
        drawBrushOverlay(in: ctx)
    }

    private func drawTileRaster(of map: EditableMap, in ctx: CGContext) {
        if tileRasterCache == nil {
            tileRasterCache = MapRasterizer.render(map.model, using: map.palette)
        }
        guard let raster = tileRasterCache else { return }

        ctx.interpolationQuality = .none
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(raster, in: CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()
    }

    private func drawFeatureOverlay(of map: EditableMap, in ctx: CGContext) {
        guard let cellSize = cellSize() else { return }
        let mapSize = map.model.mapSize
        let featureMap = map.model.featureMap
        guard featureMap.count == mapSize.area else { return }

        // Solid fill so the feature squares pop against the grayscale
        // heightmap regardless of elevation. Alpha keeps the underlying
        // height visible so users can still judge steepness through the
        // overlay.
        ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.1, alpha: 0.55).cgColor)
        for i in 0..<featureMap.count {
            guard featureMap[i] != nil else { continue }
            let col = i % mapSize.width
            let row = i / mapSize.width
            let rect = CGRect(
                x: CGFloat(col) * cellSize.width,
                y: CGFloat(row) * cellSize.height,
                width: cellSize.width,
                height: cellSize.height
            )
            ctx.fill(rect)
        }
    }

    private func drawHeightRaster(of map: EditableMap, in ctx: CGContext) {
        let mapSize = map.model.mapSize
        guard mapSize.area > 0 else { return }
        let samples = map.model.heightMap.samples

        // Build a width×height grayscale image out of the raw samples,
        // then let CG scale it to the view. cellPixelSize = bounds / mapSize,
        // but we don't need to know it — CGImage scaling handles it.
        var pixels = [UInt8](repeating: 0, count: mapSize.area)
        for i in 0..<mapSize.area {
            pixels[i] = UInt8(clamping: samples[i])
        }

        pixels.withUnsafeBufferPointer { buffer in
            guard let provider = CGDataProvider(data: Data(buffer: buffer) as CFData) else { return }
            guard let image = CGImage(
                width: mapSize.width,
                height: mapSize.height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: mapSize.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ) else { return }

            ctx.interpolationQuality = .none
            ctx.saveGState()
            // View is flipped; flip the image's y-axis so row 0 draws at the top.
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: bounds.size))
            ctx.restoreGState()
        }
    }

    private func drawBrushOverlay(in ctx: CGContext) {
        guard let hover = hoverCell, let cellSize = cellSize() else { return }

        let originX = CGFloat(hover.col - brushRadius) * cellSize.width
        let originY = CGFloat(hover.row - brushRadius) * cellSize.height
        let diameter = CGFloat(brushRadius * 2 + 1)
        let rect = CGRect(
            x: originX,
            y: originY,
            width: diameter * cellSize.width,
            height: diameter * cellSize.height
        )

        ctx.saveGState()
        ctx.setStrokeColor(eraseMode
            ? NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.9).cgColor
            : NSColor(calibratedRed: 0.25, green: 0.75, blue: 1.0, alpha: 0.9).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
    }

    // MARK: - Mouse interaction

    override func mouseDown(with event: NSEvent) {
        switch activeTool {
        case .heights:
            let delta = eraseMode ? -brushStrength : brushStrength
            activeStroke = HeightBrushStroke(config: .init(radius: brushRadius, delta: delta))
            applyStamp(at: event.locationInWindow)
        case .features:
            handleFeatureClick(at: event.locationInWindow, remove: false)
        case .tiles:
            handleTileClick(at: event.locationInWindow)
        }
    }

    private func handleTileClick(at windowPoint: CGPoint) {
        guard let map = map else { return }
        let point = convert(windowPoint, from: nil)
        guard let tile = tileMapCellUnder(point) else { return }

        let tileIndexCols = map.model.mapSize.width / 2
        let linear = tile.row * tileIndexCols + tile.col
        let indices = map.model.tileIndexMap.indices
        guard (linear + 1) * MemoryLayout<UInt16>.size <= indices.count else { return }

        let previous = indices.withUnsafeBytes { raw -> UInt16 in
            raw.bindMemory(to: UInt16.self)[linear]
        }
        let next = UInt16(clamping: selectedTileIndex)
        guard previous != next else { return }

        let command = TilePaintCommand(
            tileColumn: tile.col,
            tileRow: tile.row,
            tileIndexMapColumns: tileIndexCols,
            previous: previous,
            next: next
        )
        command.apply(to: map)
        invalidateTileRaster()
        delegate?.canvasDidFinishStroke(command)
        delegate?.canvasDidModifyMap()
    }

    /// The tile-index grid is (mapSize.width / 2) × (mapSize.height / 2).
    /// Screen-to-tile-cell is the same cellSize() math scaled down by 2.
    private func tileMapCellUnder(_ point: CGPoint) -> (col: Int, row: Int)? {
        guard let map = map else { return nil }
        guard let cellSize = cellSize() else { return nil }
        let tileWidth = cellSize.width * 2
        let tileHeight = cellSize.height * 2
        let col = Int(floor(point.x / tileWidth))
        let row = Int(floor(point.y / tileHeight))
        let tileCols = map.model.mapSize.width / 2
        let tileRows = map.model.mapSize.height / 2
        guard col >= 0, col < tileCols, row >= 0, row < tileRows else { return nil }
        return (col, row)
    }

    override func mouseDragged(with event: NSEvent) {
        guard activeTool == .heights else { return }
        applyStamp(at: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        guard activeTool == .heights else { return }
        applyStamp(at: event.locationInWindow)
        if let command = activeStroke?.finish() {
            delegate?.canvasDidFinishStroke(command)
        }
        activeStroke = nil
    }

    private func handleFeatureClick(at windowPoint: CGPoint, remove: Bool) {
        guard let map = map else { return }
        let point = convert(windowPoint, from: nil)
        guard let cell = cellUnder(point) else { return }
        let cellIndex = cell.row * map.model.mapSize.width + cell.col

        if remove {
            let previous = map.model.featureMap[cellIndex]
            guard previous != nil else { return }
            let command = FeatureAssignCommand(cellIndex: cellIndex, previous: previous, next: nil)
            command.apply(to: map)
            delegate?.canvasDidFinishStroke(command)
            delegate?.canvasDidModifyMap()
            needsDisplay = true
            return
        }

        // Placement: ask the delegate what to assign. A return of .some(nil)
        // means "erase"; .some(.some(idx)) means assign that index; nil means
        // do nothing (e.g. no feature selected yet).
        guard let decision = delegate?.canvasWantsFeatureAssignment(forCell: cellIndex) else { return }
        let previous = map.model.featureMap[cellIndex]
        let command = FeatureAssignCommand(cellIndex: cellIndex, previous: previous, next: decision)
        command.apply(to: map)
        delegate?.canvasDidFinishStroke(command)
        delegate?.canvasDidModifyMap()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoverCell = cellUnder(point)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverCell = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        switch activeTool {
        case .heights:
            // Right-click toggles erase mode for the next height stroke.
            eraseMode.toggle()
            needsDisplay = true
        case .features:
            // Right-click erases the feature at the clicked cell,
            // regardless of the current picker selection.
            handleFeatureClick(at: event.locationInWindow, remove: true)
        case .tiles:
            // No "erase" for tiles — every cell must carry a valid tile
            // index. Right-click is a no-op in this mode for now.
            break
        }
    }

    private func applyStamp(at windowPoint: CGPoint) {
        guard let map = map, let stroke = activeStroke else { return }
        let point = convert(windowPoint, from: nil)
        guard let cell = cellUnder(point) else { return }

        stroke.stamp(on: map, col: cell.col, row: cell.row)
        delegate?.canvasDidModifyMap()
        needsDisplay = true
    }

    private func cellUnder(_ point: CGPoint) -> (col: Int, row: Int)? {
        guard let map = map, let cellSize = cellSize() else { return nil }
        let col = Int(floor(point.x / cellSize.width))
        let row = Int(floor(point.y / cellSize.height))
        let mapSize = map.model.mapSize
        guard col >= 0, col < mapSize.width, row >= 0, row < mapSize.height else { return nil }
        return (col, row)
    }

    private func cellSize() -> CGSize? {
        guard let map = map else { return nil }
        let mapSize = map.model.mapSize
        guard mapSize.width > 0, mapSize.height > 0 else { return nil }
        return CGSize(
            width: bounds.width / CGFloat(mapSize.width),
            height: bounds.height / CGFloat(mapSize.height)
        )
    }
}
