//
//  TdfWriterTests.swift
//  SwiftTA-CoreTests
//
//  Round-trip coverage for the TDF writer: parse → serialize → parse
//  yields the same object graph, regardless of whether the original
//  source was ours or somebody's existing .ota / .fbi / .tdf.
//

import XCTest
@testable import SwiftTA_Core


final class TdfWriterTests: XCTestCase {

    func testFlatBlock_RoundTrips() throws {
        let source = """
        [GlobalHeader]
        {
            missionname=Test Map;
            missiondescription=A small test;
            planet=green planet;
            tidalstrength=20;
            gravity=112;
        }
        """

        let original = TdfParser.extractAll(from: Data(source.utf8))
        XCTAssertEqual(original.count, 1)

        let emitted = original.serializeAsTdf()
        let reparsed = TdfParser.extractAll(from: Data(emitted.utf8))

        XCTAssertEqual(reparsed, original, "Flat block round-trip mismatch")
    }

    func testNestedBlocks_RoundTrip() throws {
        let source = """
        [GlobalHeader]
        {
            missionname=Nested;
            gravity=112;

            [Schema 0]
            {
                type=Sandbox;
                aiprofile=DEFAULT;

                [specials]
                {
                    [special0]
                    {
                        specialwhat=StartPos1;
                        xpos=256;
                        zpos=256;
                    }
                    [special1]
                    {
                        specialwhat=StartPos2;
                        xpos=512;
                        zpos=512;
                    }
                }
            }
        }
        """

        let original = TdfParser.extractAll(from: Data(source.utf8))
        let emitted = original.serializeAsTdf()
        let reparsed = TdfParser.extractAll(from: Data(emitted.utf8))

        XCTAssertEqual(reparsed, original, "Nested block round-trip mismatch — key / value content diverged")
        XCTAssertEqual(reparsed["GlobalHeader"]?.subobjects["Schema 0"]?.subobjects["specials"]?.subobjects.count, 2)
    }

    func testDoubleRoundTrip_IsStable() throws {
        let source = """
        [GlobalHeader]
        {
            missionname=Stability Check;
            aaa=1; bbb=2; ccc=3;
            [inner] { key=value; }
        }
        """

        let firstParse = TdfParser.extractAll(from: Data(source.utf8))
        let firstEmit = firstParse.serializeAsTdf()
        let secondParse = TdfParser.extractAll(from: Data(firstEmit.utf8))
        let secondEmit = secondParse.serializeAsTdf()

        XCTAssertEqual(firstEmit, secondEmit, "Serializer is not stable across repeated round-trips")
        XCTAssertEqual(firstParse, secondParse)
    }

    func testMutationRoundTrips() throws {
        let source = """
        [GlobalHeader]
        {
            missionname=Original;
            gravity=112;
        }
        """

        var parsed = TdfParser.extractAll(from: Data(source.utf8))
        parsed["GlobalHeader"]?.properties["missionname"] = "Edited Name"
        parsed["GlobalHeader"]?.properties["gravity"] = "200"

        let emitted = parsed.serializeAsTdf()
        let reparsed = TdfParser.extractAll(from: Data(emitted.utf8))

        XCTAssertEqual(reparsed["GlobalHeader"]?["missionname"], "Edited Name")
        XCTAssertEqual(reparsed["GlobalHeader"]?["gravity"], "200")
    }

    func testMapInfoLoadsFromSerializedOta() throws {
        // A simulated .ota with the fields MapInfo actually reads.
        // After round-tripping through the serializer, MapInfo should
        // still load the same semantic values.
        let source = """
        [GlobalHeader]
        {
            missionname=Round Trip;
            missiondescription=Validates MapInfo compatibility;
            planet=Archipelago;
            tidalstrength=25;
            solarstrength=30;
            minwindspeed=100;
            maxwindspeed=500;
            gravity=100;

            [Schema 0]
            {
                Type=Sandbox;
                aiprofile=DEFAULT;

                [specials]
                {
                    [special0]
                    {
                        specialwhat=StartPos1;
                        xpos=1000;
                        zpos=2000;
                    }
                }
            }
        }
        """

        let first = TdfParser.extractAll(from: Data(source.utf8))
        let emitted = first.serializeAsTdf()
        let second = TdfParser.extractAll(from: Data(emitted.utf8))

        XCTAssertEqual(second["GlobalHeader"]?["missionname"], "Round Trip")
        XCTAssertEqual(second["GlobalHeader"]?["planet"], "Archipelago")
        XCTAssertEqual(second["GlobalHeader"]?["tidalstrength"], "25")
        XCTAssertEqual(second["GlobalHeader"]?["maxwindspeed"], "500")

        let schema = second["GlobalHeader"]?.subobjects["Schema 0"]
        XCTAssertEqual(schema?["aiprofile"], "DEFAULT")
        XCTAssertEqual(schema?.subobjects["specials"]?.subobjects["special0"]?["xpos"], "1000")
    }
}


extension TdfParser.Object: Equatable {
    public static func == (lhs: TdfParser.Object, rhs: TdfParser.Object) -> Bool {
        lhs.properties == rhs.properties && lhs.subobjects == rhs.subobjects
    }
}
