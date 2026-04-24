//
//  TileCommand.swift
//  AEX-MapEditor
//
//  Phase 4 — tile painting. The tile-index map stores a uint16 per
//  2×2 height-cell block (i.e. per 32×32-world-pixel tile). Painting a
//  tile means overwriting one of those indices with the index of a
//  tile from the map's tileSet. Each paint is an undoable command that
//  captures the previous and new index for the cell it touched.
//

import Foundation
import SwiftTA_Core


struct TilePaintCommand: MapCommand {
    let tileColumn: Int
    let tileRow: Int
    let tileIndexMapColumns: Int
    let previous: UInt16
    let next: UInt16

    func apply(to map: EditableMap) {
        writeIndex(next, in: &map.model.tileIndexMap.indices)
        map.markModified()
    }

    func revert(on map: EditableMap) {
        writeIndex(previous, in: &map.model.tileIndexMap.indices)
        map.markModified()
    }

    private func writeIndex(_ value: UInt16, in data: inout Data) {
        let linear = tileRow * tileIndexMapColumns + tileColumn
        let byteOffset = linear * MemoryLayout<UInt16>.size
        guard byteOffset + MemoryLayout<UInt16>.size <= data.count else { return }
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt16.self)
            p[linear] = value
        }
    }
}
