//
//  HeightBrushCommand.swift
//  AEX-MapEditor
//
//  One brush stroke = one command = one undo entry. The command captures
//  the exact (cellIndex, previousHeight, newHeight) tuples it touched so
//  undo can restore the pre-stroke state and redo can re-apply it. This
//  is the Phase 2 MVP tool — later phases add tile paint, feature place,
//  etc. on the same pattern.
//

import Foundation


protocol MapCommand {
    /// Applied when the command first runs, or when redo fires.
    func apply(to map: EditableMap)
    /// Called when undo fires.
    func revert(on map: EditableMap)
}


struct HeightBrushCommand: MapCommand {

    /// Cell changes keyed by mapModel sample index, so undo/redo touches
    /// only the cells actually affected by this stroke.
    let changes: [CellChange]

    struct CellChange {
        let cellIndex: Int
        let previous: Int
        let next: Int
    }

    func apply(to map: EditableMap) {
        for change in changes {
            map.model.heightMap.samples[change.cellIndex] = change.next
        }
        map.markModified()
    }

    func revert(on map: EditableMap) {
        for change in changes {
            map.model.heightMap.samples[change.cellIndex] = change.previous
        }
        map.markModified()
    }
}


/// A mouse drag produces many `stamp(on:)` calls; each stamp merges
/// under-brush cells into an accumulator. At stroke-end the accumulator
/// is snapshotted into a single `HeightBrushCommand` and pushed onto
/// undo. The "merge" behavior — an ongoing stroke that passes over the
/// same cell twice uses the larger height change — matches what every
/// painting app does: visually it looks like a continuous paint action
/// rather than snapping in steps.
final class HeightBrushStroke {

    struct Config {
        /// Brush radius measured in height-map cells (16 world-units each).
        var radius: Int
        /// Magnitude per stamp, 1-127. Positive raises, negative lowers.
        var delta: Int
    }

    private var config: Config
    private var accumulatedChanges: [Int: HeightBrushCommand.CellChange] = [:]

    init(config: Config) {
        self.config = config
    }

    /// Apply a brush stamp centred on (col, row) in height-map grid space.
    /// Height-map grid space uses the existing sampleCount as the canonical
    /// grid — each sample == one 16×16 world cell.
    func stamp(on map: EditableMap, col: Int, row: Int) {
        let samples = map.model.heightMap.samples
        let mapSize = map.model.mapSize

        let rSquared = config.radius * config.radius

        let minCol = max(0, col - config.radius)
        let maxCol = min(mapSize.width - 1, col + config.radius)
        let minRow = max(0, row - config.radius)
        let maxRow = min(mapSize.height - 1, row + config.radius)
        guard minCol <= maxCol && minRow <= maxRow else { return }

        for r in minRow...maxRow {
            for c in minCol...maxCol {
                let dx = c - col
                let dy = r - row
                let dSquared = dx * dx + dy * dy
                guard dSquared <= rSquared else { continue }

                // Linear falloff from full-strength at center to zero at edge.
                // Matches the visual expectation of a soft-edged round brush.
                let falloff: Double
                if config.radius == 0 {
                    falloff = 1.0
                } else {
                    let d = (Double(dSquared) / Double(rSquared)).squareRoot()
                    falloff = max(0.0, 1.0 - d)
                }
                let localDelta = Int((Double(config.delta) * falloff).rounded())
                guard localDelta != 0 else { continue }

                let index = r * mapSize.width + c
                let current = accumulatedChanges[index]?.next ?? samples[index]
                let previous = accumulatedChanges[index]?.previous ?? samples[index]
                let new = clamp(current + localDelta, min: 0, max: 255)

                if new != current {
                    accumulatedChanges[index] = HeightBrushCommand.CellChange(
                        cellIndex: index,
                        previous: previous,
                        next: new
                    )
                    map.model.heightMap.samples[index] = new
                }
            }
        }
        map.markModified()
    }

    /// Freeze the stroke into an undoable command, or nil if nothing changed.
    func finish() -> HeightBrushCommand? {
        guard !accumulatedChanges.isEmpty else { return nil }
        return HeightBrushCommand(
            changes: accumulatedChanges.values.sorted { $0.cellIndex < $1.cellIndex }
        )
    }
}


private func clamp<T: Comparable>(_ value: T, min lo: T, max hi: T) -> T {
    return max(lo, min(hi, value))
}
