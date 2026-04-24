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
}


final class MapCanvasView: NSView {

    weak var delegate: MapCanvasViewDelegate?

    /// The map being edited. The canvas reads `map.model.heightMap.samples`
    /// directly on each redraw and writes through it during brush strokes,
    /// so setting a new map or committing a command both require
    /// `needsDisplay = true` to repaint.
    var map: EditableMap? {
        didSet { needsDisplay = true }
    }

    /// Brush configuration, surfaced to the window's tool palette.
    var brushRadius: Int = 3
    var brushStrength: Int = 16
    /// When true, the next stroke lowers heights instead of raising.
    var eraseMode: Bool = false

    // MARK: - Internal state

    private var activeStroke: HeightBrushStroke?
    private var hoverCell: (col: Int, row: Int)?

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
        drawHeightRaster(of: map, in: ctx)
        drawBrushOverlay(in: ctx)
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
        let delta = eraseMode ? -brushStrength : brushStrength
        activeStroke = HeightBrushStroke(config: .init(radius: brushRadius, delta: delta))
        applyStamp(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        applyStamp(at: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        applyStamp(at: event.locationInWindow)
        if let command = activeStroke?.finish() {
            delegate?.canvasDidFinishStroke(command)
        }
        activeStroke = nil
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
        // Right-click toggles erase mode for the next stroke — same ergonomics
        // as most painting apps' "alt to erase" gesture. Shift could go here
        // later; keeping it basic for MVP.
        eraseMode.toggle()
        needsDisplay = true
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
