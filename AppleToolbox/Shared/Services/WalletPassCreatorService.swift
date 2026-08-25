import Foundation
import Combine

@MainActor
final class WalletPassCreatorService: ObservableObject {
    @Published var passName = "Apple Toolbox Pass"
    @Published var organizationName = "Joris Apple Toolbox"
    @Published var serialNumber = "toolbox-001"
    @Published private(set) var output = "No Wallet pass draft created yet."
    @Published private(set) var draftURL: URL?

    func createDraft() {
        let pass: [String: Any] = [
            "formatVersion": 1,
            "passTypeIdentifier": "pass.example.replace-with-your-pass-type-id",
            "serialNumber": serialNumber,
            "teamIdentifier": "REPLACE_WITH_TEAM_IDENTIFIER",
            "organizationName": organizationName,
            "description": passName,
            "foregroundColor": "rgb(255,255,255)",
            "backgroundColor": "rgb(35,35,40)",
            "labelColor": "rgb(180,180,190)",
            "generic": [
                "primaryFields": [["key": "name", "label": "PASS", "value": passName]],
                "secondaryFields": [["key": "organization", "label": "ORGANIZATION", "value": organizationName]],
                "auxiliaryFields": [["key": "serial", "label": "SERIAL", "value": serialNumber]]
            ]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: pass, options: [.prettyPrinted, .sortedKeys])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("apple-toolbox-pass-draft.json")
            try data.write(to: url, options: .atomic)
            draftURL = url
            output = "Wallet pass draft created.\n\(url.path)\n\nThis is valid pass.json content, but it is not installable yet. Apple Wallet requires a signed .pkpass package with a Pass Type ID certificate."
        } catch {
            output = "Could not create Wallet pass draft: \(error.localizedDescription)"
            draftURL = nil
        }
    }
}
