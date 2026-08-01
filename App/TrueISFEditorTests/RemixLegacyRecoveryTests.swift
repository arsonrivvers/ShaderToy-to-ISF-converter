import XCTest
@testable import TrueISFEditor

final class RemixLegacyRecoveryTests: XCTestCase {
    private let isf = """
    /*{ "ISFVSN": "2.0" }*/
    void main(){ gl_FragColor=vec4(1.0); }
    """

    func test_candidate_doesNotConsumeASiblingsTranscriptEntry() {
        XCTAssertNil(RemixLegacyRecovery.candidate(
            childID: "r1-0",
            transcript: ["[r1-1] ```glsl\n\(isf)\n```"]
        ))
    }

    func test_candidate_requiresTheExactChildTagBoundary() {
        XCTAssertNil(RemixLegacyRecovery.candidate(
            childID: "r1-0",
            transcript: ["[r1-01] ```glsl\n\(isf)\n```"]
        ))
    }

    func test_candidate_recoversOnlyTheExactChildTaggedEntry() {
        XCTAssertEqual(
            RemixLegacyRecovery.candidate(
                childID: "r1-0",
                transcript: ["[r1-0] ```glsl\n\(isf)\n```"]
            ),
            isf
        )
    }

    func test_candidate_recoversEachCompleteChildIndependentlyFromRedactedSessionFixture() throws {
        let fixture = try decodedFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.currentBatch.map(\.id), ["r1-0", "r1-1", "r1-2", "r1-3", "r1-4"])
        XCTAssertTrue(fixture.currentBatch.allSatisfy { $0.isfSource.isEmpty })

        XCTAssertEqual(RemixLegacyRecovery.candidate(childID: "r1-0", transcript: fixture.transcript), shader("r1-0"))
        XCTAssertEqual(RemixLegacyRecovery.candidate(childID: "r1-1", transcript: fixture.transcript), shader("r1-1"))
        XCTAssertEqual(RemixLegacyRecovery.candidate(childID: "r1-3", transcript: fixture.transcript), shader("r1-3"))
    }

    func test_candidate_doesNotPromoteIncompleteChildrenFromRedactedSessionFixture() throws {
        let fixture = try decodedFixture()

        XCTAssertNil(RemixLegacyRecovery.candidate(childID: "r1-2", transcript: fixture.transcript))
        XCTAssertNil(RemixLegacyRecovery.candidate(childID: "r1-4", transcript: fixture.transcript))
    }

    private func decodedFixture() throws -> LegacySessionFixture {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "remix-2026-08-01-empty-result-session-v1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(LegacySessionFixture.self, from: Data(contentsOf: url))
    }

    private func shader(_ childID: String) -> String {
        """
        /*{ "ISFVSN": "2.0", "DESCRIPTION": "Recovered \(childID)" }*/
        void main(){ gl_FragColor=vec4(1.0); }
        """
    }
}

private struct LegacySessionFixture: Decodable {
    let schemaVersion: Int
    let currentBatch: [LegacyChildFixture]
    let transcript: [String]
}

private struct LegacyChildFixture: Decodable {
    let id: String
    let isfSource: String
}
