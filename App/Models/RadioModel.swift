import Foundation
import Observation

@MainActor
@Observable
final class RadioModel {
    private let provider: any RadioProviding
    private var requestID: UUID?

    private(set) var mix: RadioMix?
    private(set) var isGenerating = false
    private(set) var errorMessage: String?

    init(provider: any RadioProviding) {
        self.provider = provider
    }

    func generate(options: RadioGenerationOptions) async {
        guard !isGenerating else { return }
        let id = UUID()
        requestID = id
        isGenerating = true
        errorMessage = nil

        do {
            let generated = try await provider.generate(options: options)
            try Task.checkCancellation()
            guard requestID == id else { return }
            mix = generated
            isGenerating = false
        } catch is CancellationError {
            guard requestID == id else { return }
            isGenerating = false
        } catch {
            guard requestID == id else { return }
            errorMessage = error.localizedDescription
            isGenerating = false
        }
    }

    func cancel() {
        requestID = nil
        isGenerating = false
    }

    func clearError() {
        errorMessage = nil
    }
}
