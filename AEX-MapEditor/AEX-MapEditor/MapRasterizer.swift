//
//  MapRasterizer.swift
//  AEX-MapEditor
//
//  Assembles a full-map RGBA raster from a TaMapModel's tileset, tile
//  index map, and palette. Used by MapCanvasView when the user has
//  the Tiles view active so the canvas shows the actual painted map
//  instead of the grayscale heights.
//
//  The Phase 4 implementation runs on the main thread via Core
//  Graphics. A 64×64 map yields a 1024×1024 raster — half a second at
//  most to assemble, and the cached image is re-used until the user
//  paints a tile. If/when the editor scales up to huge maps or
//  real-time repaints, this is the natural place to swap in the
//  Metal tile renderer from TAassets.
//

import Cocoa
import SwiftTA_Core


enum MapRasterizer {

    /// Returns a CGImage whose dimensions are (mapSize.width * 16)
    /// × (mapSize.height * 16) — the same world-pixel resolution Cavedog
    /// uses. Each 32×32 tile from `tileSet` is blitted into the target
    /// at the position indicated by `tileIndexMap`.
    static func render(_ model: TaMapModel, using palette: Palette) -> CGImage? {
        let mapSize = model.mapSize
        let tileSize = model.tileSet.tileSize
        guard tileSize.width == 32, tileSize.height == 32 else { return nil }

        // Resolution: each height cell is 16×16, each tile spans 2×2
        // height cells. So image width = (mapSize.width / 2) * 32 =
        // mapSize.width * 16. Same for height.
        let rasterWidth = mapSize.width * 16
        let rasterHeight = mapSize.height * 16
        guard rasterWidth > 0, rasterHeight > 0 else { return nil }

        let bytesPerRow = rasterWidth * 4
        var pixels = [UInt8](repeating: 0, count: rasterHeight * bytesPerRow)

        // Snapshot palette colors once so the inner loop stays tight.
        var paletteRGBA = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            let c = palette[i]
            // Pack as little-endian ABGR so the 8-bit byte layout
            // RGBA (premultipliedLast) matches.
            paletteRGBA[i] =
                (UInt32(c.alpha) << 24) |
                (UInt32(c.blue) << 16) |
                (UInt32(c.green) << 8) |
                UInt32(c.red)
        }

        let tileIndexData = model.tileIndexMap.indices
        let tileIndexCols = mapSize.width / 2
        let tileIndexRows = mapSize.height / 2
        let tileBytes = model.tileSet.tiles
        let tilePixelCount = tileSize.area
        let tileCount = model.tileSet.count

        tileIndexData.withUnsafeBytes { (tileIndexRaw: UnsafeRawBufferPointer) in
            let tileIndices = tileIndexRaw.bindMemory(to: UInt16.self)
            tileBytes.withUnsafeBytes { (tileRaw: UnsafeRawBufferPointer) in
                let tilePalettes = tileRaw.bindMemory(to: UInt8.self)

                pixels.withUnsafeMutableBufferPointer { out in
                    let outBytes = out.baseAddress!.withMemoryRebound(to: UInt32.self, capacity: rasterWidth * rasterHeight) { $0 }
                    for tr in 0..<tileIndexRows {
                        for tc in 0..<tileIndexCols {
                            let tileIndex = Int(tileIndices[tr * tileIndexCols + tc])
                            guard tileIndex < tileCount else { continue }
                            let tileStart = tileIndex * tilePixelCount
                            let destX = tc * tileSize.width
                            let destY = tr * tileSize.height
                            for row in 0..<tileSize.height {
                                let srcRow = tileStart + row * tileSize.width
                                let dstRow = (destY + row) * rasterWidth + destX
                                for col in 0..<tileSize.width {
                                    let colorIndex = Int(tilePalettes[srcRow + col])
                                    outBytes[dstRow + col] = paletteRGBA[colorIndex]
                                }
                            }
                        }
                    }
                }
            }
        }

        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: rasterWidth,
            height: rasterHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Smaller version of a single tile for the tile picker UI.
    /// Returns a 32×32 NSImage suitable for an NSCollectionView or a
    /// simple scrolling palette.
    static func renderTile(index: Int, in model: TaMapModel, using palette: Palette) -> NSImage? {
        let tileSize = model.tileSet.tileSize
        guard tileSize.width == 32, tileSize.height == 32 else { return nil }
        guard model.tileSet[safe: index] != nil else { return nil }
        let tileData = model.tileSet[index]

        var pixels = [UInt8](repeating: 0, count: tileSize.area * 4)
        tileData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<tileSize.area {
                let color = palette[Int(bytes[i])]
                pixels[i * 4 + 0] = color.red
                pixels[i * 4 + 1] = color.green
                pixels[i * 4 + 2] = color.blue
                pixels[i * 4 + 3] = color.alpha
            }
        }

        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        guard let cgImage = CGImage(
            width: tileSize.width,
            height: tileSize.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: tileSize.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: tileSize.width, height: tileSize.height))
    }
}
