//
//  TaMapModelWriterTests.swift
//  SwiftTA-CoreTests
//
//  Round-trip coverage for the TNT writer. Phase 1 of the map-editor
//  work asserts that every map serialized by TaMapModel.writeTnt()
//  reads back equal to the original — this is the regression gate the
//  later editor UI rests on.
//
//  The synthetic tests construct a MapModel in memory and round-trip
//  it, which catches writer bugs without needing any external .tnt
//  fixtures. Real-map round-tripping (setting the
//  SWIFTTA_TEST_MAPS_DIR env var to a directory of loose .tnt files)
//  is optional and skipped when the variable is unset — useful for
//  local validation against the actual Cavedog shipping maps without
//  bundling them in the repo.
//

import XCTest
@testable import SwiftTA_Core


final class TaMapModelWriterTests: XCTestCase {

    // MARK: - Synthetic round-trip

    /// A minimal 4×4 map with two tiles in the tileset, one feature, a
    /// non-zero sea level, and a deterministic height pattern. Exercises
    /// every section of the writer.
    func testSyntheticMap_RoundTripsExactly() throws {
        let original = makeSyntheticMap(
            mapSize: Size2(width: 4, height: 4),
            tileCount: 2,
            seaLevel: 42,
            featureNames: ["Tree01"],
            placeFeatureEveryNCells: 3
        )

        let encoded = try original.writeTnt()
        let rehydrated = try decodeTa(from: encoded)

        assertMapsEqual(rehydrated, original)
    }

    /// Larger map with many features to exercise the feature-entry loop
    /// and a tile count that produces a non-trivial tile array.
    func testSyntheticMap_ManyFeatures_RoundTripsExactly() throws {
        let original = makeSyntheticMap(
            mapSize: Size2(width: 16, height: 16),
            tileCount: 10,
            seaLevel: 128,
            featureNames: (0..<32).map { "Feature\($0)" },
            placeFeatureEveryNCells: 5
        )

        let encoded = try original.writeTnt()
        let rehydrated = try decodeTa(from: encoded)

        assertMapsEqual(rehydrated, original)
    }

    /// Edge case: no features at all. featureCount must be 0, no
    /// feature-entry section written, and every featureMap cell must
    /// round-trip as nil.
    func testSyntheticMap_NoFeatures_RoundTripsExactly() throws {
        let original = makeSyntheticMap(
            mapSize: Size2(width: 8, height: 8),
            tileCount: 4,
            seaLevel: 0,
            featureNames: [],
            placeFeatureEveryNCells: 0
        )

        let encoded = try original.writeTnt()
        let rehydrated = try decodeTa(from: encoded)

        XCTAssertEqual(rehydrated.features.count, 0)
        XCTAssertTrue(rehydrated.featureMap.allSatisfy { $0 == nil })
        assertMapsEqual(rehydrated, original)
    }

    // MARK: - Error surface

    func testRejectsOversizedFeatureName() throws {
        var model = makeSyntheticMap(mapSize: Size2(4, 4), tileCount: 1, seaLevel: 0, featureNames: ["TooLong"], placeFeatureEveryNCells: 0)
        model.features = [FeatureTypeId(named: String(repeating: "A", count: 128))]
        XCTAssertThrowsError(try model.writeTnt()) { error in
            guard case TaMapModel.WriteError.featureNameTooLong = error else {
                XCTFail("Expected featureNameTooLong, got \(error)")
                return
            }
        }
    }

    func testRejectsHeightSampleCountMismatch() throws {
        var model = makeSyntheticMap(mapSize: Size2(4, 4), tileCount: 1, seaLevel: 0, featureNames: [], placeFeatureEveryNCells: 0)
        model.heightMap.samples.removeLast()
        XCTAssertThrowsError(try model.writeTnt()) { error in
            guard case TaMapModel.WriteError.heightSampleCountMismatch = error else {
                XCTFail("Expected heightSampleCountMismatch, got \(error)")
                return
            }
        }
    }

    // MARK: - Optional real-map round-trip

    /// Runs only when `SWIFTTA_TEST_MAPS_DIR` is set — iterates every
    /// loose `.tnt` in that directory and verifies the writer round-trips
    /// semantically. Skipped (not failed) when the env var is unset, so
    /// CI can stay hermetic while local devs can validate against their
    /// tafiles.
    func testRealMaps_RoundTripIfConfigured() throws {
        guard let dir = ProcessInfo.processInfo.environment["SWIFTTA_TEST_MAPS_DIR"] else {
            throw XCTSkip("Set SWIFTTA_TEST_MAPS_DIR to a directory of loose .tnt files to enable.")
        }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        let tntFiles = (try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension.lowercased() == "tnt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(tntFiles.isEmpty, "No .tnt files found under \(dir)")

        for file in tntFiles {
            guard let bytes = try? Data(contentsOf: file) else {
                XCTFail("\(file.lastPathComponent): could not read file")
                continue
            }
            let reader = DataReader(data: bytes, name: file.lastPathComponent)
            guard let parsed = try? MapModel(contentsOf: reader) else {
                XCTFail("\(file.lastPathComponent): could not parse TNT")
                continue
            }
            guard case .ta(let original) = parsed else {
                XCTFail("\(file.lastPathComponent): not a TA TNT file (skipping)")
                continue
            }

            let encoded: Data
            do {
                encoded = try original.writeTnt()
            } catch {
                XCTFail("\(file.lastPathComponent): writeTnt failed — \(error)")
                continue
            }

            let rehydrated: TaMapModel
            do {
                rehydrated = try decodeTa(from: encoded)
            } catch {
                XCTFail("\(file.lastPathComponent): rewritten TNT does not re-parse — \(error)")
                continue
            }

            assertMapsEqual(rehydrated, original, prefix: file.lastPathComponent)
        }
    }

    // MARK: - Helpers

    private func makeSyntheticMap(
        mapSize: Size2<Int>,
        tileCount: Int,
        seaLevel: Int,
        featureNames: [String],
        placeFeatureEveryNCells: Int
    ) -> TaMapModel {
        let tileSize = Size2(width: 32, height: 32)
        let tileBytes = tileCount * tileSize.area
        var tiles = Data(count: tileBytes)
        for i in 0..<tileBytes {
            tiles[i] = UInt8((i * 7) & 0xFF)
        }

        let tileIndexCount = (mapSize.width / 2) * (mapSize.height / 2)
        var tileIndexBytes = Data(count: tileIndexCount * MemoryLayout<UInt16>.size)
        tileIndexBytes.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt16.self)
            for i in 0..<tileIndexCount {
                p[i] = UInt16(i % max(1, tileCount))
            }
        }

