import Foundation
import Combine

@MainActor
final class IndoorIMDFExperimentService: ObservableObject {
    @Published private(set) var output = "IMDF import is ready. Select a valid Indoor Mapping Data Format file."
    @Published private(set) var status: ExperimentStatus = .available

    func load(url: URL) {
        do {
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let document = object as? [String: Any] else {
                status = .unavailable
                output = "IMDF error: the root value is not a JSON object."
                return
            }
            let featureCollections = document.keys.filter { $0.lowercased().contains("geojson") || $0.lowercased().contains("feature") }
            let featureCount = document.values.reduce(0) { partial, value in
                guard let collection = value as? [String: Any], let features = collection["features"] as? [Any] else { return partial }
                return partial + features.count
            }
            status = .available
            output = "IMDF JSON loaded.\nTop-level keys: \(document.keys.sorted().joined(separator: ", "))\nFeature collections: \(featureCollections.count)\nFeatures found: \(featureCount)"
        } catch {
            status = .unavailable
            output = "IMDF import error: \(error.localizedDescription)"
        }
    }

    func reportImportFailure(_ error: Error) {
        status = .unavailable
        output = "File import error: \(error.localizedDescription)"
    }
}
