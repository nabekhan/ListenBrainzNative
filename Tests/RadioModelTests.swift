import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class RadioModelTests: XCTestCase {
    func testDuplicateGenerateTapIsIgnoredAndResultLoads() async throws {
        let provider = RadioProviderSpy(delay: .milliseconds(30))
        let model = RadioModel(provider: provider)
        let options = try XCTUnwrap(RadioGenerationOptions(prompt: "#ambient", mode: .easy))

        async let first: Void = model.generate(options: options)
        await Task.yield()
        async let second: Void = model.generate(options: options)
        _ = await (first, second)

        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(model.mix?.options, options)
        XCTAssertFalse(model.isGenerating)
        XCTAssertNil(model.errorMessage)
    }

    func testFailedRegenerationPreservesPreviousMix() async throws {
        let provider = RadioProviderSpy()
        let model = RadioModel(provider: provider)
        let first = try XCTUnwrap(RadioGenerationOptions(prompt: "#ambient", mode: .easy))
        await model.generate(options: first)
        let previous = try XCTUnwrap(model.mix)

        await provider.setError(RadioProviderError.generationUnavailable)
        let second = try XCTUnwrap(RadioGenerationOptions(prompt: "#shoegaze", mode: .hard))
        await model.generate(options: second)

        XCTAssertEqual(model.mix, previous)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isGenerating)
    }

    func testCancelIgnoresLateResult() async throws {
        let provider = RadioProviderSpy(delay: .milliseconds(60))
        let model = RadioModel(provider: provider)
        let options = try XCTUnwrap(RadioGenerationOptions(prompt: "#ambient", mode: .medium))

        let task = Task { await model.generate(options: options) }
        await Task.yield()
        model.cancel()
        await task.value

        XCTAssertNil(model.mix)
        XCTAssertFalse(model.isGenerating)
    }
}

private actor RadioProviderSpy: RadioProviding {
    private let delay: Duration
    private var error: RadioProviderError?
    private var calls = 0

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    func generate(options: RadioGenerationOptions) async throws -> RadioMix {
        calls += 1
        if delay > .zero { try await ContinuousClock().sleep(for: delay) }
        if let error { throw error }
        return RadioMix(
            options: options,
            title: "Fixture radio",
            annotation: nil,
            feedback: [],
            tracks: [],
            metadataEnrichmentFailed: false,
            generatedAt: .now
        )
    }

    func setError(_ error: RadioProviderError?) { self.error = error }
    func callCount() -> Int { calls }
}