        let heightSamples = (0..<mapSize.area).map { Int(UInt8(($0 * 17) & 0xFF)) }

        let features = featureNames.map { FeatureTypeId(named: $0) }
        let featureIndexRange = 0..<features.count
        var featureMap = [Int?](repeating: nil, count: mapSize.area)
        if placeFeatureEveryNCells > 0 && !features.isEmpty {
            for i in stride(from: 0, to: mapSize.area, by: placeFeatureEveryNCells) {
                let idx = i % features.count
                if featureIndexRange.contains(idx) {
                    featureMap[i] = idx
                }
            }
        }

        let minimapSize = Size2(width: max(1, mapSize.width), height: max(1, mapSize.height))
        var minimapData = Data(count: minimapSize.area)
        for i in 0..<minimapSize.area {
            minimapData[i] = UInt8((i * 3) & 0xFF)
        }

        return TaMapModel(
            mapSize: mapSize,
            tileSet: .init(tiles: tiles, count: tileCount, tileSize: tileSize),
            tileIndexMap: .init(
                indices: tileIndexBytes,
                size: Size2(width: mapSize.width / 2, height: mapSize.height / 2),
                tileSize: tileSize
            ),
            seaLevel: seaLevel,
            heightMap: HeightMap(samples: heightSamples, count: mapSize),
            featureMap: featureMap,
            features: features,
            minimap: MinimapImage(size: minimapSize, data: minimapData)
        )
    }

    private func decodeTa(from data: Data) throws -> TaMapModel {
        let handle = DataReader(data: data)
        let model = try MapModel(contentsOf: handle)
        switch model {
        case .ta(let ta): return ta
        case .tak:
            XCTFail("Writer produced a Kingdoms-version TNT — expected TA")
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private func assertMapsEqual(_ lhs: TaMapModel, _ rhs: TaMapModel, prefix: String = "", file: StaticString = #file, line: UInt = #line) {
        let p = prefix.isEmpty ? "" : "\(prefix): "
        XCTAssertEqual(lhs.mapSize, rhs.mapSize, "\(p)mapSize", file: file, line: line)
        XCTAssertEqual(lhs.seaLevel, rhs.seaLevel, "\(p)seaLevel", file: file, line: line)
        XCTAssertEqual(lhs.heightMap.samples, rhs.heightMap.samples, "\(p)heightMap.samples", file: file, line: line)
        XCTAssertEqual(lhs.heightMap.sampleCount, rhs.heightMap.sampleCount, "\(p)heightMap.sampleCount", file: file, line: line)
        XCTAssertEqual(lhs.tileSet.count, rhs.tileSet.count, "\(p)tileSet.count", file: file, line: line)
        XCTAssertEqual(lhs.tileSet.tileSize, rhs.tileSet.tileSize, "\(p)tileSet.tileSize", file: file, line: line)
        XCTAssertEqual(lhs.tileSet.tiles, rhs.tileSet.tiles, "\(p)tileSet.tiles", file: file, line: line)
        XCTAssertEqual(lhs.tileIndexMap.indices, rhs.tileIndexMap.indices, "\(p)tileIndexMap.indices", file: file, line: line)
        XCTAssertEqual(lhs.tileIndexMap.size, rhs.tileIndexMap.size, "\(p)tileIndexMap.size", file: file, line: line)
        XCTAssertEqual(lhs.featureMap, rhs.featureMap, "\(p)featureMap", file: file, line: line)
        XCTAssertEqual(lhs.features.map { $0.name }, rhs.features.map { $0.name }, "\(p)features", file: file, line: line)
        XCTAssertEqual(lhs.minimap.size, rhs.minimap.size, "\(p)minimap.size", file: file, line: line)
        XCTAssertEqual(lhs.minimap.data, rhs.minimap.data, "\(p)minimap.data", file: file, line: line)
    }
}


// MARK: - In-memory FileReadHandle

/// Minimal in-memory seekable/readable file used by the synthetic round-trip
/// tests. The real map loader only requires `FileReadHandle` semantics
/// (read + seek), so Data-backed tests can avoid touching the filesystem.
private final class DataReader: FileReadHandle {
    private let data: Data
    private var cursor: Int = 0
    let fileName: String

    init(data: Data, name: String = "<in-memory>") {
        self.data = data
        self.fileName = name
    }

    var fileSize: Int { data.count }
    var fileOffset: Int { cursor }

    func seek(toFileOffset offset: Int) {
        cursor = max(0, min(offset, data.count))
    }

    func readData(ofLength length: Int) -> Data {
        let end = min(cursor + length, data.count)
        let slice = data.subdata(in: cursor..<end)
        cursor = end
        return slice
    }

    func readDataToEndOfFile() -> Data {
        let slice = data.subdata(in: cursor..<data.count)
        cursor = data.count
        return slice
    }
}
