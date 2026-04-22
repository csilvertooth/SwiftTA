//
//  UnitModel+Bounds.swift
//  SwiftTA-Core
//

import Foundation

public extension UnitModel {

    /// The farthest distance from the model origin to any vertex, measured after
    /// each piece's local offset is added to the accumulated parent offset.
    var maxWorldExtent: GameFloat {
        var extent: GameFloat = 0
        accumulate(pieceIndex: root, parentOffset: .zero, into: &extent)
        return extent
    }

    private func accumulate(pieceIndex: Pieces.Index,
                            parentOffset: Vertex3f,
                            into extent: inout GameFloat) {
        let piece = pieces[pieceIndex]
        let offset = piece.offset + parentOffset

        for primitiveIndex in piece.primitives {
            guard primitiveIndex != groundPlate else { continue }
            for vertexIndex in primitives[primitiveIndex].indices {
                let v = vertices[vertexIndex] + offset
                let local = max(abs(v.x), abs(v.y), abs(v.z))
                if local > extent { extent = local }
            }
        }

        for child in piece.children {
            accumulate(pieceIndex: child, parentOffset: offset, into: &extent)
        }
    }
}
