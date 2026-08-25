import Foundation
import Combine

#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

#if canImport(HealthKit) && !os(macOS) && !os(tvOS)
import HealthKit
#endif

#if canImport(PassKit) && !os(watchOS)
import PassKit
#endif

@MainActor
final class AIExperimentService: ObservableObject {
    @Published private(set) var output = "On-device language analysis is ready."
    @Published var input = "Joris Apple Toolbox explores native Apple technologies."

    func analyze() {
        #if canImport(NaturalLanguage)
        let text = input
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage?.rawValue ?? "Unknown"
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3).map { "\($0.key.rawValue): \($0.value.formatted(.percent.precision(.fractionLength(1))))" }.joined(separator: "\n")
        output = "Input: \(text)\nDominant language: \(language)\nHypotheses:\n\(hypotheses)"
        #else
        output = "NaturalLanguage is not available on this platform."
        #endif
    }
}

struct HealthExperimentService {
    static func statusText() -> String {
        #if canImport(HealthKit) && !os(macOS) && !os(tvOS)
        return HKHealthStore.isHealthDataAvailable() ? "HealthKit is available. Reading health data requires explicit user authorization and HealthKit entitlement." : "HealthKit is not available on this device."
        #else
        return "HealthKit is not available on this platform."
        #endif
    }
}

struct WalletExperimentService {
    static func statusText() -> String {
        #if canImport(PassKit) && !os(watchOS)
        let library = PKPassLibrary()
        return "PassKit is available. Stored passes visible to this app: \(library.passes().count)\nAdvanced credentials require Apple-issued entitlements and approval."
        #else
        return "PassKit pass library is not available on this platform."
        #endif
    }
}

struct FoundationModelsExperimentService {
    static func statusText() -> String {
        #if canImport(FoundationModels)
        return "Foundation Models framework is present. Model availability depends on device, OS, Apple Intelligence state, and region."
        #else
        return "Foundation Models is not present in this SDK/platform target."
        #endif
    }
}
