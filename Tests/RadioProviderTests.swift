import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class RadioProviderTests: XCTestCase {
    func testPromptSourcesBuildOnlyTheirDocumentedTerms() throws {
        XCTAssertEqual(
            RadioPromptSource.listening.prompt(username: " listener ", input: "ignored"),
            "stats:listener::all_time"
        )
        XCTAssertEqual(
            RadioPromptSource.recommendations.prompt(username: "listener", input: ""),
            "recs:listener::unlistened"
        )
        XCTAssertEqual(
            RadioPromptSource.artist.prompt(username: "listener", input: " Björk "),
            "artist:(Björk)"
        )
        XCTAssertEqual(
            RadioPromptSource.tag.prompt(username: "listener", input: " dream pop "),
            "tag:(dream pop)"
        )
        XCTAssertEqual(
            RadioPromptSource.advanced.prompt(username: "listener", input: " #metal "),
            "#metal"
        )
        XCTAssertNil(RadioPromptSource.artist.prompt(username: "listener", input: "artist) tag:(rock"))
        XCTAssertNil(RadioPromptSource.tag.prompt(username: "listener", input: "x"))
        XCTAssertNil(RadioPromptSource.advanced.prompt(username: "listener", input: "abc"))

        let options = try XCTUnwrap(RadioGenerationOptions(prompt: " #dream-pop ", mode: .hard))
        XCTAssertEqual(options.prompt, "#dream-pop")
        let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(options.listenBrainzURL), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "prompt" })?.value, "#dream-pop")
        XCTAssertEqual(query.first(where: { $0.name == "mode" })?.value, "hard")
    }

    func testGenerationUsesOneBatchMetadataRequestAndPreservesOrder() async throws {
        let firstID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let releaseID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let transport = RadioFixtureTransport(
            generated: Self.generated(firstID: firstID, secondID: secondID),
            metadata: [
                firstID: .init(
                    title: "Canonical first",
                    artistName: "Canonical artist",
                    artistMBIDs: [],
                    releaseTitle: "Canonical album",
                    releaseMBID: releaseID,
                    releaseGroupMBID: nil,
                    artworkReleaseMBID: releaseID,
                    durationMilliseconds: 241_000
                ),
            ]
        )
        let provider = ListenBrainzRadioProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let options = try XCTUnwrap(RadioGenerationOptions(prompt: "#ambient", mode: .medium))

        let mix = try await provider.generate(options: options)

        XCTAssertEqual(mix.title, "Fixture mix")
        XCTAssertEqual(mix.feedback, ["Using your prompt", "2 tracks"])
        XCTAssertEqual(mix.tracks.map(\.recording.identity.mbid), [firstID, secondID, firstID])
        XCTAssertEqual(mix.tracks.first?.recording.title, "Canonical first")
        XCTAssertEqual(mix.tracks.first?.recording.artworkReleaseMBID, releaseID)
        XCTAssertEqual(mix.tracks[1].recording.title, "Second fallback")
        XCTAssertFalse(mix.metadataEnrichmentFailed)

        let calls = await transport.recordedCalls()
        XCTAssertEqual(calls, [.generate("#ambient", .medium), .metadata([firstID, secondID])])
    }

    func testMetadataFailureKeepsGeneratedTracksWithoutRegenerating() async throws {
        let recordingID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let transport = RadioFixtureTransport(
            generated: Self.generated(firstID: recordingID, secondID: nil),
            metadataError: .unknownError
        )
        let provider = ListenBrainzRadioProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let options = try XCTUnwrap(RadioGenerationOptions(prompt: "artist:(Björk)", mode: .easy))

        let mix = try await provider.generate(options: options)

        XCTAssertTrue(mix.metadataEnrichmentFailed)
        XCTAssertEqual(mix.tracks.first?.recording.title, "First fallback")
        let calls = await transport.recordedCalls()
        XCTAssertEqual(calls.filter { if case .generate = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(calls.filter { if case .metadata = $0 { true } else { false } }.count, 1)
    }

    func testRateLimitMapsAfterOneGatedGenerationCall() async throws {
        let transport = RadioFixtureTransport(generationError: .rateLimited(resetIn: 3))
        let provider = ListenBrainzRadioProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let options = try XCTUnwrap(RadioGenerationOptions(prompt: "stats:listener", mode: .easy))

        do {
            _ = try await provider.generate(options: options)
            XCTFail("Expected rate limit")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 3)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let calls = await transport.recordedCalls()
        XCTAssertEqual(calls.count, 1)
    }

    func testMetadataRateLimitKeepsMixAndDefersTheNextGeneration() async throws {
        let recordingID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let transport = RadioFixtureTransport(
            generated: Self.generated(firstID: recordingID, secondID: nil),
            metadataError: .rateLimited(resetIn: 1)
        )
        let gate = RequestGate(minimumInterval: .zero)
        let provider = ListenBrainzRadioProvider(transport: transport, gate: gate)
        let options = try XCTUnwrap(RadioGenerationOptions(prompt: "#ambient", mode: .easy))

        let mix = try await provider.generate(options: options)

        XCTAssertTrue(mix.metadataEnrichmentFailed)
        XCTAssertEqual(mix.tracks.first?.recording.title, "First fallback")
        let callsBeforeRetry = await transport.recordedCalls()
        XCTAssertEqual(callsBeforeRetry.count, 2)

        let deferredGeneration = Task { try await provider.generate(options: options) }
        try await ContinuousClock().sleep(for: .milliseconds(60))
        let callsDuringDeferral = await transport.recordedCalls()
        XCTAssertEqual(
            callsDuringDeferral.count,
            2,
            "The next generator call must remain behind the metadata response's Retry-After deferral"
        )
        deferredGeneration.cancel()
        do {
            _ = try await deferredGeneration.value
            XCTFail("Expected the deferred generation to cancel before transport admission")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testCancellationBeforeGateAdmissionDoesNotGenerate() async throws {
        let gate = RequestGate(minimumInterval: .seconds(5))
        _ = try await gate.perform { true }
        let transport = RadioFixtureTransport(generated: Self.generated(firstID: nil, secondID: nil))
        let provider = ListenBrainzRadioProvider(transport: transport, gate: gate)
        let options = try XCTUnwrap(RadioGenerationOptions(prompt: "#ambient", mode: .easy))

        let task = Task { try await provider.generate(options: options) }
        await Task.yield()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        try await ContinuousClock().sleep(for: .milliseconds(30))
        let calls = await transport.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    private static func generated(firstID: UUID?, secondID: UUID?) -> LBGeneratedRadio {
        let first = LBPlaylistTrack(
            title: "First fallback",
            artistCreditName: "First artist",
            releaseName: nil,
            durationMilliseconds: 180_000,
            recordingMBID: firstID,
            releaseMBID: nil,
            artistMBIDs: [],
            caaReleaseMBID: nil,
            caaID: nil
        )
        let second = LBPlaylistTrack(
            title: "Second fallback",
            artistCreditName: "Second artist",
            releaseName: "Second album",
            durationMilliseconds: nil,
            recordingMBID: secondID,
            releaseMBID: nil,
            artistMBIDs: [],
            caaReleaseMBID: nil,
            caaID: nil
        )
        return LBGeneratedRadio(
            title: " Fixture mix ",
            annotation: "A generated playlist",
            tracks: [first, second, first],
            feedback: ["Using your prompt", "2 tracks", "using your prompt", " "]
        )
    }
}

private actor RadioFixtureTransport: RadioTransport {
    enum Call: Equatable {
        case generate(String, LBRadioMode)
        case metadata([UUID])
    }

    private let generated: LBGeneratedRadio?
    private let metadata: [UUID: RadioRecordingMetadata]
    private let generationError: LBError?
    private let metadataError: LBError?
    private var calls: [Call] = []

    init(
        generated: LBGeneratedRadio? = nil,
        metadata: [UUID: RadioRecordingMetadata] = [:],
        generationError: LBError? = nil,
        metadataError: LBError? = nil
    ) {
        self.generated = generated
        self.metadata = metadata
        self.generationError = generationError
        self.metadataError = metadataError
    }

    func generate(prompt: String, mode: LBRadioMode) async throws -> LBGeneratedRadio {
        calls.append(.generate(prompt, mode))
        if let generationError { throw generationError }
        return generated ?? LBGeneratedRadio(title: nil, annotation: nil, tracks: [], feedback: [])
    }

    func recordingMetadata(mbids: [UUID]) async throws -> [UUID: RadioRecordingMetadata] {
        calls.append(.metadata(mbids))
        if let metadataError { throw metadataError }
        return metadata
    }

    func recordedCalls() -> [Call] { calls }
}
