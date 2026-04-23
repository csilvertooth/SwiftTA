//
//  UnitModel+Bounds.swift
//  SwiftTA-Core
//

import Foundation
import simd

public extension UnitModel {

    /// World-space position of a piece with the current animation state applied.
    /// Walks the piece's ancestor chain from the root down, multiplying each
    /// piece's local translation/rotation matrix so Create-time IK queries like
    /// `get PIECE_XZ(tip)` see the result of intermediate `turn ... now` calls.
    func pieceWorldPosition(_ index: Pieces.Index, instance: UnitModel.Instance) -> Vertex3f {
        let t = pieceWorldTransform(index, instance: instance)
        return Vertex3f(x: t.columns.3.x, y: t.columns.3.y, z: t.columns.3.z)
    }

    func pieceWorldTransform(_ index: Pieces.Index, instance: UnitModel.Instance) -> matrix_float4x4 {
        var transform = matrix_float4x4.identity
        if index < parents.count {
            for ancestor in parents[index] {
                transform = transform * pieceLocalTransform(ancestor, instance: instance)
            }
        }
        transform = transform * pieceLocalTransform(index, instance: instance)
        return transform
    }

    private func pieceLocalTransform(_ index: Pieces.Index, instance: UnitModel.Instance) -> matrix_float4x4 {
        let piece = pieces[index]
        let anim = index < instance.pieces.count ? instance.pieces[index] : PieceState()
        let offset = piece.offset
        let move = anim.move
        let turn = anim.turn
        let rad = GameFloat.pi / 180
        let sx = Darwin.sin(turn.x * rad), cx = Darwin.cos(turn.x * rad)
        let sy = Darwin.sin(turn.y * rad), cy = Darwin.cos(turn.y * rad)
        let sz = Darwin.sin(turn.z * rad), cz = Darwin.cos(turn.z * rad)
        // R = R_SIMDz(turn.y) · R_SIMDy(turn.z) · R_SIMDx(turn.x). Yaw is the
        // outermost rotation; a child's turn.x (pitch) therefore rotates around
        // an axis that stays in the horizontal plane regardless of the parent's
        // own pitch. TA walker IK (CORMKL's Create/PositionLegs) assumes this —
        // with pitch outermost the bisection's knee axis rotated into a near-
        // vertical line whenever the shoulder had any pitch, making the
        // distance-vs-angle function unimodal instead of monotonic and freezing
        // the bisection at its degenerate minimum.
        return matrix_float4x4(columns: (
            vector_float4(cy * cz,
                          sy * cz,
                          -sz,
                          0),
            vector_float4((cy * sz * sx) - (sy * cx),
                          (sy * sz * sx) + (cy * cx),
                          cz * sx,
                          0),
            vector_float4((cy * sz * cx) + (sy * sx),
                          (sy * sz * cx) - (cy * sx),
                          cz * cx,
                          0),
            vector_float4(offset.x - move.x,
                          offset.y - move.z,
                          offset.z + move.y,
                          1)
        ))
    }
}

public extension UnitModel {

    /// The farthest distance from the model origin to any vertex, measured after
    /// each piece's local offset is added to the accumulated parent offset.
    var maxWorldExtent: GameFloat {
        var extent: GameFloat = 0
        let rootsToVisit: [Pieces.Index] = roots.isEmpty ? [root] : roots
        for rootIndex in rootsToVisit {
            accumulate(pieceIndex: rootIndex, parentOffset: .zero, into: &extent)
        }
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
