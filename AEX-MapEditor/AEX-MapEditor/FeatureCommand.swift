//
//  FeatureCommand.swift
//  AEX-MapEditor
//
//  Commands for Phase 3 — feature placement and removal. A feature in
//  TA is whatever single item occupies a map cell (rocks, trees,
//  wrecks, metal deposits). Each cell of featureMap carries either an
//  index into model.features or nil for "nothing there". The editor
//  manipulates that array directly; the game engine is responsible for
//  rendering the actual sprite at load time.
//

import Foundation
import SwiftTA_Core


/// Sets the feature index at a single cell and records the previous
/// value for undo. If the new index is nil (no feature), this is an
/// erase; if the index refers to a `model.features` entry that doesn't
/// yet exist, the caller is expected to have appended it to the array
/// first — this command doesn't mutate the feature table.
struct FeatureAssignCommand: MapCommand {
    let cellIndex: Int
    let previous: Int?
    let next: Int?

    func apply(to map: EditableMap) {
        guard map.model.featureMap.indices.contains(cellIndex) else { return }
        map.model.featureMap[cellIndex] = next
        map.markModified()
    }

    func revert(on map: EditableMap) {
        guard map.model.featureMap.indices.contains(cellIndex) else { return }
        map.model.featureMap[cellIndex] = previous
        map.markModified()
    }
}


/// Appends a new feature type to the map's feature table. Used when
/// the user types a name that isn't already present; the index of the
/// newly-added entry is returned via the command's `appendedIndex` so
/// a subsequent `FeatureAssignCommand` can place it. Kept as its own
/// command so undoing the assign doesn't leave orphaned entries in
/// the feature table, and undoing the *add* doesn't break assigns.
struct FeatureTypeAppendCommand: MapCommand {
    let featureName: String
    /// Filled in after the first apply so revert knows what to remove.
    /// Mutating inside a value type's method requires inout patterns,
    /// so the command is recorded as a reference-backed wrapper in the
    /// undo stack — see `FeatureTypeAppendCommand.Record`.
    final class Record {
        var appendedIndex: Int?
    }
    let record: Record

    init(featureName: String) {
        self.featureName = featureName
        self.record = Record()
    }

    func apply(to map: EditableMap) {
        let newIndex = map.model.features.count
        map.model.features.append(FeatureTypeId(named: featureName))
        record.appendedIndex = newIndex
        map.markModified()
    }

    func revert(on map: EditableMap) {
        // Only pop the last entry if it's actually the one we appended;
        // a re-ordering done by another command in between would make
        // blind popping unsafe.
        guard let idx = record.appendedIndex,
              idx == map.model.features.count - 1,
              map.model.features.indices.contains(idx),
              map.model.features[idx].name == featureName
        else { return }
        map.model.features.removeLast()
        map.markModified()
    }
}
